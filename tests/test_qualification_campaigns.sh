#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf "${fixture_root}"' EXIT
mkdir -p "${fixture_root}/config"

write_manifest() {
    local negative_exit="$1"
    local negative_diagnostic="$2"
    local four_state_exit="$3"
    local manifest="${fixture_root}/config/qualification-campaigns.json"
    python3 - "${manifest}" "${negative_exit}" "${negative_diagnostic}" \
        "${four_state_exit}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
negative_exit = int(sys.argv[2])
negative_diagnostic = sys.argv[3]
four_state_exit = int(sys.argv[4])
driver = "{flow_root}/tests/fixtures/qualification_driver.py"

def phase(expected, diagnostic, exit_code, failure_class=None, name="run"):
    value = {
        "name": name,
        "command": [
            "{python}", driver, "--diagnostic", diagnostic,
            "--exit-code", str(exit_code),
        ],
        "expected": expected,
        "diagnostic": diagnostic,
    }
    if failure_class:
        value["failure_class"] = failure_class
    return value

manifest = {
    "schema": "mosaic-qualification-campaigns-v1",
    "campaigns": {
        "negative": {
            "infrastructure_diagnostics": ["UNRELATED_TOOL_FAILURE"],
            "cases": [
                {
                    "id": "positive_control", "evidence": "positive_control",
                    "role": "positive_control", "kind": "positive_control",
                    "phases": [phase("success", "POSITIVE_CONTROL_PASS", 0)],
                },
                {
                    "id": "detected_mutation", "evidence": "detected_mutation",
                    "role": "negative", "kind": "simulation_mutation",
                    "positive_control": "positive_control",
                    "phases": [phase(
                        "failure", negative_diagnostic, negative_exit, "assertion"
                    )],
                },
                {
                    "id": "expected_eqy_mismatch", "evidence": "expected_eqy_mismatch",
                    "role": "negative", "kind": "equivalence_mismatch",
                    "positive_control": "positive_control",
                    "phases": [phase(
                        "failure", "Successfully proved designs inequivalent", 1,
                        "equivalence"
                    )],
                },
            ],
        },
        "four_state": {
            "simulator": "iverilog",
            "cases": [
                {
                    "id": "disabled_monitor", "evidence": "disabled_monitor",
                    "role": "disabled_monitor_control", "kind": "stimulus_control",
                    "injections": [{"control": "enable_i", "values": ["X", "Z"]}],
                    "phases": [
                        {
                            "name": "compile",
                            "command": [
                                "{iverilog}", "--diagnostic", "COMPILE_PASS",
                                "--exit-code", "0"
                            ],
                            "expected": "success"
                        },
                        {
                            "name": "run",
                            "command": [
                                "{vvp}", "--diagnostic", "UNKNOWN_STIMULUS_REACHED",
                                "--exit-code", "0"
                            ],
                            "expected": "success",
                            "diagnostic": "UNKNOWN_STIMULUS_REACHED"
                        }
                    ],
                },
                {
                    "id": "unknown_control", "evidence": "unknown_control",
                    "role": "unknown_detection", "kind": "control_unknown",
                    "monitor_control": "disabled_monitor",
                    "injections": [{"control": "enable_i", "values": ["X", "Z"]}],
                    "phases": [
                        {
                            "name": "compile",
                            "command": [
                                "{iverilog}", "--diagnostic", "COMPILE_PASS",
                                "--exit-code", "0"
                            ],
                            "expected": "success"
                        },
                        {
                            "name": "run",
                            "command": [
                                "{vvp}", "--diagnostic", "UNKNOWN_CONTROL_DETECTED",
                                "--exit-code", str(four_state_exit)
                            ],
                            "expected": "failure",
                            "diagnostic": "UNKNOWN_CONTROL_DETECTED",
                            "failure_class": "unknown_control"
                        }
                    ],
                },
            ],
        },
    },
}
path.write_text(json.dumps(manifest), encoding="utf-8")
PY

    fake_tools="${fixture_root}/fake-tools"
    mkdir -p "${fake_tools}"
    cp "${flow_root}/tests/fixtures/qualification_driver.py" "${fake_tools}/iverilog"
    cp "${flow_root}/tests/fixtures/qualification_driver.py" "${fake_tools}/vvp"
    chmod +x "${fake_tools}/iverilog" "${fake_tools}/vvp"
    export IVERILOG_CMD="${fake_tools}/iverilog"
    export VVP_CMD="${fake_tools}/vvp"
}

run_campaign() {
    local campaign="$1"
    local name="$2"
    "${flow_root}/ci/qualification_campaign.py" \
        --campaign "${campaign}" \
        --manifest "${fixture_root}/config/qualification-campaigns.json" \
        --module-root "${fixture_root}" --flow-root "${flow_root}" \
        --report-dir "${fixture_root}/reports/${name}" \
        --work-dir "${fixture_root}/work/${name}"
}

