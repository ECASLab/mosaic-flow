#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
report_root="${flow_root}/tests/fixture-parameter-profiles/reports"
work_root="${flow_root}/tests/fixture-parameter-profiles/work"

python3 - "${report_root}" "${work_root}" <<'PY'
import json
import pathlib
import sys

report_root = pathlib.Path(sys.argv[1])
work_root = pathlib.Path(sys.argv[2])
summary = json.loads(
    (report_root / "parameter-profile-summary.json").read_text(encoding="utf-8")
)

expected_parameters = {
    "width_min": {"FEATURE_INVERT": False, "WIDTH": 1},
    "nominal": {"FEATURE_INVERT": False, "WIDTH": 8},
    "feature_invert": {"FEATURE_INVERT": True, "WIDTH": 5},
    "elaboration_only": {"FEATURE_INVERT": False, "WIDTH": 3},
}
portable_flows = {
    "verible_lint",
    "verible_format",
    "slang_elaboration",
    "verilator_lint",
    "yosys_synthesis",
    "symbiyosys_formal",
    "eqy_equivalence",
    "verilator_sim",
    "pyuvm_open_source",
}
reported_flows = portable_flows | {"coverage_qualification"}
elaboration_flows = {
    "verible_lint",
    "verible_format",
    "slang_elaboration",
    "verilator_lint",
}

assert summary["aggregate_status"] == "PASS"
assert [entry["profile"] for entry in summary["profiles"]] == list(
    expected_parameters
)

for entry in summary["profiles"]:
    profile = entry["profile"]
    assert entry["parameters"] == expected_parameters[profile]
    expected_pass = elaboration_flows if profile == "elaboration_only" else portable_flows
    assert set(entry["statuses"]) == reported_flows
    for flow, status in entry["statuses"].items():
        assert status == ("PASS" if flow in expected_pass else "SKIP"), (
            profile,
            flow,
            status,
        )

    evidence = json.loads(
        (report_root / profile / "parameter-profile.json").read_text(
            encoding="utf-8"
        )
    )
    assert evidence["parameters"] == expected_parameters[profile]

for profile in ("width_min", "nominal", "feature_invert"):
    parameters = expected_parameters[profile]
    expected_commands = {
        f"chparam -set FEATURE_INVERT {int(parameters['FEATURE_INVERT'])} profile_fixture_formal",
        f"chparam -set WIDTH {parameters['WIDTH']} profile_fixture_formal",
    }
    formal_config = (
        report_root / profile / "symbiyosys_formal" / "profile.sby"
    ).read_text(encoding="utf-8")
    assert expected_commands.issubset(set(formal_config.splitlines()))

    eqy_config = (report_root / profile / "eqy_equivalence" / "profile.eqy").read_text(
        encoding="utf-8"
    )
    expected_netlist = (
        work_root / profile / "yosys_synthesis" / "profile_fixture_netlist.v"
    )
    assert str(expected_netlist) in eqy_config
    assert expected_netlist.is_file()
    assert f"chparam -set WIDTH {parameters['WIDTH']} profile_fixture" in eqy_config
    assert (
        f"chparam -set FEATURE_INVERT {int(parameters['FEATURE_INVERT'])} "
        "profile_fixture"
    ) in eqy_config

print("Parameter-profile fixture evidence is complete and isolated")
PY
