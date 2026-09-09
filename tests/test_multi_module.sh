#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="${flow_root}/tests/fixture-multi-module"
temporary_root="$(mktemp -d)"
trap 'rm -rf "${temporary_root}"; make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" clean' EXIT

make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" module-manifest-check >/dev/null

module_list="$(make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" module-list)"
if [[ "${module_list}" != $'alpha\nbeta' ]]; then
  echo "Module list is not deterministic: ${module_list}" >&2
  exit 1
fi

module_matrix="$(make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" module-matrix)"
python3 -c '
import json
import sys

matrix = json.loads(sys.argv[1])
assert [entry["name"] for entry in matrix["include"]] == ["alpha", "beta"]
assert all(entry["artifact_suffix"] == "native" for entry in matrix["include"])
' "${module_matrix}"

if make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" flow-config-check \
  >"${temporary_root}/missing-selection.log" 2>&1; then
  echo "A multi-module flow ran without selecting MODULE" >&2
  exit 1
fi
grep -Fq "select MODULE=<name>" "${temporary_root}/missing-selection.log"

if make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" MODULE=missing \
  fixture-probe >"${temporary_root}/unknown-selection.log" 2>&1; then
  echo "A multi-module flow accepted an unknown MODULE" >&2
  exit 1
fi
grep -Fq "Unknown MODULE 'missing'" "${temporary_root}/unknown-selection.log"

make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" MODULE=alpha fixture-probe
make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" MODULE=beta fixture-probe

alpha_probe="${fixture_root}/reports/alpha/probe/config.txt"
beta_probe="${fixture_root}/reports/beta/probe/config.txt"
grep -Fq "rtl_filelist=${fixture_root}/filelists/alpha.rtl.f" "${alpha_probe}"
grep -Fq "formal_config=${fixture_root}/flows/symbiyosys/alpha.formal.sby" "${alpha_probe}"
grep -Fq "format_args=--indentation_spaces=4" "${alpha_probe}"
grep -Fq "rtl_filelist=${fixture_root}/filelists/rtl.f" "${beta_probe}"
grep -Fq "formal_config=${fixture_root}/flows/symbiyosys/formal.sby" "${beta_probe}"

make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" MODULE=alpha clean
if [[ -e "${fixture_root}/reports/alpha/probe/status.txt" ]] ||
   [[ -e "${fixture_root}/work/alpha" ]]; then
  echo "Selected clean retained alpha-generated state" >&2
  exit 1
fi
if [[ ! -e "${fixture_root}/reports/beta/probe/status.txt" ]] ||
   [[ ! -e "${fixture_root}/work/beta/probe/output.txt" ]]; then
  echo "Selected clean removed beta-generated state" >&2
  exit 1
fi

make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" clean
make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" \
  TARGET=fixture-probe MODULE_JOBS=2 all-modules
for module_name in alpha beta; do
  test "$(<"${fixture_root}/reports/${module_name}/probe/status.txt")" = PASS
done

make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" clean
if make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" \
  TARGET=fixture-probe MODULE_JOBS=2 FAIL_MODULE=beta all-modules \
  >"${temporary_root}/aggregate-failure.log" 2>&1; then
  echo "Aggregate execution accepted a failing module" >&2
  exit 1
fi
test "$(<"${fixture_root}/reports/alpha/probe/status.txt")" = PASS
test "$(<"${fixture_root}/reports/beta/probe/status.txt")" = FAIL

if make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" \
  TARGET=all-modules all-modules >/dev/null 2>&1; then
  echo "Aggregate execution accepted recursive TARGET=all-modules" >&2
  exit 1
fi
if make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" \
  MODULE_JOBS=-1 all-modules >/dev/null 2>&1; then
  echo "Aggregate execution accepted an invalid MODULE_JOBS value" >&2
  exit 1
fi

mkdir -p "${temporary_root}/config/modules"
touch "${temporary_root}/config/modules/alpha.mk"
touch "${temporary_root}/config/modules/alpha-flows.mk"

check_invalid_manifest() {
  local manifest_body="$1"
  local expected_message="$2"
  printf '%s\n' "${manifest_body}" >"${temporary_root}/config/modules.json"
  if python3 "${flow_root}/ci/module_manifest.py" validate \
    --manifest "${temporary_root}/config/modules.json" \
    --module-root "${temporary_root}" \
    >"${temporary_root}/invalid.log" 2>&1; then
    echo "Invalid module manifest was accepted" >&2
    exit 1
  fi
  grep -Fq "${expected_message}" "${temporary_root}/invalid.log"
}

check_invalid_manifest \
  '{"schema":"mosaic-modules-v1","include":[{"name":"alpha"},{"name":"alpha"}]}' \
  "Duplicate module name"
check_invalid_manifest \
  '{"schema":"mosaic-modules-v1","include":[{"name":"../alpha"}]}' \
  "invalid name"
check_invalid_manifest \
  '{"schema":"wrong","include":[{"name":"alpha"}]}' \
  "schema must be"
check_invalid_manifest \
  '{"schema":"mosaic-modules-v1","include":[{"name":"missing"}]}' \
  "missing design configuration"

rm -f "${temporary_root}/config/modules/alpha-flows.mk"
check_invalid_manifest \
  '{"schema":"mosaic-modules-v1","include":[{"name":"alpha"}]}' \
  "missing flow policy"

# The original import sequence remains valid when no module manifest exists.
make -s -C "${flow_root}/tests/fixture-module" FLOW_ROOT="${flow_root}" \
  flow-config-check >/dev/null

echo "Multi-module project orchestration tests passed"