expect_failure() {
    if "$@" >"${fixture_root}/failure.log" 2>&1; then
        echo "Qualification fixture unexpectedly passed" >&2
        exit 1
    fi
}

write_manifest 1 ASSERTION_FAILURE_DETECTED 1
run_campaign negative negative-pass >/dev/null
run_campaign four_state four-state-pass >/dev/null
grep -Fq '"classification": "expected_assertion_failure"' \
    "${fixture_root}/reports/negative-pass/detected_mutation/summary.json"
grep -Fq '"classification": "expected_equivalence_failure"' \
    "${fixture_root}/reports/negative-pass/expected_eqy_mismatch/summary.json"
python3 - "${fixture_root}" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
negative = json.loads(
    (root / "reports/negative-pass/summary.json").read_text(encoding="utf-8")
)
four_state = json.loads(
    (root / "reports/four-state-pass/summary.json").read_text(encoding="utf-8")
)
assert negative["status"] == "PASS"
assert four_state["status"] == "PASS"
assert four_state["simulator"] == "iverilog"
assert all(case["status"] == "PASS" for case in negative["cases"])
assert all(case["status"] == "PASS" for case in four_state["cases"])
for report in (
    root / "reports/negative-pass/detected_mutation",
    root / "reports/four-state-pass/iverilog/unknown_control",
):
    assert (report / "status.txt").read_text(encoding="utf-8").strip() == "PASS"
    assert (report / "summary.json").is_file()
    assert (report / "run-command.json").is_file()
    assert (report / "run-result.json").is_file()
    assert (report / "run.log").is_file()
PY

write_manifest 0 ASSERTION_FAILURE_DETECTED 1
expect_failure run_campaign negative escaped-mutation
grep -Fq '"classification": "escaped_fault"' \
    "${fixture_root}/reports/escaped-mutation/detected_mutation/summary.json"
test "$(<"${fixture_root}/reports/escaped-mutation/status.txt")" = FAIL

write_manifest 2 UNRELATED_TOOL_FAILURE 1
expect_failure run_campaign negative infrastructure-failure
grep -Fq '"classification": "infrastructure_failure"' \
    "${fixture_root}/reports/infrastructure-failure/detected_mutation/summary.json"

write_manifest 1 ASSERTION_FAILURE_DETECTED 0
expect_failure run_campaign four_state broken-monitor
grep -Fq '"classification": "escaped_fault"' \
    "${fixture_root}/reports/broken-monitor/iverilog/unknown_control/summary.json"

write_manifest 1 ASSERTION_FAILURE_DETECTED 1
python3 - "${fixture_root}/config/qualification-campaigns.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text(encoding="utf-8"))
control = manifest["campaigns"]["four_state"]["cases"][0]
control["phases"][0]["diagnostic"] = "BROKEN_CONTROL_MARKER"
path.write_text(json.dumps(manifest), encoding="utf-8")
PY
expect_failure run_campaign four_state broken-control
grep -Fq '"classification": "blocked_by_control"' \
    "${fixture_root}/reports/broken-control/iverilog/unknown_control/summary.json"

write_manifest 1 ASSERTION_FAILURE_DETECTED 1
python3 - "${fixture_root}/config/qualification-campaigns.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text(encoding="utf-8"))
manifest["campaigns"]["negative"]["inputs"] = ["missing-mutation.sv"]
path.write_text(json.dumps(manifest), encoding="utf-8")
PY
expect_failure run_campaign negative missing-input
grep -Fq 'campaign input is missing: missing-mutation.sv' \
    "${fixture_root}/reports/missing-input/summary.json"

skip_reports="${fixture_root}/skip-reports"
env \
    MOSAIC_FLOW_IDS="negative_qualification four_state_qualification" \
    FLOW_negative_qualification=disabled FLOW_four_state_qualification=disabled \
    FLOW_DEPENDENCIES_negative_qualification= FLOW_DEPENDENCIES_four_state_qualification= \
    DISABLED_FLOWS="negative_qualification four_state_qualification" \
    REPORT_DIR="${skip_reports}" MODULE_ROOT="${fixture_root}" \
    "${flow_root}/ci/run_flow.sh" negative_qualification false >/dev/null
test "$(<"${skip_reports}/negative_qualification/status.txt")" = SKIP
env \
    MOSAIC_FLOW_IDS="negative_qualification four_state_qualification" \
    FLOW_negative_qualification=disabled FLOW_four_state_qualification=disabled \
    FLOW_DEPENDENCIES_negative_qualification= FLOW_DEPENDENCIES_four_state_qualification= \
    DISABLED_FLOWS="negative_qualification four_state_qualification" \
    REPORT_DIR="${skip_reports}" MODULE_ROOT="${fixture_root}" \
    "${flow_root}/ci/run_flow.sh" four_state_qualification false >/dev/null
test "$(<"${skip_reports}/four_state_qualification/status.txt")" = SKIP

echo "Qualification campaign tests passed"
