#!/usr/bin/env python3
"""Run declarative negative-test and four-state qualification campaigns."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCHEMA = "mosaic-qualification-campaigns-v1"
SUMMARY_SCHEMA = "mosaic-qualification-result-v1"
NAME = re.compile(r"^[a-z][a-z0-9_]*$")
CAMPAIGNS = {"negative", "four_state"}
ROLES = {
    "negative": {"negative", "positive_control"},
    "four_state": {"unknown_detection", "disabled_monitor_control"},
}
PHASES = {"compile", "run"}
FAILURE_CLASSES = {
    "assertion",
    "elaboration",
    "equivalence",
    "mutation",
    "unknown_control",
}
DEFAULT_INFRASTRUCTURE_DIAGNOSTICS = [
    r"command not found",
    r"No such file or directory",
    r"license checkout failed",
    r"internal (?:compiler|tool) error",
    r"INFRASTRUCTURE_FAILURE",
]


class CampaignError(ValueError):
    """Report an invalid campaign or execution contract."""


def write_json(path: Path, value: object) -> None:
    """Write stable, human-readable JSON evidence."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_status(path: Path, status: str) -> None:
    """Write one status using the shared flow evidence contract."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"{status}\n", encoding="utf-8")


def require_fields(value: dict[str, Any], allowed: set[str], required: set[str], label: str) -> None:
    """Reject missing and unknown manifest fields."""
    missing = sorted(required - set(value))
    unknown = sorted(set(value) - allowed)
    if missing:
        raise CampaignError(f"{label} is missing fields: {', '.join(missing)}")
    if unknown:
        raise CampaignError(f"{label} has unknown fields: {', '.join(unknown)}")


def validate_pattern(pattern: object, label: str) -> str:
    """Validate and compile one diagnostic regular expression."""
    if not isinstance(pattern, str) or not pattern:
        raise CampaignError(f"{label} must be a nonempty regular expression")
    try:
        re.compile(pattern)
    except re.error as error:
        raise CampaignError(f"{label} is invalid: {error}") from error
    return pattern


def validate_phase(phase: object, label: str) -> dict[str, Any]:
    """Validate one compile or run phase."""
    if not isinstance(phase, dict):
        raise CampaignError(f"{label} must be an object")
    require_fields(
        phase,
        {
            "name",
            "command",
            "fixture",
            "expected",
            "diagnostic",
            "failure_class",
            "environment",
            "timeout_seconds",
        },
        {"name", "expected"},
        label,
    )
    if phase["name"] not in PHASES:
        raise CampaignError(f"{label}.name must be compile or run")
    if ("command" in phase) == ("fixture" in phase):
        raise CampaignError(f"{label} must define exactly one of command or fixture")
    if "command" in phase and (
        not isinstance(phase["command"], list)
        or not phase["command"]
        or not all(isinstance(item, str) and item for item in phase["command"])
    ):
        raise CampaignError(f"{label}.command must be a nonempty string array")
    if "fixture" in phase and (
        not isinstance(phase["fixture"], str) or not phase["fixture"]
    ):
        raise CampaignError(f"{label}.fixture must be a nonempty path")
    if phase["expected"] not in {"success", "failure"}:
        raise CampaignError(f"{label}.expected must be success or failure")
    if phase["expected"] == "failure":
        validate_pattern(phase.get("diagnostic"), f"{label}.diagnostic")
        if phase.get("failure_class") not in FAILURE_CLASSES:
            raise CampaignError(
                f"{label}.failure_class must identify an expected design-check failure"
            )
    elif "failure_class" in phase:
        raise CampaignError(f"{label}.failure_class is only valid for expected failure")
    if "diagnostic" in phase:
        validate_pattern(phase["diagnostic"], f"{label}.diagnostic")
    environment = phase.get("environment", {})
    if not isinstance(environment, dict) or not all(
        isinstance(key, str)
        and key
        and isinstance(value, str)
        for key, value in environment.items()
    ):
        raise CampaignError(f"{label}.environment must map names to strings")
    timeout = phase.get("timeout_seconds", 300)
    if not isinstance(timeout, int) or isinstance(timeout, bool) or timeout < 1:
        raise CampaignError(f"{label}.timeout_seconds must be a positive integer")
    return phase


def validate_case(case: object, campaign: str, label: str) -> dict[str, Any]:
    """Validate one campaign case and its semantic role."""
    if not isinstance(case, dict):
        raise CampaignError(f"{label} must be an object")
    allowed = {
        "id",
        "evidence",
        "role",
        "kind",
        "phases",
        "positive_control",
        "monitor_control",
        "injections",
    }
    require_fields(case, allowed, {"id", "evidence", "role", "kind", "phases"}, label)
    for field in ("id", "evidence"):
        if not isinstance(case[field], str) or not NAME.fullmatch(case[field]):
            raise CampaignError(f"{label}.{field} must match {NAME.pattern}")
    if case["role"] not in ROLES[campaign]:
        raise CampaignError(f"{label}.role is invalid for {campaign}")
    if not isinstance(case["kind"], str) or not case["kind"]:
        raise CampaignError(f"{label}.kind must be a nonempty string")
    phases = case["phases"]
    if not isinstance(phases, list) or not phases:
        raise CampaignError(f"{label}.phases must be a nonempty array")
    validated_phases = [
        validate_phase(phase, f"{label}.phases[{index}]")
        for index, phase in enumerate(phases)
    ]
    phase_names = [phase["name"] for phase in validated_phases]
    if len(phase_names) != len(set(phase_names)):
        raise CampaignError(f"{label} repeats a phase name")

    expected_failures = sum(phase["expected"] == "failure" for phase in validated_phases)
    if case["role"] in {"positive_control", "disabled_monitor_control"}:
        if expected_failures:
            raise CampaignError(f"{label} control phases must all expect success")
        run_phases = [phase for phase in validated_phases if phase["name"] == "run"]
        if campaign == "four_state" and (
            not run_phases or not run_phases[0].get("diagnostic")
        ):
            raise CampaignError(
                f"{label} disabled-monitor control must prove stimulus arrival with a diagnostic"
            )
    elif expected_failures != 1:
        raise CampaignError(f"{label} must contain exactly one expected failure")

    if campaign == "negative" and case["role"] == "negative":
        control = case.get("positive_control")
        if not isinstance(control, str) or not NAME.fullmatch(control):
            raise CampaignError(f"{label}.positive_control is required")
    if campaign == "four_state":
        injections = case.get("injections")
        if (
            not isinstance(injections, list)
            or not injections
            or not all(
                isinstance(item, dict)
                and set(item) == {"control", "values"}
                and isinstance(item["control"], str)
                and item["control"]
                and isinstance(item["values"], list)
                and item["values"]
                and all(value in {"X", "Z"} for value in item["values"])
                for item in injections
            )
        ):
            raise CampaignError(
                f"{label}.injections must declare control names and X/Z values"
            )
        by_phase = {phase["name"]: phase for phase in validated_phases}
        if set(by_phase) != PHASES:
            raise CampaignError(f"{label} must define compile and run phases")
        if by_phase["compile"].get("command", [None])[0] != "{iverilog}":
            raise CampaignError(f"{label} compile phase must invoke {{iverilog}} directly")
        if by_phase["run"].get("command", [None])[0] != "{vvp}":
            raise CampaignError(f"{label} run phase must invoke {{vvp}} directly")
        if case["role"] == "unknown_detection":
            control = case.get("monitor_control")
            if not isinstance(control, str) or not NAME.fullmatch(control):
                raise CampaignError(f"{label}.monitor_control is required")
    return case


def load_campaign(path: Path, campaign: str) -> tuple[dict[str, Any], list[str]]:
    """Load and semantically validate one selected campaign."""
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise CampaignError(f"Cannot read campaign manifest {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise CampaignError(
            f"Campaign manifest JSON is invalid at column {error.colno}: {error.msg}"
        ) from error
    if not isinstance(manifest, dict):
        raise CampaignError("Campaign manifest root must be an object")
    require_fields(manifest, {"schema", "campaigns"}, {"schema", "campaigns"}, "manifest")
    if manifest["schema"] != SCHEMA:
        raise CampaignError(f"Campaign manifest schema must be {SCHEMA}")
    campaigns = manifest["campaigns"]
    if not isinstance(campaigns, dict) or not set(campaigns).issubset(CAMPAIGNS):
        raise CampaignError("manifest.campaigns contains an unknown campaign")
    if campaign not in campaigns:
        raise CampaignError(f"Campaign manifest does not define {campaign}")

    selected = campaigns[campaign]
    if not isinstance(selected, dict):
        raise CampaignError(f"campaigns.{campaign} must be an object")
    allowed = {"cases", "infrastructure_diagnostics", "inputs"}
    if campaign == "four_state":
        allowed.add("simulator")
    require_fields(selected, allowed, {"cases"}, f"campaigns.{campaign}")
    if campaign == "four_state" and selected.get("simulator") != "iverilog":
        raise CampaignError("four_state.simulator must be pinned to iverilog")
    patterns = selected.get("infrastructure_diagnostics", [])
    if not isinstance(patterns, list):
        raise CampaignError("infrastructure_diagnostics must be an array")
    infrastructure = [
        *DEFAULT_INFRASTRUCTURE_DIAGNOSTICS,
        *[
            validate_pattern(pattern, f"infrastructure_diagnostics[{index}]")
            for index, pattern in enumerate(patterns)
        ],
    ]
    inputs = selected.get("inputs", [])
    if (
        not isinstance(inputs, list)
        or not all(isinstance(item, str) and item for item in inputs)
        or len(inputs) != len(set(inputs))
    ):
        raise CampaignError(f"campaigns.{campaign}.inputs must be a unique string array")
    cases = selected["cases"]
    if not isinstance(cases, list) or not cases:
        raise CampaignError(f"campaigns.{campaign}.cases must be a nonempty array")
    validated = [
        validate_case(case, campaign, f"campaigns.{campaign}.cases[{index}]")
        for index, case in enumerate(cases)
    ]
    missing_roles = ROLES[campaign] - {case["role"] for case in validated}
    if missing_roles:
        raise CampaignError(
            f"campaigns.{campaign} is missing required roles: {', '.join(sorted(missing_roles))}"
        )
    ids = [case["id"] for case in validated]
    evidence = [case["evidence"] for case in validated]
    if len(ids) != len(set(ids)):
        raise CampaignError(f"campaigns.{campaign} repeats a case ID")
    if len(evidence) != len(set(evidence)):
        raise CampaignError(f"campaigns.{campaign} repeats an evidence name")
    by_id = {case["id"]: case for case in validated}
    for case in validated:
        reference = case.get("positive_control") or case.get("monitor_control")
        if reference:
            expected_role = (
                "positive_control" if campaign == "negative" else "disabled_monitor_control"
            )
            if reference not in by_id or by_id[reference]["role"] != expected_role:
                raise CampaignError(
                    f"case {case['id']} references missing {expected_role} {reference}"
                )
            if campaign == "four_state" and case["injections"] != by_id[reference]["injections"]:
                raise CampaignError(
                    f"case {case['id']} and monitor control {reference} must declare identical injections"
                )
    selected["cases"] = validated
    return selected, infrastructure


def expand(value: str, variables: dict[str, str], label: str) -> str:
    """Expand only the documented brace placeholders in a manifest string."""
    try:
        return value.format_map(variables)
    except KeyError as error:
        raise CampaignError(f"{label} uses unknown placeholder {{{error.args[0]}}}") from error
    except ValueError as error:
        raise CampaignError(f"{label} has invalid placeholder syntax: {error}") from error


def classify_phase(
    phase: dict[str, Any], returncode: int, output: str, infrastructure: list[str]
) -> tuple[bool, str, str]:
    """Distinguish expected design-check outcomes from escaped and tool failures."""
    expected = phase["expected"]
    diagnostic = phase.get("diagnostic")
    diagnostic_seen = bool(diagnostic and re.search(diagnostic, output, re.MULTILINE))
    infrastructure_seen = any(
        re.search(pattern, output, re.IGNORECASE | re.MULTILINE)
        for pattern in infrastructure
    )
    if expected == "success":
        if returncode != 0:
            classification = (
                "infrastructure_failure" if infrastructure_seen else "unexpected_failure"
            )
            return False, classification, "phase returned nonzero but success was required"
        if diagnostic and not diagnostic_seen:
            return False, "missing_diagnostic", "required success diagnostic was absent"
        return True, "expected_success", "phase succeeded"
    if returncode == 0:
        return False, "escaped_fault", "design-check failure was expected but command succeeded"
    if infrastructure_seen:
        return False, "infrastructure_failure", "tool or execution infrastructure failed"
    if not diagnostic_seen:
        return False, "unexpected_failure", "nonzero result lacked the required diagnostic"
    return True, f"expected_{phase['failure_class']}_failure", "expected failure was detected"


def run_phase(
    phase: dict[str, Any], variables: dict[str, str], infrastructure: list[str], case_dir: Path
) -> dict[str, Any]:
    """Execute one phase and emit its complete command and log evidence."""
    phase_name = phase["name"]
    if "command" in phase:
        command = [
            expand(argument, variables, f"{phase_name}.command")
            for argument in phase["command"]
        ]
    else:
        command = [expand(phase["fixture"], variables, f"{phase_name}.fixture")]
    environment = os.environ.copy()
    environment.update(
        {
            key: expand(value, variables, f"{phase_name}.environment.{key}")
            for key, value in phase.get("environment", {}).items()
        }
    )
    command_record = {
        "argv": command,
        "environment": phase.get("environment", {}),
        "timeout_seconds": phase.get("timeout_seconds", 300),
    }
    write_json(case_dir / f"{phase_name}-command.json", command_record)
    started = datetime.now(timezone.utc)
    try:
        completed = subprocess.run(
            command,
            cwd=variables["module_root"],
            env=environment,
            capture_output=True,
            text=True,
            errors="replace",
            timeout=phase.get("timeout_seconds", 300),
            check=False,
        )
        stdout = completed.stdout
        stderr = completed.stderr
        returncode = completed.returncode
        passed, classification, message = classify_phase(
            phase, returncode, stdout + stderr, infrastructure
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        stdout = getattr(error, "stdout", "") or ""
        stderr = (getattr(error, "stderr", "") or "") + f"\n{error}\n"
        returncode = None
        passed = False
        classification = "infrastructure_failure"
        message = "command could not be executed"
    (case_dir / f"{phase_name}.log").write_text(stdout + stderr, encoding="utf-8")
    result = {
        "classification": classification,
        "duration_seconds": round((datetime.now(timezone.utc) - started).total_seconds(), 6),
        "expected": phase["expected"],
        "message": message,
        "name": phase_name,
        "returncode": returncode,
        "status": "PASS" if passed else "FAIL",
    }
    write_json(case_dir / f"{phase_name}-result.json", result)
    return result


def run_case(
    case: dict[str, Any], module_root: Path, flow_root: Path, report_dir: Path,
    work_dir: Path, infrastructure: list[str], controls: dict[str, str]
) -> dict[str, Any]:
    """Run one isolated case after checking its declared control dependency."""
    case_report_dir = report_dir / case["evidence"]
    case_work_dir = work_dir / case["evidence"]
    case_report_dir.mkdir(parents=True, exist_ok=True)
    case_work_dir.mkdir(parents=True, exist_ok=True)
    write_status(case_report_dir / "status.txt", "FAIL")
    reference = case.get("positive_control") or case.get("monitor_control")
    if reference and controls.get(reference) != "PASS":
        result = {
            "classification": "blocked_by_control",
            "evidence": case["evidence"],
            "id": case["id"],
            "kind": case["kind"],
            "message": f"required control {reference} did not pass",
            "phases": [],
            "role": case["role"],
            "status": "FAIL",
        }
        write_json(case_report_dir / "summary.json", result)
        return result
    variables = {
        "case_report_dir": str(case_report_dir),
        "case_work_dir": str(case_work_dir),
        "eqy": os.environ.get("EQY_CMD", "eqy"),
        "flow_root": str(flow_root),
        "iverilog": os.environ.get("IVERILOG_CMD", "iverilog"),
        "module_root": str(module_root),
        "python": sys.executable,
        "report_dir": str(report_dir),
        "verilator": os.environ.get("VERILATOR_CMD", "verilator"),
        "vvp": os.environ.get("VVP_CMD", "vvp"),
        "work_dir": str(work_dir),
    }
    phase_results = []
    for phase in case["phases"]:
        result = run_phase(phase, variables, infrastructure, case_report_dir)
        phase_results.append(result)
        if result["status"] != "PASS":
            break
    passed = len(phase_results) == len(case["phases"]) and all(
        result["status"] == "PASS" for result in phase_results
    )
    classification = (
        phase_results[-1]["classification"] if phase_results else "not_run"
    )
    result = {
        "classification": classification,
        "evidence": case["evidence"],
        "id": case["id"],
        "kind": case["kind"],
        "phases": phase_results,
        "role": case["role"],
        "status": "PASS" if passed else "FAIL",
    }
    if "injections" in case:
        result["injections"] = case["injections"]
    write_json(case_report_dir / "summary.json", result)
    write_status(case_report_dir / "status.txt", result["status"])
    return result


def execute(args: argparse.Namespace) -> int:
    """Validate and execute one campaign, preserving evidence on every failure."""
    module_root = args.module_root.resolve()
    flow_root = args.flow_root.resolve()
    report_dir = args.report_dir.resolve()
    work_dir = args.work_dir.resolve()
    shutil.rmtree(report_dir, ignore_errors=True)
    shutil.rmtree(work_dir, ignore_errors=True)
    report_dir.mkdir(parents=True)
    work_dir.mkdir(parents=True)
    write_status(report_dir / "status.txt", "FAIL")
    try:
        selected, infrastructure = load_campaign(args.manifest.resolve(), args.campaign)
        for declared_input in selected.get("inputs", []):
            input_path = (module_root / declared_input).resolve()
            try:
                input_path.relative_to(module_root)
            except ValueError as error:
                raise CampaignError(
                    f"campaign input must be inside module root: {declared_input}"
                ) from error
            if not input_path.exists():
                raise CampaignError(f"campaign input is missing: {declared_input}")
        controls: dict[str, str] = {}
        cases = sorted(
            selected["cases"],
            key=lambda case: case["role"] not in {"positive_control", "disabled_monitor_control"},
        )
        results = []
        case_report_root = report_dir / selected.get("simulator", "")
        case_work_root = work_dir / selected.get("simulator", "")
        for case in cases:
            result = run_case(
                case,
                module_root,
                flow_root,
                case_report_root,
                case_work_root,
                infrastructure,
                controls,
            )
            results.append(result)
            if case["role"] in {"positive_control", "disabled_monitor_control"}:
                controls[case["id"]] = result["status"]
        passed = all(result["status"] == "PASS" for result in results)
        summary = {
            "campaign": args.campaign,
            "cases": results,
            "manifest": str(args.manifest.resolve().relative_to(module_root)),
            "inputs": selected.get("inputs", []),
            "schema": SUMMARY_SCHEMA,
            "simulator": selected.get("simulator"),
            "status": "PASS" if passed else "FAIL",
        }
    except (CampaignError, ValueError) as error:
        summary = {
            "campaign": args.campaign,
            "cases": [],
            "errors": [str(error)],
            "schema": SUMMARY_SCHEMA,
            "status": "FAIL",
        }
        passed = False
    write_json(report_dir / "summary.json", summary)
    write_status(report_dir / "status.txt", summary["status"])
    if not passed:
        print(f"{args.campaign} qualification failed; see {report_dir / 'summary.json'}", file=sys.stderr)
        return 1
    print(f"{args.campaign} qualification passed")
    return 0


def parse_arguments() -> argparse.Namespace:
    """Parse the command-line contract used by the shell adapters and tests."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--campaign", choices=sorted(CAMPAIGNS), required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--module-root", type=Path, required=True)
    parser.add_argument("--flow-root", type=Path, required=True)
    parser.add_argument("--report-dir", type=Path, required=True)
    parser.add_argument("--work-dir", type=Path, required=True)
    return parser.parse_args()


if __name__ == "__main__":
    sys.exit(execute(parse_arguments()))
