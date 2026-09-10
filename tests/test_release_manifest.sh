#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_context="${FIXTURE_CONTEXT:-native}"
fixture_root="$(mktemp -d)"
module_root="${fixture_root}/module"
methodology_root="${fixture_root}/methodology"
packaged_methodology_root="${fixture_root}/packaged-methodology"
report_dir="${module_root}/reports"
output_dir="${report_dir}/release_manifest/${fixture_context}"
release_tool="${flow_root}/ci/release_manifest.py"

trap 'rm -rf "${fixture_root}"' EXIT

mkdir -p \
  "${module_root}/config" \
  "${module_root}/constraints" \
  "${module_root}/filelists" \
  "${module_root}/reports/verible_lint" \
  "${module_root}/reports/pyuvm_open_source" \
  "${module_root}/reports/qualification" \
  "${module_root}/rtl" \
  "${module_root}/tools" \
  "${module_root}/verif/pyuvm" \
  "${methodology_root}" \
  "${packaged_methodology_root}"

cp "${flow_root}/VERSION" "${methodology_root}/VERSION"
cp "${flow_root}/VERSION" "${packaged_methodology_root}/VERSION"

cat >"${module_root}/.gitignore" <<'EOF'
reports/
EOF
cat >"${module_root}/config/design.mk" <<'EOF'
DESIGN_TOP := release_fixture
EOF
cat >"${module_root}/config/flows.mk" <<'EOF'
FLOW_verible_lint := enabled
FLOW_pyuvm_open_source := enabled
FLOW_openroad := disabled
EOF
cat >"${module_root}/constraints/timing.sdc" <<'EOF'
create_clock -name clk -period 10 [get_ports clk]
EOF
cat >"${module_root}/rtl/release_fixture.sv" <<'EOF'
module release_fixture(input logic clk);
endmodule
EOF
cat >"${module_root}/verif/pyuvm/test_release_fixture.py" <<'EOF'
"""Release manifest fixture test module."""
EOF
cat >"${module_root}/filelists/rtl.f" <<'EOF'
+incdir+rtl
rtl/release_fixture.sv
EOF
cat >"${module_root}/filelists/pyuvm.f" <<'EOF'
-f filelists/rtl.f
EOF
cat >"${module_root}/tools/fake_tool.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'fixture-tool 1.2.3\n'
EOF
chmod +x "${module_root}/tools/fake_tool.sh"

printf 'PASS\n' >"${report_dir}/verible_lint/status.txt"
printf 'PASS\n' >"${report_dir}/pyuvm_open_source/status.txt"
printf 'PASS\n' >"${report_dir}/qualification/status.txt"
cat >"${report_dir}/pyuvm_open_source/versions.log" <<EOF
python=3.12.3
pyuvm=5.0.0
cocotb=2.1.0
simulator=verilator
simulator_executable=${module_root}/tools/fake_tool.sh
simulator_version<<VERSION_EOF
fixture-tool 1.2.3
VERSION_EOF
EOF
printf 'native HDL coverage\n' >"${report_dir}/pyuvm_open_source/coverage.info"
printf '{"covered":1,"total":1}\n' \
  >"${report_dir}/pyuvm_open_source/functional-coverage.json"
printf '{"review":"complete"}\n' >"${report_dir}/qualification/summary.json"

git -C "${module_root}" init --quiet
git -C "${module_root}" config user.email fixture@example.invalid
git -C "${module_root}" config user.name "MOSAIC fixture"
git -C "${module_root}" add .
git -C "${module_root}" commit --quiet -m fixture
git -C "${methodology_root}" init --quiet
git -C "${methodology_root}" config user.email fixture@example.invalid
git -C "${methodology_root}" config user.name "MOSAIC fixture"
git -C "${methodology_root}" add VERSION
git -C "${methodology_root}" commit --quiet -m fixture
module_revision="$(git -C "${module_root}" rev-parse HEAD)"
methodology_revision="$(git -C "${methodology_root}" rev-parse HEAD)"

