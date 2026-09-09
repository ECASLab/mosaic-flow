#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="${flow_root}/tests/fixture-parameter-profiles"
temporary_root="$(mktemp -d)"
trap 'find "${temporary_root}" -depth -delete; make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" clean' EXIT

make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" profile-manifest-check >/dev/null
profile_list="$(make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" profile-list)"
if [[ "${profile_list}" != $'width_min\nnominal\nfeature_invert\nelaboration_only' ]]; then
  echo "Profile list is not deterministic: ${profile_list}" >&2
  exit 1
fi

profile_matrix="$(make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" profile-matrix)"
python3 -c '
import json
import sys

matrix = json.loads(sys.argv[1])
assert [entry["profile"] for entry in matrix["include"]] == [
    "width_min", "nominal", "feature_invert", "elaboration_only"
]
assert len({entry["job_name"] for entry in matrix["include"]}) == 4
assert all(entry["module"] == "profile_fixture" for entry in matrix["include"])
' "${profile_matrix}"

if make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" flow-config-check \
  >"${temporary_root}/missing-selection.log" 2>&1; then
  echo "A parameterized flow ran without selecting PROFILE" >&2
  exit 1
fi
grep -Fq "select PROFILE=<name>" "${temporary_root}/missing-selection.log"

if make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" PROFILE=nominal \
  FLOW_yosys_synthesis=disabled flow-config-check \
  >"${temporary_root}/policy-conflict.log" 2>&1; then
  echo "A profile required a flow disabled by module policy" >&2
  exit 1
fi
grep -Fq "requires flows disabled by module policy: yosys_synthesis" \
  "${temporary_root}/policy-conflict.log"

for profile in width_min nominal feature_invert elaboration_only; do
  make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" \
    PROFILE="${profile}" profile-probe
  test -f "${fixture_root}/reports/${profile}/parameter-profile.json"
  test -f "${fixture_root}/reports/${profile}/probe/status.txt"
done

python3 -c '
import json
import pathlib

root = pathlib.Path("tests/fixture-parameter-profiles/reports")
assert json.loads((root / "width_min/parameter-profile.json").read_text())["parameters"] == {
    "FEATURE_INVERT": False,
    "WIDTH": 1,
}
evidence = json.loads((root / "feature_invert/parameter-profile.json").read_text())
assert evidence["parameters"] == {"FEATURE_INVERT": True, "WIDTH": 5}
assert evidence["tops"]["formal"] == "profile_fixture_formal"
'

make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" PROFILE=width_min clean
test ! -e "${fixture_root}/reports/width_min/probe/status.txt"
test -e "${fixture_root}/reports/nominal/probe/status.txt"

make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" clean
make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" \
  PROFILE_TARGET=profile-probe PROFILE_JOBS=2 all-profiles
for profile in width_min nominal feature_invert elaboration_only; do
  test "$(<"${fixture_root}/reports/${profile}/probe/status.txt")" = PASS
done
python3 -c '
import json
import pathlib

summary = json.loads(
    pathlib.Path("tests/fixture-parameter-profiles/reports/parameter-profile-summary.json").read_text()
)
assert summary["aggregate_status"] == "PASS"
assert all(item["statuses"]["probe"] == "PASS" for item in summary["profiles"])
'

make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" clean
if make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" \
  PROFILE_TARGET=profile-probe PROFILE_JOBS=2 FAIL_PROFILE=nominal all-profiles \
  >"${temporary_root}/aggregate-failure.log" 2>&1; then
  echo "Profile aggregate accepted a failing required profile" >&2
  exit 1
fi
test "$(<"${fixture_root}/reports/width_min/probe/status.txt")" = PASS
test "$(<"${fixture_root}/reports/nominal/probe/status.txt")" = FAIL
test "$(<"${fixture_root}/reports/feature_invert/probe/status.txt")" = PASS
test "$(<"${fixture_root}/reports/elaboration_only/probe/status.txt")" = PASS
python3 -c '
import json
import pathlib

summary = json.loads(
    pathlib.Path("tests/fixture-parameter-profiles/reports/parameter-profile-summary.json").read_text()
)
assert summary["aggregate_status"] == "FAIL"
assert summary["profiles"][1]["statuses"]["probe"] == "FAIL"
'

if make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" \
  PROFILE_TARGET=all-profiles all-profiles >/dev/null 2>&1; then
  echo "Profile aggregate accepted recursive PROFILE_TARGET=all-profiles" >&2
  exit 1
fi
if make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" \
  PROFILE_JOBS=-1 all-profiles >/dev/null 2>&1; then
  echo "Profile aggregate accepted an invalid PROFILE_JOBS value" >&2
  exit 1
fi

profile_tool="${flow_root}/ci/parameter_profiles.py"
argument_output="$(
  python3 "${profile_tool}" arguments \
    --parameters '{"FEATURE_INVERT":true,"WIDTH":5}' \
    --backend verilator --top profile_fixture
)"
if [[ "${argument_output}" != $'-GFEATURE_INVERT=1\n-GWIDTH=5' ]]; then
  echo "Unexpected Verilator parameter translation: ${argument_output}" >&2
  exit 1
fi

test "$(${profile_tool} arguments --parameters '{"WIDTH":5}' --backend slang --top ignored)" = $'-G\nWIDTH=5'
test "$(${profile_tool} arguments --parameters '{"WIDTH":5}' --backend vcs --top profile_fixture_tb)" = '-pvalue+profile_fixture_tb.WIDTH=5'
test "$(${profile_tool} arguments --parameters '{"FEATURE_INVERT":true,"WIDTH":5}' --backend dc --top ignored)" = 'FEATURE_INVERT=1,WIDTH=5'
test "$(${profile_tool} arguments --parameters '{"WIDTH":5}' --backend yosys --top profile_fixture)" = 'chparam -set WIDTH 5 profile_fixture;'

