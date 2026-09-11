#!/usr/bin/env python3
"""Generate and validate auditable MOSAIC release evidence manifests."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shlex
import shutil
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCHEMA = "mosaic-release-evidence-v1"
NAME = re.compile(r"^[a-z][a-z0-9_]*$")
REVISION = re.compile(r"^[0-9a-fA-F]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
VALID_STATUSES = {"PASS", "SKIP"}


class ReleaseError(ValueError):
    """Report a user-correctable release evidence error."""


def json_environment(name: str, default: object) -> object:
    """Decode one JSON environment variable with a caller-provided default."""
    raw_value = os.environ.get(name, "")
    if not raw_value:
        return default
    try:
        return json.loads(raw_value)
    except json.JSONDecodeError as error:
        raise ReleaseError(
            f"{name} contains invalid JSON at column {error.colno}: {error.msg}"
        ) from error


def environment_list(name: str) -> list[str]:
    """Split one shell-style path or identifier list from the environment."""
    try:
        return shlex.split(os.environ.get(name, ""))
    except ValueError as error:
        raise ReleaseError(f"Cannot parse {name}: {error}") from error


def git_output(repository: Path, arguments: list[str]) -> str:
    """Run a read-only Git query and return trimmed standard output."""
    completed = subprocess.run(
        ["git", "-C", str(repository), *arguments],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        diagnostic = (completed.stderr or completed.stdout).strip()
        raise ReleaseError(f"Git query failed in {repository}: {diagnostic}")
    return completed.stdout.strip()


def resolve_revision(supplied: str, repository: Path, label: str) -> str:
    """Validate an explicit revision or resolve HEAD for local development."""
    if supplied:
        if not REVISION.fullmatch(supplied):
            raise ReleaseError(f"{label} revision must contain exactly 40 hex digits")
        return supplied.lower()
    ci_value = os.environ.get("CI", "").strip().lower()
    if ci_value not in {"", "0", "false", "no"}:
        raise ReleaseError(f"{label} revision must be supplied explicitly in CI")
    revision = git_output(repository, ["rev-parse", "--verify", "HEAD^{commit}"])
    if not REVISION.fullmatch(revision):
        raise ReleaseError(f"Git returned an invalid {label} revision: {revision!r}")
    return revision.lower()


def source_tree_dirty(repository: Path) -> bool:
    """Report tracked, staged, and untracked source changes."""
    return bool(git_output(repository, ["status", "--porcelain", "--untracked-files=normal"]))


def resolve_dirty_state(repository: Path, supplied: str, label: str) -> bool:
    """Use an explicit packaged-source attestation or inspect a Git checkout."""
    normalized = supplied.strip().lower()
    if normalized:
        if normalized not in {"true", "false"}:
            raise ReleaseError(
                f"{label} dirty state must be true or false when supplied"
            )
        return normalized == "true"
    try:
        return source_tree_dirty(repository)
    except ReleaseError as error:
        variable = f"RELEASE_{label.upper()}_DIRTY"
        raise ReleaseError(
            f"Cannot inspect {label} source tree; supply {variable}=true or false "
            "for an immutable packaged checkout"
        ) from error


def sha256_file(path: Path) -> str:
    """Hash one file without loading it completely into memory."""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def relative_path(path: Path, module_root: Path) -> str:
    """Return a repository-relative POSIX path or reject external evidence."""
    resolved = path.resolve()
    try:
        return resolved.relative_to(module_root).as_posix()
    except ValueError as error:
        raise ReleaseError(
            f"Release input or evidence must be inside MODULE_ROOT: {resolved}"
        ) from error


class InputCollector:
    """Collect required release inputs and their reasons without duplicates."""

    def __init__(self, module_root: Path) -> None:
        self.module_root = module_root
        self.roles: dict[Path, set[str]] = defaultdict(set)
        self.visited_filelists: set[Path] = set()

    def add(self, declared_path: str | Path, role: str) -> None:
        """Add one file or every file below one declared directory."""
        path = Path(declared_path)
        if not path.is_absolute():
            path = self.module_root / path
        if not path.exists():
            raise ReleaseError(f"Required release input is missing: {path}")
        if path.is_dir():
            files = sorted(
                candidate
                for candidate in path.rglob("*")
                if candidate.is_file()
                and "__pycache__" not in candidate.parts
                and candidate.suffix not in {".pyc", ".pyo"}
            )
            if not files:
                raise ReleaseError(f"Required release input directory is empty: {path}")
            for candidate in files:
                self.add(candidate, role)
            return
        resolved = path.resolve()
        relative_path(resolved, self.module_root)
        self.roles[resolved].add(role)

    def add_filelist(self, declared_path: str | Path) -> None:
        """Add a portable filelist, nested lists, sources, and include trees."""
        path = Path(declared_path)
        if not path.is_absolute():
            path = self.module_root / path
        path = path.resolve()
        if path in self.visited_filelists:
            return
        self.visited_filelists.add(path)
        self.add(path, "filelist")

        try:
            tokens = shlex.split(path.read_text(encoding="utf-8"), comments=True)
        except (OSError, UnicodeError, ValueError) as error:
            raise ReleaseError(f"Cannot parse release filelist {path}: {error}") from error

        token_index = 0
        while token_index < len(tokens):
            token = tokens[token_index]
            if token in {"-f", "-F"}:
                token_index += 1
                if token_index >= len(tokens):
                    raise ReleaseError(f"Filelist option {token} has no path in {path}")
                self.add_filelist(tokens[token_index])
            elif token.startswith("+incdir+"):
                for include in token.removeprefix("+incdir+").split("+"):
                    self.add(include, "include")
            elif token.startswith("+define+"):
                pass
            elif token.startswith(("+", "-")):
                raise ReleaseError(f"Unsupported release filelist token {token!r} in {path}")
            else:
                self.add(token, "source")
            token_index += 1

    def entries(self) -> list[dict[str, object]]:
        """Return sorted machine-readable path, role, and digest records."""
        return [
            {
                "path": relative_path(path, self.module_root),
                "roles": sorted(roles),
                "sha256": sha256_file(path),
            }
            for path, roles in sorted(
                self.roles.items(), key=lambda item: relative_path(item[0], self.module_root)
            )
        ]


def flow_is_disabled(flow: str, disabled_flows: set[str]) -> bool:
    """Apply the canonical disabled-flow policy, including the CDC alias."""
    return flow in disabled_flows or (
        "cdc" in disabled_flows and flow in {"vc_cdc", "sg_cdc"}
    )


def evidence_entry(path: Path, module_root: Path) -> dict[str, str]:
    """Create a relative path and SHA-256 record for generated evidence."""
    if not path.is_file():
        raise ReleaseError(f"Required release evidence is missing: {path}")
    return {
        "path": relative_path(path, module_root),
        "sha256": sha256_file(path),
    }


def collect_flows(
    module_root: Path, report_dir: Path
) -> tuple[list[dict[str, object]], set[str]]:
    """Validate every canonical flow against its resolved required or skip policy."""
    flows = os.environ.get("MOSAIC_FLOW_IDS", "").split()
    if not flows:
        raise ReleaseError("MOSAIC_FLOW_IDS is empty")
    if len(flows) != len(set(flows)):
        raise ReleaseError("MOSAIC_FLOW_IDS contains duplicate flow names")

    disabled_flows = set(os.environ.get("DISABLED_FLOWS", "").split())
    entries: list[dict[str, object]] = []
    required_flows: set[str] = set()
    for flow in flows:
        status_path = report_dir / flow / "status.txt"
        disabled = flow_is_disabled(flow, disabled_flows)
        if disabled:
            status = "SKIP"
            status_evidence = None
            if status_path.exists():
                status = status_path.read_text(encoding="utf-8").strip()
                if status != "SKIP":
                    raise ReleaseError(
                        f"Disabled flow {flow} has status {status}, expected SKIP"
                    )
                status_evidence = evidence_entry(status_path, module_root)
            entries.append(
                {
                    "id": flow,
                    "policy": "approved_skip",
                    "status": "SKIP",
                    "status_evidence": status_evidence,
                }
            )
            continue

        required_flows.add(flow)
        if not status_path.is_file():
            raise ReleaseError(
                f"Required flow {flow} is missing status evidence: {status_path}"
            )
        status = status_path.read_text(encoding="utf-8").strip()
        if status != "PASS":
            raise ReleaseError(f"Required flow {flow} has status {status}, expected PASS")
        entries.append(
            {
                "id": flow,
                "policy": "required",
                "status": "PASS",
                "status_evidence": evidence_entry(status_path, module_root),
            }
        )
    return entries, required_flows


def collect_supplemental_gates(
    module_root: Path, report_dir: Path
) -> list[dict[str, object]]:
    """Validate module-owned supplemental gates using the shared status contract."""
    gates = environment_list("RELEASE_SUPPLEMENTAL_GATES")
    if len(gates) != len(set(gates)):
        raise ReleaseError("RELEASE_SUPPLEMENTAL_GATES contains duplicate names")
    entries = []
    for gate in gates:
        if not NAME.fullmatch(gate):
            raise ReleaseError(f"Invalid supplemental gate name: {gate!r}")
        status_path = report_dir / gate / "status.txt"
        if not status_path.is_file():
            raise ReleaseError(
                f"Supplemental gate {gate} is missing status evidence: {status_path}"
            )
        status = status_path.read_text(encoding="utf-8").strip()
        if status != "PASS":
            raise ReleaseError(
                f"Supplemental gate {gate} has status {status}, expected PASS"
            )
        entries.append(
            {
                "id": gate,
                "status": status,
                "status_evidence": evidence_entry(status_path, module_root),
            }
        )
    return entries


def run_version_command(
    name: str, command_text: str, version_arguments: list[str], flows: set[str]
) -> tuple[dict[str, object], dict[str, str]]:
    """Resolve one executable and capture its complete version response."""
    command = shlex.split(command_text)
    if not command:
        raise ReleaseError(f"Tool command for {name} is empty")
    executable = command[0]
    resolved = str(Path(executable).resolve()) if Path(executable).is_file() else shutil.which(executable)
    if not resolved:
        raise ReleaseError(f"Enabled flows require {name}, but {executable} is not in PATH")
    completed = subprocess.run(
        [resolved, *command[1:], *version_arguments],
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
    )
    version = (completed.stdout or completed.stderr).strip()
    if completed.returncode != 0 or not version:
        raise ReleaseError(
            f"Cannot read {name} version with {' '.join([resolved, *version_arguments])}"
        )
    return (
        {
            "name": name,
            "context": "flow",
            "command": [Path(executable).name, *command[1:], *version_arguments],
            "flows": sorted(flows),
            "version": version,
        },
        {"name": name, "context": "flow", "path": resolved},
    )


def parse_version_log(path: Path) -> dict[str, str]:
    """Parse key/value and heredoc fields emitted by the PyUVM adapter."""
    if not path.is_file():
        raise ReleaseError(f"PyUVM version evidence is missing: {path}")
    lines = path.read_text(encoding="utf-8").splitlines()
    values: dict[str, str] = {}
    index = 0
    while index < len(lines):
        line = lines[index]
        if "<<" in line:
            key, delimiter = line.split("<<", 1)
            index += 1
            contents = []
            while index < len(lines) and lines[index] != delimiter:
                contents.append(lines[index])
                index += 1
            if index >= len(lines):
                raise ReleaseError(f"Unterminated version field {key} in {path}")
            values[key] = "\n".join(contents)
        elif "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
        index += 1
    return values


def collect_tools(
    module_root: Path, report_dir: Path, required_flows: set[str]
) -> tuple[list[dict[str, object]], list[dict[str, str]]]:
    """Capture exact portable tool versions and optional module-owned tools."""
    tools: list[dict[str, object]] = [
        {
            "name": "python",
            "context": "manifest_generator",
            "command": [Path(sys.executable).name],
            "flows": [],
            "version": platform.python_version(),
        }
    ]
    tool_paths = [
        {
            "name": "python",
            "context": "manifest_generator",
            "path": str(Path(sys.executable).resolve()),
        }
    ]
    specifications = [
        ("verible-verilog-lint", {"verible_lint"}, "VERIBLE_LINT_CMD", "verible-verilog-lint", ["--version"]),
        ("verible-verilog-format", {"verible_format"}, "VERIBLE_FORMAT_CMD", "verible-verilog-format", ["--version"]),
        ("slang", {"slang_elaboration"}, "SLANG_CMD", "slang", ["--version"]),
        ("verilator", {"verilator_lint", "verilator_sim"}, "VERILATOR_CMD", "verilator", ["--version"]),
        ("yosys", {"yosys_synthesis"}, "YOSYS_CMD", "yosys", ["--version"]),
        ("symbiyosys", {"symbiyosys_formal"}, "SBY_CMD", "sby", ["--version"]),
        ("eqy", {"eqy_equivalence"}, "EQY_CMD", "eqy", ["--version"]),
        ("iverilog", {"four_state_qualification"}, "IVERILOG_CMD", "iverilog", ["-V"]),
        ("vvp", {"four_state_qualification"}, "VVP_CMD", "vvp", ["-V"]),
    ]
    for name, owned_flows, variable, default, arguments in specifications:
        active_flows = owned_flows & required_flows
        if active_flows:
            tool, tool_path = run_version_command(
                name, os.environ.get(variable, default), arguments, active_flows
            )
            tools.append(tool)
            tool_paths.append(tool_path)

    for flow in ("pyuvm_open_source", "pyuvm_commercial"):
        if flow not in required_flows:
            continue
        version_path = report_dir / flow / "versions.log"
        values = parse_version_log(version_path)
        required_fields = {
            "python",
            "pyuvm",
            "cocotb",
            "simulator",
            "simulator_executable",
            "simulator_version",
        }
        missing_fields = sorted(required_fields - set(values))
        if missing_fields:
            raise ReleaseError(
                f"PyUVM version evidence is missing fields: {', '.join(missing_fields)}"
            )
        source = evidence_entry(version_path, module_root)
        for name in ("python", "pyuvm", "cocotb"):
            tools.append(
                {
                    "name": name,
                    "context": flow,
                    "command": ["python"] if name == "python" else [],
                    "flows": [flow],
                    "source": source,
                    "version": values[name],
                }
            )
        tools.append(
            {
                "name": values["simulator"],
                "context": flow,
                "command": [Path(values["simulator_executable"]).name],
                "flows": [flow],
                "source": source,
                "version": values["simulator_version"],
            }
        )
        tool_paths.extend(
            [
                {
                    "name": "python",
                    "context": flow,
                    "path": os.environ.get("PYUVM_PYTHON", ""),
                },
                {
                    "name": values["simulator"],
                    "context": flow,
                    "path": values["simulator_executable"],
                },
            ]
        )

    custom_tools = json_environment("RELEASE_ADDITIONAL_TOOLS_JSON", [])
    if not isinstance(custom_tools, list):
        raise ReleaseError("RELEASE_ADDITIONAL_TOOLS_JSON must contain a JSON array")
    for index, custom in enumerate(custom_tools):
        if not isinstance(custom, dict) or set(custom) != {"name", "command", "flows"}:
            raise ReleaseError(
                f"Additional tool {index} must contain name, command, and flows"
            )
        name = custom["name"]
        command = custom["command"]
        flows = custom["flows"]
        if not isinstance(name, str) or not NAME.fullmatch(name):
            raise ReleaseError(f"Additional tool {index} has invalid name")
        if not isinstance(command, list) or not all(
            isinstance(item, str) and item for item in command
        ):
            raise ReleaseError(f"Additional tool {name} command must be a string array")
        if not isinstance(flows, list) or not all(isinstance(item, str) for item in flows):
            raise ReleaseError(f"Additional tool {name} flows must be a string array")
        active_flows = set(flows) & required_flows
        if flows and not active_flows:
            continue
        tool, tool_path = run_version_command(
            name, command[0], command[1:], active_flows
        )
        tools.append(tool)
        tool_paths.append(tool_path)

    key = lambda entry: (str(entry["name"]), str(entry["context"]))
    return sorted(tools, key=key), sorted(tool_paths, key=key)


def collect_coverage(module_root: Path, report_dir: Path) -> list[dict[str, str]]:
    """Index native HDL and PyUVM functional coverage as separate evidence."""
    candidates = [
        ("verilator_sim", "coverage.dat", "systemverilog_native_database"),
        ("verilator_sim", "coverage.info", "systemverilog_native_report"),
        ("pyuvm_open_source", "coverage.dat", "systemverilog_native_database"),
        ("pyuvm_open_source", "coverage.info", "systemverilog_native_report"),
        ("pyuvm_open_source", "functional-coverage.json", "pyuvm_functional"),
        ("pyuvm_commercial", "functional-coverage.json", "pyuvm_functional"),
        (
            "coverage_qualification",
            "summary.json",
            "coverage_qualification_summary",
        ),
    ]
    entries = []
    for producer, filename, kind in candidates:
        path = report_dir / producer / filename
        if path.is_file():
            entries.append(
                {"kind": kind, "producer": producer, **evidence_entry(path, module_root)}
            )

    additional = json_environment("RELEASE_COVERAGE_EVIDENCE_JSON", [])
    if not isinstance(additional, list):
        raise ReleaseError("RELEASE_COVERAGE_EVIDENCE_JSON must contain a JSON array")
    for index, item in enumerate(additional):
        if not isinstance(item, dict) or set(item) != {"kind", "producer", "path"}:
            raise ReleaseError(
                f"Additional coverage entry {index} must contain kind, producer, and path"
            )
        if not all(isinstance(item[field], str) and item[field] for field in item):
            raise ReleaseError(f"Additional coverage entry {index} has empty fields")
        path = Path(item["path"])
        if not path.is_absolute():
            path = module_root / path
        entries.append(
            {
                "kind": item["kind"],
                "producer": item["producer"],
                **evidence_entry(path, module_root),
            }
        )
    return sorted(
        entries,
        key=lambda entry: (entry["producer"], entry["kind"], entry["path"]),
    )


def collect_qualification_inputs(
    collector: InputCollector, module_root: Path, required_flows: set[str]
) -> None:
    """Hash module-owned collateral for each enabled qualification campaign."""
    campaign_by_flow = {
        "negative_qualification": "negative",
        "four_state_qualification": "four_state",
    }
    active = {
        flow: campaign
        for flow, campaign in campaign_by_flow.items()
        if flow in required_flows
    }
    if not active:
        return
    manifest_path = Path(
        os.environ.get(
            "QUALIFICATION_CAMPAIGN_MANIFEST",
            str(module_root / "config" / "qualification-campaigns.json"),
        )
    )
    if not manifest_path.is_absolute():
        manifest_path = module_root / manifest_path
    collector.add(manifest_path, "declared")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ReleaseError(
            f"Cannot parse qualification campaign inputs from {manifest_path}: {error}"
        ) from error
    campaigns = manifest.get("campaigns") if isinstance(manifest, dict) else None
    if not isinstance(campaigns, dict):
        raise ReleaseError("Qualification campaign manifest has no campaigns object")
    for flow, campaign in active.items():
        selected = campaigns.get(campaign)
        if not isinstance(selected, dict):
            raise ReleaseError(f"Required flow {flow} has no {campaign} campaign")
        inputs = selected.get("inputs", [])
        if not isinstance(inputs, list) or not all(
            isinstance(item, str) and item for item in inputs
        ):
            raise ReleaseError(f"Campaign {campaign} inputs must be a string array")
        for declared_input in inputs:
            collector.add(declared_input, "declared")


def collect_static_intent_inputs(
    collector: InputCollector, module_root: Path, required_flows: set[str]
) -> None:
    """Hash the expectation file and every SDC or UPF path it selects."""
    if "static_intent" not in required_flows:
        return
    config_path = Path(
        os.environ.get(
            "STATIC_INTENT_CONFIG",
            str(module_root / "config" / "static-intent.json"),
        )
    )
    if not config_path.is_absolute():
        config_path = module_root / config_path
    collector.add(config_path, "declared")
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ReleaseError(
            f"Cannot parse static-intent inputs from {config_path}: {error}"
        ) from error
    if not isinstance(config, dict):
        raise ReleaseError("Static-intent configuration root must be an object")
    sdc = config.get("sdc", {})
    if not isinstance(sdc, dict):
        raise ReleaseError("Static-intent sdc section must be an object")
    profiles = sdc.get("profiles", [])
    if not isinstance(profiles, list):
        raise ReleaseError("Static-intent SDC profiles must be an array")
    for index, profile in enumerate(profiles):
        if not isinstance(profile, dict) or not isinstance(profile.get("path"), str):
            raise ReleaseError(f"Static-intent SDC profile {index} has no path")
        collector.add(profile["path"], "declared")
    upf = config.get("upf")
    if upf is not None:
        if not isinstance(upf, dict) or not isinstance(upf.get("path"), str):
            raise ReleaseError("Static-intent UPF section has no path")
        collector.add(upf["path"], "declared")


def generate_manifest(module_root: Path, flow_root: Path, report_dir: Path) -> dict[str, object]:
    """Validate release evidence and compose deterministic and volatile sections."""
    module_root = module_root.resolve()
    flow_root = flow_root.resolve()
    report_dir = report_dir.resolve()
    module_name = os.environ.get("RELEASE_MODULE_NAME", "").strip()
    if not NAME.fullmatch(module_name):
        raise ReleaseError(f"Invalid release module name: {module_name!r}")
    profile = os.environ.get("PROFILE", "default") or "default"
    if not NAME.fullmatch(profile):
        raise ReleaseError(f"Invalid release profile name: {profile!r}")
    context = os.environ.get("RELEASE_EXECUTION_CONTEXT", "native")
    if not NAME.fullmatch(context):
        raise ReleaseError(f"Invalid release execution context: {context!r}")

    module_revision = resolve_revision(
        os.environ.get("MODULE_REVISION", ""), module_root, "module"
    )
    methodology_revision = resolve_revision(
        os.environ.get("METHODOLOGY_REVISION", ""), flow_root, "methodology"
    )
    module_dirty = resolve_dirty_state(
        module_root, os.environ.get("RELEASE_MODULE_DIRTY", ""), "module"
    )
    methodology_dirty = resolve_dirty_state(
        flow_root,
        os.environ.get("RELEASE_METHODOLOGY_DIRTY", ""),
        "methodology",
    )
    allow_dirty = os.environ.get("RELEASE_ALLOW_DIRTY", "disabled")
    if allow_dirty not in {"enabled", "disabled"}:
        raise ReleaseError("RELEASE_ALLOW_DIRTY must be enabled or disabled")
    if (module_dirty or methodology_dirty) and allow_dirty != "enabled":
        dirty_repositories = ", ".join(
            name
            for name, dirty in (
                ("module", module_dirty),
                ("methodology", methodology_dirty),
            )
            if dirty
        )
        raise ReleaseError(
            f"Dirty source tree detected for {dirty_repositories}; commit changes or "
            "set RELEASE_ALLOW_DIRTY=enabled"
        )

    collector = InputCollector(module_root)
    for path in environment_list("RELEASE_INPUT_FILES"):
        collector.add(path, "declared")
    for path in environment_list("RELEASE_FILELISTS"):
        collector.add_filelist(path)

    flows, required_flows = collect_flows(module_root, report_dir)
    collect_qualification_inputs(collector, module_root, required_flows)
    collect_static_intent_inputs(collector, module_root, required_flows)
    gates = collect_supplemental_gates(module_root, report_dir)
    additional_evidence = []
    for declared_path in (
        environment_list("RELEASE_STANDARD_EVIDENCE")
        + environment_list("RELEASE_ADDITIONAL_EVIDENCE")
    ):
        path = Path(declared_path)
        if not path.is_absolute():
            path = module_root / path
        additional_evidence.append(evidence_entry(path, module_root))
    for flow in ("negative_qualification", "four_state_qualification"):
        summary_path = report_dir / flow / "summary.json"
        if flow in required_flows and summary_path.is_file():
            additional_evidence.append(evidence_entry(summary_path, module_root))
    if "static_intent" in required_flows:
        for filename in ("sdc-findings.json", "upf-findings.json", "summary.json"):
            additional_evidence.append(
                evidence_entry(report_dir / "static_intent" / filename, module_root)
            )

    parameters = json_environment("PROFILE_PARAMETERS_JSON", {})
    technology_details = json_environment("RELEASE_TECHNOLOGY_METADATA_JSON", {})
    metadata = json_environment("RELEASE_METADATA_JSON", {})
    execution_metadata = json_environment("RELEASE_EXECUTION_METADATA_JSON", {})
    for variable, value in (
        ("PROFILE_PARAMETERS_JSON", parameters),
        ("RELEASE_TECHNOLOGY_METADATA_JSON", technology_details),
        ("RELEASE_METADATA_JSON", metadata),
        ("RELEASE_EXECUTION_METADATA_JSON", execution_metadata),
    ):
        if not isinstance(value, dict):
            raise ReleaseError(f"{variable} must contain a JSON object")

    methodology_version_path = flow_root / "VERSION"
    if not methodology_version_path.is_file():
        raise ReleaseError(f"Methodology VERSION is missing: {methodology_version_path}")
    technology = {
        "name": os.environ.get("RELEASE_TECHNOLOGY", "technology-independent"),
        "details": technology_details,
    }
    if not technology["name"]:
        raise ReleaseError("RELEASE_TECHNOLOGY cannot be empty")
    tools, tool_paths = collect_tools(module_root, report_dir, required_flows)

    return {
        "schema": SCHEMA,
        "deterministic": {
            "identity": {
                "module": module_name,
                "profile": profile,
                "module_revision": module_revision,
                "methodology_revision": methodology_revision,
                "methodology_version": methodology_version_path.read_text(
                    encoding="utf-8"
                ).strip(),
                "execution_context": context,
            },
            "parameters": parameters,
            "technology": technology,
            "flows": flows,
            "supplemental_gates": gates,
            "tools": tools,
            "inputs": collector.entries(),
            "evidence": {
                "additional": sorted(additional_evidence, key=lambda item: item["path"]),
                "coverage": collect_coverage(module_root, report_dir),
            },
            "metadata": metadata,
        },
        "volatile": {
            "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "source_tree": {
                "module_dirty": module_dirty,
                "methodology_dirty": methodology_dirty,
            },
            "execution": {
                "context": context,
                "host": {
                    "machine": platform.machine(),
                    "platform": platform.platform(),
                    "python_executable": str(Path(sys.executable).resolve()),
                },
                "tool_paths": tool_paths,
                "metadata": execution_metadata,
            },
        },
    }


def validate_evidence_record(record: object, label: str) -> None:
    """Validate one path and digest record shared by several sections."""
    if not isinstance(record, dict):
        raise ReleaseError(f"{label} must be an object")
    path = record.get("path")
    digest = record.get("sha256")
    if (
        not isinstance(path, str)
        or not path
        or Path(path).is_absolute()
        or ".." in Path(path).parts
    ):
        raise ReleaseError(f"{label} has an invalid repository-relative path")
    if not isinstance(digest, str) or not SHA256.fullmatch(digest):
        raise ReleaseError(f"{label} has an invalid SHA-256 digest")


def validate_manifest(manifest: object) -> None:
    """Validate the stable structural and semantic release manifest contract."""
    if not isinstance(manifest, dict) or set(manifest) != {
        "schema",
        "deterministic",
        "volatile",
    }:
        raise ReleaseError("Release manifest root has invalid fields")
    if manifest["schema"] != SCHEMA:
        raise ReleaseError(f"Release manifest schema must be {SCHEMA!r}")
    deterministic = manifest["deterministic"]
    volatile = manifest["volatile"]
    if not isinstance(deterministic, dict) or not isinstance(volatile, dict):
        raise ReleaseError("Release manifest sections must be objects")

    required_sections = {
        "identity",
        "parameters",
        "technology",
        "flows",
        "supplemental_gates",
        "tools",
        "inputs",
        "evidence",
        "metadata",
    }
    if set(deterministic) != required_sections:
        raise ReleaseError("Release manifest deterministic section has invalid fields")
    identity = deterministic["identity"]
    if not isinstance(identity, dict) or set(identity) != {
        "module",
        "profile",
        "module_revision",
        "methodology_revision",
        "methodology_version",
        "execution_context",
    }:
        raise ReleaseError("Release identity must be an object")
    for field in ("module_revision", "methodology_revision"):
        if not isinstance(identity.get(field), str) or not REVISION.fullmatch(
            identity[field]
        ):
            raise ReleaseError(f"Release identity has invalid {field}")
    for field in ("module", "profile", "execution_context"):
        if not isinstance(identity.get(field), str) or not NAME.fullmatch(identity[field]):
            raise ReleaseError(f"Release identity has invalid {field}")
    if (
        not isinstance(identity.get("methodology_version"), str)
        or not identity["methodology_version"]
    ):
        raise ReleaseError("Release identity has invalid methodology_version")

    if not isinstance(deterministic["parameters"], dict):
        raise ReleaseError("Release parameters must be an object")
    if not isinstance(deterministic["metadata"], dict):
        raise ReleaseError("Release metadata must be an object")
    technology = deterministic["technology"]
    if (
        not isinstance(technology, dict)
        or set(technology) != {"name", "details"}
        or not isinstance(technology["name"], str)
        or not technology["name"]
        or not isinstance(technology["details"], dict)
    ):
        raise ReleaseError("Release technology context is invalid")

    flows = deterministic["flows"]
    if not isinstance(flows, list) or not flows:
        raise ReleaseError("Release manifest must record canonical flows")
    flow_ids = []
    for index, flow in enumerate(flows):
        if not isinstance(flow, dict):
            raise ReleaseError(f"Flow entry {index} must be an object")
        if set(flow) != {"id", "policy", "status", "status_evidence"}:
            raise ReleaseError(f"Flow entry {index} has invalid fields")
        flow_ids.append(flow.get("id"))
        if not isinstance(flow.get("id"), str) or not NAME.fullmatch(flow["id"]):
            raise ReleaseError(f"Flow entry {index} has invalid ID")
        if flow.get("status") not in VALID_STATUSES:
            raise ReleaseError(f"Flow entry {index} has invalid status")
        expected_policy = "required" if flow["status"] == "PASS" else "approved_skip"
        if flow.get("policy") != expected_policy:
            raise ReleaseError(f"Flow entry {index} has inconsistent policy")
        evidence = flow.get("status_evidence")
        if flow["status"] == "PASS" and evidence is None:
            raise ReleaseError(f"Required flow entry {index} has no status evidence")
        if evidence is not None:
            validate_evidence_record(evidence, f"flow entry {index} status evidence")
    if len(flow_ids) != len(set(flow_ids)):
        raise ReleaseError("Release manifest repeats canonical flow IDs")

    for section in ("supplemental_gates", "inputs", "tools"):
        if not isinstance(deterministic[section], list):
            raise ReleaseError(f"Release manifest {section} must be an array")
    for index, item in enumerate(deterministic["supplemental_gates"]):
        if (
            not isinstance(item, dict)
            or set(item) != {"id", "status", "status_evidence"}
            or not isinstance(item.get("id"), str)
            or not NAME.fullmatch(item["id"])
            or item.get("status") != "PASS"
        ):
            raise ReleaseError(f"Supplemental gate entry {index} is invalid")
        validate_evidence_record(item.get("status_evidence"), f"supplemental gate {index}")
    for index, item in enumerate(deterministic["inputs"]):
        if not isinstance(item, dict) or set(item) != {"path", "roles", "sha256"}:
            raise ReleaseError(f"Input entry {index} has invalid fields")
        validate_evidence_record(item, f"input entry {index}")
        if (
            not isinstance(item.get("roles"), list)
            or not item["roles"]
            or not all(
                isinstance(role, str) and role in {"declared", "filelist", "include", "source"}
                for role in item["roles"]
            )
        ):
            raise ReleaseError(f"Input entry {index} has no roles")

    for index, item in enumerate(deterministic["tools"]):
        if not isinstance(item, dict):
            raise ReleaseError(f"Tool entry {index} must be an object")
        required_tool_fields = {"name", "context", "command", "flows", "version"}
        if not required_tool_fields.issubset(item) or not set(item).issubset(
            required_tool_fields | {"source"}
        ):
            raise ReleaseError(f"Tool entry {index} has invalid fields")
        if not isinstance(item["name"], str) or not item["name"]:
            raise ReleaseError(f"Tool entry {index} has invalid name")
        if not isinstance(item["context"], str) or not NAME.fullmatch(item["context"]):
            raise ReleaseError(f"Tool entry {index} has invalid context")
        if not isinstance(item["command"], list) or not all(
            isinstance(argument, str) and argument for argument in item["command"]
        ):
            raise ReleaseError(f"Tool entry {index} has invalid command")
        if not isinstance(item["flows"], list) or not all(
            isinstance(flow, str) and NAME.fullmatch(flow) for flow in item["flows"]
        ):
            raise ReleaseError(f"Tool entry {index} has invalid flows")
        if not isinstance(item["version"], str) or not item["version"]:
            raise ReleaseError(f"Tool entry {index} has invalid version")
        if "source" in item:
            validate_evidence_record(item["source"], f"tool entry {index} source")

    evidence = deterministic["evidence"]
    if not isinstance(evidence, dict) or set(evidence) != {"additional", "coverage"}:
        raise ReleaseError("Release evidence section has invalid fields")
    for group in ("additional", "coverage"):
        if not isinstance(evidence[group], list):
            raise ReleaseError(f"Release evidence {group} must be an array")
        for index, item in enumerate(evidence[group]):
            expected_fields = {"path", "sha256"}
            if group == "coverage":
                expected_fields |= {"kind", "producer"}
            if not isinstance(item, dict) or set(item) != expected_fields:
                raise ReleaseError(f"{group} evidence entry {index} has invalid fields")
            validate_evidence_record(item, f"{group} evidence entry {index}")
            if group == "coverage" and not all(
                isinstance(item[field], str) and item[field]
                for field in ("kind", "producer")
            ):
                raise ReleaseError(f"Coverage evidence entry {index} has invalid labels")

    if set(volatile) != {"generated_at", "source_tree", "execution"}:
        raise ReleaseError("Release manifest volatile section has invalid fields")
    source_tree = volatile.get("source_tree")
    if not isinstance(source_tree, dict) or set(source_tree) != {
        "module_dirty",
        "methodology_dirty",
    } or not all(isinstance(value, bool) for value in source_tree.values()):
        raise ReleaseError("Release manifest has invalid dirty-tree state")
    generated_at = volatile.get("generated_at")
    if not isinstance(generated_at, str) or not generated_at.endswith("Z"):
        raise ReleaseError("Release manifest has invalid generation time")
    try:
        datetime.fromisoformat(generated_at.removesuffix("Z") + "+00:00")
    except ValueError as error:
        raise ReleaseError("Release manifest has invalid generation time") from error

    execution = volatile.get("execution")
    if not isinstance(execution, dict) or set(execution) != {
        "context",
        "host",
        "tool_paths",
        "metadata",
    }:
        raise ReleaseError("Release execution context has invalid fields")
    if execution["context"] != identity["execution_context"]:
        raise ReleaseError("Deterministic and volatile execution contexts disagree")
    host = execution["host"]
    if not isinstance(host, dict) or set(host) != {
        "machine",
        "platform",
        "python_executable",
    }:
        raise ReleaseError("Release execution host has invalid fields")
    if not all(isinstance(value, str) and value for value in host.values()):
        raise ReleaseError("Release execution host has empty fields")
    if not isinstance(execution["metadata"], dict):
        raise ReleaseError("Release execution metadata must be an object")
    if not isinstance(execution["tool_paths"], list):
        raise ReleaseError("Release execution tool_paths must be an array")
    for index, tool_path in enumerate(execution["tool_paths"]):
        if (
            not isinstance(tool_path, dict)
            or set(tool_path) != {"name", "context", "path"}
            or not all(isinstance(tool_path[field], str) and tool_path[field]
                       for field in ("name", "context", "path"))
        ):
            raise ReleaseError(f"Release execution tool path {index} is invalid")


def write_summary(manifest: dict[str, object], path: Path) -> None:
    """Write a compact reviewer-oriented summary beside the JSON manifest."""
    deterministic = manifest["deterministic"]
    volatile = manifest["volatile"]
    identity = deterministic["identity"]
    lines = [
        "MOSAIC release evidence",
        f"Module: {identity['module']}",
        f"Profile: {identity['profile']}",
        f"Execution context: {identity['execution_context']}",
        f"Module revision: {identity['module_revision']}",
        f"Methodology revision: {identity['methodology_revision']}",
        f"Generated at: {volatile['generated_at']}",
        f"Dirty module tree: {str(volatile['source_tree']['module_dirty']).lower()}",
        "Dirty methodology tree: "
        f"{str(volatile['source_tree']['methodology_dirty']).lower()}",
        "",
        "Flows:",
    ]
    lines.extend(
        f"  {flow['status']:4}  {flow['id']} ({flow['policy']})"
        for flow in deterministic["flows"]
    )
    if deterministic["supplemental_gates"]:
        lines.extend(["", "Supplemental gates:"])
        lines.extend(
            f"  {gate['status']:4}  {gate['id']}"
            for gate in deterministic["supplemental_gates"]
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parser() -> argparse.ArgumentParser:
    """Build the release manifest generator and validator CLI."""
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)
    generate = subparsers.add_parser("generate")
    generate.add_argument("--module-root", required=True, type=Path)
    generate.add_argument("--flow-root", required=True, type=Path)
    generate.add_argument("--report-dir", required=True, type=Path)
    generate.add_argument("--output-dir", required=True, type=Path)
    validate = subparsers.add_parser("validate")
    validate.add_argument("--manifest", required=True, type=Path)
    return result


def main() -> int:
    """Generate new evidence or validate an archived manifest."""
    arguments = parser().parse_args()
    output_dir = arguments.output_dir.resolve() if arguments.command == "generate" else None
    try:
        if arguments.command == "validate":
            manifest = json.loads(arguments.manifest.read_text(encoding="utf-8"))
            validate_manifest(manifest)
            print(f"Validated release manifest: {arguments.manifest.resolve()}")
            return 0

        manifest = generate_manifest(
            arguments.module_root, arguments.flow_root, arguments.report_dir
        )
        validate_manifest(manifest)
        output_dir.mkdir(parents=True, exist_ok=True)
        manifest_path = output_dir / "manifest.json"
        summary_path = output_dir / "summary.txt"
        temporary_path = output_dir / "manifest.json.tmp"
        temporary_path.write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        temporary_path.replace(manifest_path)
        write_summary(manifest, summary_path)
        (output_dir / "status.txt").write_text("PASS\n", encoding="utf-8")
        print(f"Release evidence manifest written to {manifest_path}")
        return 0
    except (ReleaseError, OSError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        if output_dir is not None:
            output_dir.mkdir(parents=True, exist_ok=True)
            for stale_name in ("manifest.json", "manifest.json.tmp", "summary.txt"):
                (output_dir / stale_name).unlink(missing_ok=True)
            (output_dir / "status.txt").write_text("FAIL\n", encoding="utf-8")
        print(f"release manifest error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