manifest_environment=(
  "MODULE_ROOT=${module_root}"
  "FLOW_ROOT=${methodology_root}"
  "REPORT_DIR=${report_dir}"
  "MOSAIC_FLOW_IDS=verible_lint pyuvm_open_source openroad"
  "DISABLED_FLOWS=openroad"
  "RELEASE_MODULE_NAME=release_fixture"
  "MODULE_REVISION=${module_revision}"
  "METHODOLOGY_REVISION=${methodology_revision}"
  "RELEASE_EXECUTION_CONTEXT=${fixture_context}"
  "RELEASE_ALLOW_DIRTY=disabled"
  "RELEASE_TECHNOLOGY=fixture-technology"
  'RELEASE_TECHNOLOGY_METADATA_JSON={"corner":"typical"}'
  'RELEASE_METADATA_JSON={"qualification":"fixture"}'
  "RELEASE_EXECUTION_METADATA_JSON={\"fixture_context\":\"${fixture_context}\"}"
  "RELEASE_ADDITIONAL_TOOLS_JSON=[{\"name\":\"custom_analyzer\",\"command\":[\"${module_root}/tools/fake_tool.sh\",\"--version\"],\"flows\":[]}]"
  "RELEASE_SUPPLEMENTAL_GATES=qualification"
  "RELEASE_INPUT_FILES=${module_root}/config/design.mk ${module_root}/config/flows.mk ${module_root}/constraints"
  "RELEASE_FILELISTS=${module_root}/filelists/rtl.f ${module_root}/filelists/pyuvm.f"
  "RELEASE_ADDITIONAL_EVIDENCE=${report_dir}/qualification/summary.json"
  "VERIBLE_LINT_CMD=${module_root}/tools/fake_tool.sh"
  "PYUVM_PYTHON=${module_root}/tools/fake_tool.sh"
)

generate_manifest() {
  local destination="$1"
  shift
  env "${manifest_environment[@]}" "$@" \
    python3 "${release_tool}" generate \
      --module-root "${module_root}" \
      --flow-root "${methodology_root}" \
      --report-dir "${report_dir}" \
      --output-dir "${destination}"
}

generate_packaged_manifest() {
  local destination="$1"
  shift
  env "${manifest_environment[@]}" \
    "FLOW_ROOT=${packaged_methodology_root}" \
    "$@" \
    python3 "${release_tool}" generate \
      --module-root "${module_root}" \
      --flow-root "${packaged_methodology_root}" \
      --report-dir "${report_dir}" \
      --output-dir "${destination}"
}

expect_failure() {
  local expected_message="$1"
  shift
  if "$@" >"${fixture_root}/negative.log" 2>&1; then
    echo "Release fixture unexpectedly accepted invalid evidence" >&2
    exit 1
  fi
  grep -Fq "${expected_message}" "${fixture_root}/negative.log"
}

generate_manifest "${output_dir}" >/dev/null
python3 "${release_tool}" validate --manifest "${output_dir}/manifest.json" >/dev/null

python3 - "${output_dir}/manifest.json" "${fixture_context}" <<'PY'
import json
import pathlib
import re
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
context = sys.argv[2]
deterministic = manifest["deterministic"]

assert manifest["schema"] == "mosaic-release-evidence-v1"
assert deterministic["identity"]["execution_context"] == context
assert re.fullmatch(r"[0-9a-f]{40}", deterministic["identity"]["module_revision"])
assert deterministic["technology"] == {
    "details": {"corner": "typical"},
    "name": "fixture-technology",
}
assert {flow["id"]: flow["status"] for flow in deterministic["flows"]} == {
    "openroad": "SKIP",
    "pyuvm_open_source": "PASS",
    "verible_lint": "PASS",
}
assert deterministic["supplemental_gates"][0]["id"] == "qualification"
assert {tool["name"] for tool in deterministic["tools"]} >= {
    "cocotb", "custom_analyzer", "python", "pyuvm",
    "verible-verilog-lint", "verilator"
}
custom_tool = next(tool for tool in deterministic["tools"]
                   if tool["name"] == "custom_analyzer")