cat >"${temporary_root}/ambiguous.eqy" <<'EOF'
[gold]
prep -top profile_fixture
[gate]
read_verilog first.v second.v
prep -top profile_fixture
EOF
if "${profile_tool}" render-eqy \
  --input "${temporary_root}/ambiguous.eqy" \
  --output "${temporary_root}/rendered.eqy" \
  --parameters '{"WIDTH":5}' --top profile_fixture \
  --netlist "${temporary_root}/profile_fixture_netlist.v" \
  >"${temporary_root}/ambiguous.log" 2>&1; then
  echo "An ambiguous EQY gate input set was accepted" >&2
  exit 1
fi
grep -Fq "exactly one gate HDL input" "${temporary_root}/ambiguous.log"

mkdir -p "${temporary_root}/blocked/width_min/yosys_synthesis"
printf 'BLOCKED\n' >"${temporary_root}/blocked/width_min/yosys_synthesis/status.txt"
if python3 "${profile_tool}" summary \
  --manifest "${fixture_root}/config/parameter-profiles.json" \
  --report-root "${temporary_root}/blocked" \
  --output "${temporary_root}/blocked-summary.json"; then
  echo "A blocked profile produced a successful summary exit status" >&2
  exit 1
fi
python3 -c '
import json
import pathlib

summary = json.loads(pathlib.Path("'"${temporary_root}"'/blocked-summary.json").read_text())
assert summary["aggregate_status"] == "FAIL"
assert summary["profiles"][0]["statuses"]["yosys_synthesis"] == "BLOCKED"
assert summary["profiles"][1]["statuses"]["aggregate"] == "MISSING"
'

check_invalid_manifest() {
  local manifest_body="$1"
  local expected_message="$2"
  printf '%s\n' "${manifest_body}" >"${temporary_root}/profiles.json"
  if python3 "${profile_tool}" validate --manifest "${temporary_root}/profiles.json" \
    >"${temporary_root}/invalid.log" 2>&1; then
    echo "Invalid parameter-profile manifest was accepted" >&2
    exit 1
  fi
  grep -Fq "${expected_message}" "${temporary_root}/invalid.log"
}

check_invalid_manifest \
  '{"schema":"mosaic-parameter-profiles-v1","include":[{"name":"a","parameters":{},"flows":["slang_elaboration"]},{"name":"a","parameters":{},"flows":["slang_elaboration"]}]}' \
  "Duplicate profile name"
check_invalid_manifest \
  '{"schema":"mosaic-parameter-profiles-v1","include":[{"name":"a","parameters":{"WIDTH":"1;delete"},"flows":["slang_elaboration"]}]}' \
  "unsupported parameter value"
check_invalid_manifest \
  '{"schema":"mosaic-parameter-profiles-v1","include":[{"name":"a","parameters":{"1WIDTH":1},"flows":["slang_elaboration"]}]}' \
  "invalid parameter name"
check_invalid_manifest \
  '{"schema":"mosaic-parameter-profiles-v1","include":[{"name":"a","parameters":{},"flows":["openroad"]}]}' \
  "unsupported flows"
check_invalid_manifest \
  '{"schema":"mosaic-parameter-profiles-v1","include":[{"name":"a","parameters":{},"flows":["eqy_equivalence"]}]}' \
  "requires: yosys_synthesis"

default_profiles="$(
  make -s -C "${flow_root}/tests/fixture-module" FLOW_ROOT="${flow_root}" profile-list
)"
test "${default_profiles}" = default
make -s -C "${flow_root}/tests/fixture-module" FLOW_ROOT="${flow_root}" \
  flow-config-check >/dev/null

combined_matrix="$(
  make -s -C "${flow_root}/tests/fixture-multi-module" FLOW_ROOT="${flow_root}" \
    module-profile-matrix
)"
python3 -c '
import json
import sys

entries = json.loads(sys.argv[1])["include"]
assert [(entry["module"], entry["profile"]) for entry in entries] == [
    ("alpha", "default"), ("beta", "default")
]
assert len({entry["job_name"] for entry in entries}) == 2
' "${combined_matrix}"

profiled_multi_root="${temporary_root}/profiled-multi"
cp -R "${flow_root}/tests/fixture-multi-module" "${profiled_multi_root}"
mkdir -p "${profiled_multi_root}/config/parameter-profiles"
printf '%s\n' \
  '{"schema":"mosaic-parameter-profiles-v1","include":[{"name":"width_min","parameters":{"WIDTH":1},"flows":["slang_elaboration"]},{"name":"nominal","parameters":{"WIDTH":8},"flows":["slang_elaboration"]}]}' \
  >"${profiled_multi_root}/config/parameter-profiles/alpha.json"
combined_matrix="$(
  make -s -C "${profiled_multi_root}" FLOW_ROOT="${flow_root}" \
    module-profile-matrix
)"
python3 -c '
import json
import sys

entries = json.loads(sys.argv[1])["include"]
assert [(entry["module"], entry["profile"]) for entry in entries] == [
    ("alpha", "width_min"), ("alpha", "nominal"), ("beta", "default")
]
assert len({entry["job_name"] for entry in entries}) == 3
' "${combined_matrix}"

echo "Parameter-profile qualification tests passed"
