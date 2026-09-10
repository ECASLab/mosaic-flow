#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest_path="${flow_root}/tests/fixture-module/reports/release_manifest/native/manifest.json"
summary_path="${flow_root}/tests/fixture-module/reports/release_manifest/native/summary.txt"
status_path="${flow_root}/tests/fixture-module/reports/release_manifest/native/status.txt"

test "$(<"${status_path}")" = PASS
grep -Fq "MOSAIC release evidence" "${summary_path}"
grep -Fq "Execution context: native" "${summary_path}"

python3 - "${manifest_path}" "${EXPECT_CLEAN_RELEASE:-false}" <<'PY'
import json
import pathlib
import re
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
expect_clean = sys.argv[2] == "true"
deterministic = manifest["deterministic"]
identity = deterministic["identity"]

assert manifest["schema"] == "mosaic-release-evidence-v1"
assert identity["module"] == "flow_fixture"
assert identity["profile"] == "default"
assert identity["execution_context"] == "native"
assert re.fullmatch(r"[0-9a-f]{40}", identity["module_revision"])
assert re.fullmatch(r"[0-9a-f]{40}", identity["methodology_revision"])

expected_pass = {
    "eqy_equivalence",
    "pyuvm_open_source",
    "coverage_qualification",
    "negative_qualification",
    "four_state_qualification",
    "static_intent",
    "slang_elaboration",
    "symbiyosys_formal",
    "verible_format",
    "verible_lint",
    "verilator_lint",
    "verilator_sim",
    "yosys_synthesis",
}
flow_statuses = {entry["id"]: entry["status"] for entry in deterministic["flows"]}
assert set(flow_statuses) == {
    "eqy_equivalence",
    "openroad",
    "pyuvm_commercial",
    "pyuvm_open_source",
    "coverage_qualification",
    "negative_qualification",
    "four_state_qualification",
    "static_intent",
    "sg_cdc",
    "sg_dft",
    "slang_elaboration",
    "symbiyosys_formal",
    "synopsys_primepower",
    "synopsys_primetime",
    "synopsys_synthesis",
    "vc_cdc",
    "vc_lint",
    "vc_lp",
    "vcs_sim",
    "verible_format",
    "verible_lint",
    "verilator_lint",
    "verilator_sim",
    "yosys_synthesis",
}
assert {
    name for name, status in flow_statuses.items() if status == "PASS"
} == expected_pass
assert all(
    status == "SKIP"
    for name, status in flow_statuses.items()
    if name not in expected_pass
)

expected_tools = {
    "cocotb",
    "eqy",
    "iverilog",
    "python",
    "pyuvm",
    "slang",
    "symbiyosys",
    "verible-verilog-format",
    "verible-verilog-lint",
    "verilator",
    "yosys",
    "vvp",
}
tools = deterministic["tools"]
assert {entry["name"] for entry in tools} == expected_tools
assert all(entry["version"] for entry in tools)
assert all(entry["source"]["sha256"] for entry in tools if "source" in entry)

input_paths = {entry["path"] for entry in deterministic["inputs"]}
assert {
    "config/design.mk",
    "config/coverage-policy.json",
    "config/qualification-campaigns.json",
    "config/qualification-equivalent.eqy",
    "config/qualification-inequivalent.eqy",
    "config/static-intent.json",
    "config/flows.mk",
    "config/formal.sby",
    "config/formal_cover.sby",
    "config/equivalence.eqy",
    "config/openroad.mk",
    "config/verible.rules",
    "config/verible_waivers.txt",
    "config/verilator_waivers.vlt",
    "constraints/timing.sdc",
    "constraints/power.upf",
    "filelists/assertions.f",
    "filelists/coverage.f",
    "filelists/properties.f",
    "filelists/rtl.f",
    "filelists/tb.f",
    "rtl/flow_fixture.sv",
    "verif/mutations/flow_fixture_bad_netlist.v",
    "verif/pyuvm/test_flow_fixture.py",
    "verif/tb/flow_fixture_four_state_tb.sv",
} <= input_paths
assert all(
    re.fullmatch(r"[0-9a-f]{64}", entry["sha256"])
    for entry in deterministic["inputs"]
)
assert not any(
    "__pycache__" in path or path.endswith(".pyc") for path in input_paths
)

coverage = deterministic["evidence"]["coverage"]
assert {(entry["producer"], entry["kind"]) for entry in coverage} >= {
    ("coverage_qualification", "coverage_qualification_summary"),
    ("pyuvm_open_source", "pyuvm_functional"),
    ("pyuvm_open_source", "systemverilog_native_report"),
    ("verilator_sim", "systemverilog_native_report"),
}
additional_paths = {entry["path"] for entry in deterministic["evidence"]["additional"]}
assert {
    "reports/negative_qualification/summary.json",
    "reports/four_state_qualification/summary.json",
    "reports/static_intent/sdc-findings.json",
    "reports/static_intent/upf-findings.json",
    "reports/static_intent/summary.json",
} <= additional_paths
if expect_clean:
    assert manifest["volatile"]["source_tree"] == {
        "methodology_dirty": False,
        "module_dirty": False,
    }
PY

echo "Complete fixture release manifest is valid"