assert custom_tool["command"] == ["fake_tool.sh", "--version"]
assert all(re.fullmatch(r"[0-9a-f]{64}", item["sha256"])
           for item in deterministic["inputs"])
assert all(not pathlib.Path(item["path"]).is_absolute()
           for item in deterministic["inputs"])
input_paths = {item["path"] for item in deterministic["inputs"]}
assert {"config/design.mk", "config/flows.mk", "constraints/timing.sdc",
        "filelists/rtl.f", "rtl/release_fixture.sv"} <= input_paths
coverage_kinds = {item["kind"] for item in deterministic["evidence"]["coverage"]}
assert coverage_kinds == {"pyuvm_functional", "systemverilog_native_report"}
assert deterministic["evidence"]["additional"][0]["path"] == \
    "reports/qualification/summary.json"
assert manifest["volatile"]["source_tree"] == {
    "methodology_dirty": False,
    "module_dirty": False,
}
PY

cp "${output_dir}/manifest.json" "${fixture_root}/first.json"
generate_manifest "${output_dir}" >/dev/null
python3 - "${fixture_root}/first.json" "${output_dir}/manifest.json" <<'PY'
import json
import pathlib
import sys

first = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
second = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
assert first["deterministic"] == second["deterministic"]
PY

expect_failure "Cannot inspect methodology source tree" \
  generate_packaged_manifest "${output_dir}"
generate_packaged_manifest "${output_dir}" \
  RELEASE_METHODOLOGY_DIRTY=false >/dev/null
expect_failure "methodology dirty state must be true or false" \
  generate_packaged_manifest "${output_dir}" \
    RELEASE_METHODOLOGY_DIRTY=unknown

generate_manifest "${output_dir}" \
  CI=false MODULE_REVISION= >/dev/null
expect_failure "module revision must be supplied explicitly in CI" \
  generate_manifest "${output_dir}" CI=true MODULE_REVISION=
expect_failure "module revision must be supplied explicitly in CI" \
  generate_manifest "${output_dir}" CI=1 MODULE_REVISION=

printf 'FAIL\n' >"${report_dir}/verible_lint/status.txt"
expect_failure "Required flow verible_lint has status FAIL" \
  generate_manifest "${output_dir}"
test "$(<"${output_dir}/status.txt")" = FAIL

printf 'BLOCKED\n' >"${report_dir}/verible_lint/status.txt"
expect_failure "Required flow verible_lint has status BLOCKED" \
  generate_manifest "${output_dir}"

rm "${report_dir}/verible_lint/status.txt"
expect_failure "Required flow verible_lint is missing status evidence" \
  generate_manifest "${output_dir}"
printf 'PASS\n' >"${report_dir}/verible_lint/status.txt"

mkdir -p "${report_dir}/openroad"
printf 'PASS\n' >"${report_dir}/openroad/status.txt"
expect_failure "Disabled flow openroad has status PASS" \
  generate_manifest "${output_dir}"
rm "${report_dir}/openroad/status.txt"

rm "${report_dir}/qualification/status.txt"
expect_failure "Supplemental gate qualification is missing status evidence" \
  generate_manifest "${output_dir}"
printf 'PASS\n' >"${report_dir}/qualification/status.txt"

expect_failure "module revision must contain exactly 40 hex digits" \
  generate_manifest "${output_dir}" MODULE_REVISION=bad-revision
expect_failure "Required release input is missing" \
  generate_manifest "${output_dir}" \
    "RELEASE_INPUT_FILES=${module_root}/config/missing.mk"

touch "${module_root}/dirty-marker"
expect_failure "Dirty source tree detected for module" \
  generate_manifest "${output_dir}"
generate_manifest "${output_dir}" RELEASE_ALLOW_DIRTY=enabled >/dev/null
python3 - "${output_dir}/manifest.json" <<'PY'
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert manifest["volatile"]["source_tree"]["module_dirty"] is True
PY

rm "${module_root}/dirty-marker"
touch "${methodology_root}/dirty-marker"
expect_failure "Dirty source tree detected for methodology" \
  generate_manifest "${output_dir}"

echo "Release manifest ${fixture_context} fixture passed"
