#!/usr/bin/env python3
"""Validate, query, and render MOSAIC parameter-profile manifests."""

from __future__ import annotations

import argparse
import json
import re
import shlex
import sys
from pathlib import Path
from typing import Any


SCHEMA = "mosaic-parameter-profiles-v1"
PROFILE_NAME = re.compile(r"^[a-z][a-z0-9_]*$")
IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
PARAMETER_VALUE = re.compile(r"^[A-Za-z0-9_.:'()+*/%<>=!?&|~^{},\[\]-]+$")
TOP_FIELDS = {"design", "testbench", "formal", "pyuvm"}
SUPPORTED_FLOWS = {
    "verible_lint",
    "verible_format",
    "slang_elaboration",
    "verilator_lint",
    "yosys_synthesis",
    "symbiyosys_formal",
    "eqy_equivalence",
    "verilator_sim",
    "pyuvm_open_source",
    "vcs_sim",
    "pyuvm_commercial",
    "synopsys_synthesis",
    "synopsys_primetime",
    "synopsys_primepower",
}
FLOW_DEPENDENCIES = {
    "eqy_equivalence": {"yosys_synthesis"},
    "synopsys_primetime": {"synopsys_synthesis"},
    "synopsys_primepower": {"vcs_sim", "synopsys_synthesis"},
}


class ProfileError(ValueError):
    """Report a user-correctable profile declaration error."""


def normalized_value(value: object) -> str:
    """Convert one JSON scalar into a backend-neutral HDL constant token."""
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str) and value and PARAMETER_VALUE.fullmatch(value):
        return value
    raise ProfileError(
        f"unsupported parameter value {value!r}; use an integer, boolean, or "
        "whitespace-free HDL constant without semicolons"
    )


def validate_profile(entry: object, index: int, names: set[str]) -> dict[str, Any]:
    """Validate one profile object and return it with a narrowed type."""
    if not isinstance(entry, dict):
        raise ProfileError(f"Profile entry {index} must be a JSON object")

    name = entry.get("name")
    if not isinstance(name, str) or not PROFILE_NAME.fullmatch(name):
        raise ProfileError(
            f"Profile entry {index} has invalid name {name!r}; expected lowercase "
            "letters, digits, and underscores"
        )
    if name in names:
        raise ProfileError(f"Duplicate profile name: {name}")
    names.add(name)

    parameters = entry.get("parameters")
    if not isinstance(parameters, dict):
        raise ProfileError(f"Profile {name} must declare a parameters object")
    for parameter_name, value in parameters.items():
        if not isinstance(parameter_name, str) or not IDENTIFIER.fullmatch(
            parameter_name
        ):
            raise ProfileError(
                f"Profile {name} has invalid parameter name: {parameter_name!r}"
            )
        try:
            normalized_value(value)
        except ProfileError as error:
            raise ProfileError(f"Profile {name} has {error}") from error

    flows = entry.get("flows")
    if not isinstance(flows, list) or not flows:
        raise ProfileError(f"Profile {name} must declare a nonempty flows array")
    if any(not isinstance(flow, str) for flow in flows):
        raise ProfileError(f"Profile {name} flows must be strings")
    duplicate_flows = sorted({flow for flow in flows if flows.count(flow) > 1})
    if duplicate_flows:
        raise ProfileError(
            f"Profile {name} repeats flows: {', '.join(duplicate_flows)}"
        )
    unsupported = sorted(set(flows) - SUPPORTED_FLOWS)
    if unsupported:
        raise ProfileError(
            f"Profile {name} selects unsupported flows: {', '.join(unsupported)}"
        )
    for flow, dependencies in FLOW_DEPENDENCIES.items():
        if flow in flows and not dependencies.issubset(flows):
            missing = ", ".join(sorted(dependencies - set(flows)))
            raise ProfileError(f"Profile {name} flow {flow} requires: {missing}")

    tops = entry.get("tops", {})
    if not isinstance(tops, dict):
        raise ProfileError(f"Profile {name} tops must be a JSON object")
    unsupported_tops = sorted(set(tops) - TOP_FIELDS)
    if unsupported_tops:
        raise ProfileError(
            f"Profile {name} has unsupported top fields: {', '.join(unsupported_tops)}"
        )
    for top_kind, top_name in tops.items():
        if not isinstance(top_name, str) or not IDENTIFIER.fullmatch(top_name):
            raise ProfileError(
                f"Profile {name} has invalid {top_kind} top: {top_name!r}"
            )

    unknown_fields = sorted(set(entry) - {"name", "parameters", "flows", "tops"})
    if unknown_fields:
        raise ProfileError(
            f"Profile {name} has unsupported fields: {', '.join(unknown_fields)}"
        )
    return entry


def load_manifest(path: Path) -> dict[str, Any]:
    """Load and validate a parameter-profile manifest."""
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ProfileError(f"Parameter-profile manifest does not exist: {path}") from error
    except json.JSONDecodeError as error:
        raise ProfileError(
            f"Invalid JSON in {path}:{error.lineno}:{error.colno}: {error.msg}"
        ) from error

    if not isinstance(manifest, dict):
        raise ProfileError("Parameter-profile manifest root must be a JSON object")
    if manifest.get("schema") != SCHEMA:
        raise ProfileError(f"Parameter-profile manifest schema must be {SCHEMA!r}")
    if set(manifest) != {"schema", "include"}:
        unsupported = sorted(set(manifest) - {"schema", "include"})
        missing = sorted({"schema", "include"} - set(manifest))
        details = unsupported or missing
        raise ProfileError(
            "Parameter-profile manifest has invalid root fields: " + ", ".join(details)
        )

    entries = manifest.get("include")
    if not isinstance(entries, list) or not entries:
        raise ProfileError("Parameter-profile manifest 'include' must be nonempty")
    names: set[str] = set()
    for index, entry in enumerate(entries):
        validate_profile(entry, index, names)
    return manifest


def selected_profile(manifest: dict[str, Any], selected: str) -> dict[str, Any]:
    """Return one named profile or report the registered choices."""
    for entry in manifest["include"]:
        if entry["name"] == selected:
            return entry
    names = ", ".join(entry["name"] for entry in manifest["include"])
    raise ProfileError(f"Unknown PROFILE {selected!r}; registered profiles: {names}")


def matrix_entry(entry: dict[str, Any], module: str) -> dict[str, Any]:
    """Create one collision-resistant GitHub Actions matrix entry."""
    profile = entry["name"]
    result = {key: value for key, value in entry.items() if key != "name"}
    result["profile"] = profile
    if module:
        result["module"] = module
    result["job_name"] = f"{module or 'module'}--{profile}"
    return result


def parameter_arguments(parameters: dict[str, object], backend: str, top: str) -> list[str]:
    """Translate the canonical map into one backend's command-line arguments."""
    pairs = [(name, normalized_value(value)) for name, value in parameters.items()]
    if backend == "slang":
        return [item for name, value in pairs for item in ("-G", f"{name}={value}")]
    if backend == "verilator":
        return [f"-G{name}={value}" for name, value in pairs]
    if backend == "vcs":
        return [f"-pvalue+{top}.{name}={value}" for name, value in pairs]
    if backend == "dc":
        return [",".join(f"{name}={value}" for name, value in pairs)] if pairs else []
    if backend == "yosys":
        return [f"chparam -set {name} {value} {top};" for name, value in pairs]
    raise ProfileError(f"Unsupported parameter backend: {backend}")


def rewrite_prep_top(line: str, top: str) -> str:
    """Replace a Yosys prep command's top while retaining other options."""
    tokens = shlex.split(line)
    if not tokens or tokens[0] != "prep":
        return line
    if "-top" in tokens:
        tokens[tokens.index("-top") + 1] = top
    else:
        tokens.extend(["-top", top])
    return shlex.join(tokens)


def render_sby(source: Path, destination: Path, top: str, parameters: dict[str, object]) -> None:
    """Inject formal-top parameters before prep in an SBY script section."""
    lines = source.read_text(encoding="utf-8").splitlines()
    rendered: list[str] = []
    section = ""
    injected = False
    for line in lines:
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
        if section == "script" and shlex.split(line)[:1] == ["prep"]:
            for command in parameter_arguments(parameters, "yosys", top):
                rendered.append(command.removesuffix(";"))
            line = rewrite_prep_top(line, top)
            injected = True
        rendered.append(line)
    if not injected:
        raise ProfileError(f"SBY configuration has no prep command in [script]: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(rendered) + "\n", encoding="utf-8")


def render_eqy(
    source: Path,
    destination: Path,
    top: str,
    netlist: Path,
    parameters: dict[str, object],
) -> None:
    """Bind an EQY configuration to matching parameterized gold and gate inputs."""
    lines = source.read_text(encoding="utf-8").splitlines()
    rendered: list[str] = []
    section = ""
    injected_gold = False
    replaced_gate_inputs = 0
    for line in lines:
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
        tokens = shlex.split(line)
        if section == "gold" and tokens[:1] == ["prep"]:
            for command in parameter_arguments(parameters, "yosys", top):
                rendered.append(command.removesuffix(";"))
            line = rewrite_prep_top(line, top)
            injected_gold = True
        elif section == "gate" and tokens[:1] == ["prep"]:
            line = rewrite_prep_top(line, top)
        elif section == "gate" and tokens[:1] in (["read"], ["read_verilog"]):
            for index, token in enumerate(tokens):
                if token.endswith((".v", ".sv")):
                    tokens[index] = str(netlist)
                    replaced_gate_inputs += 1
            line = shlex.join(tokens)
        rendered.append(line)
    if not injected_gold:
        raise ProfileError(f"EQY configuration has no prep command in [gold]: {source}")
    if replaced_gate_inputs != 1:
        raise ProfileError(
            "EQY configuration must have exactly one gate HDL input, found "
            f"{replaced_gate_inputs}: {source}"
        )
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(rendered) + "\n", encoding="utf-8")


def parser() -> argparse.ArgumentParser:
    """Build the command-line interface shared by Make and flow adapters."""
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)

    for command in ("validate", "list", "matrix", "get", "evidence", "summary"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--manifest", required=True, type=Path)
        if command in {"get", "evidence"}:
            subparser.add_argument("--selected", required=True)
        if command == "validate":
            subparser.add_argument("--quiet", action="store_true")
        if command == "matrix":
            subparser.add_argument("--module", default="")
        if command == "get":
            subparser.add_argument(
                "--field",
                required=True,
                choices=("parameters", "flows", "design", "testbench", "formal", "pyuvm"),
            )
        if command == "evidence":
            subparser.add_argument("--output", required=True, type=Path)
            for top in sorted(TOP_FIELDS):
                subparser.add_argument(f"--{top}-top", required=True)
        if command == "summary":
            subparser.add_argument("--report-root", required=True, type=Path)
            subparser.add_argument("--output", required=True, type=Path)

    arguments = subparsers.add_parser("arguments")
    arguments.add_argument("--parameters", required=True)
    arguments.add_argument(
        "--backend", required=True, choices=("slang", "verilator", "vcs", "dc", "yosys")
    )
    arguments.add_argument("--top", required=True)

    for command in ("render-sby", "render-eqy"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--input", required=True, type=Path)
        subparser.add_argument("--output", required=True, type=Path)
        subparser.add_argument("--parameters", required=True)
        subparser.add_argument("--top", required=True)
        if command == "render-eqy":
            subparser.add_argument("--netlist", required=True, type=Path)

    subparsers.add_parser("combine-matrices")
    return result


def main() -> int:
    """Execute one validated manifest or adapter operation."""
    arguments = parser().parse_args()
    try:
        if arguments.command == "combine-matrices":
            entries: list[dict[str, Any]] = []
            job_names: set[str] = set()
            for line in sys.stdin:
                if not line.strip():
                    continue
                matrix = json.loads(line)
                for entry in matrix["include"]:
                    if entry["job_name"] in job_names:
                        raise ProfileError(f"Duplicate matrix job_name: {entry['job_name']}")
                    job_names.add(entry["job_name"])
                    entries.append(entry)
            print(json.dumps({"include": entries}, separators=(",", ":"), sort_keys=True))
            return 0

        if arguments.command in {"arguments", "render-sby", "render-eqy"}:
            parameters = json.loads(arguments.parameters)
            if not isinstance(parameters, dict):
                raise ProfileError("Parameters must decode to a JSON object")
            for name, value in parameters.items():
                if not IDENTIFIER.fullmatch(name):
                    raise ProfileError(f"Invalid parameter name: {name!r}")
                normalized_value(value)
            if arguments.command == "arguments":
                print("\n".join(parameter_arguments(parameters, arguments.backend, arguments.top)))
            elif arguments.command == "render-sby":
                render_sby(arguments.input, arguments.output, arguments.top, parameters)
            else:
                render_eqy(
                    arguments.input,
                    arguments.output,
                    arguments.top,
                    arguments.netlist,
                    parameters,
                )
            return 0

        manifest_path = arguments.manifest.resolve()
        manifest = load_manifest(manifest_path)
        entries = manifest["include"]
        if arguments.command == "validate":
            if not arguments.quiet:
                print(f"Validated {len(entries)} profiles from {manifest_path}")
        elif arguments.command == "list":
            print("\n".join(entry["name"] for entry in entries))
        elif arguments.command == "matrix":
            matrix = [matrix_entry(entry, arguments.module) for entry in entries]
            print(json.dumps({"include": matrix}, separators=(",", ":"), sort_keys=True))
        elif arguments.command == "summary":
            profiles = []
            aggregate_status = "PASS"
            for entry in entries:
                profile_root = arguments.report_root / entry["name"]
                statuses = {
                    str(path.parent.relative_to(profile_root)): path.read_text(
                        encoding="utf-8"
                    ).strip()
                    for path in sorted(profile_root.rglob("status.txt"))
                }
                if not statuses:
                    statuses = {"aggregate": "MISSING"}
                if any(status not in {"PASS", "SKIP"} for status in statuses.values()):
                    aggregate_status = "FAIL"
                profiles.append(
                    {
                        "profile": entry["name"],
                        "parameters": entry["parameters"],
                        "statuses": statuses,
                    }
                )
            summary = {
                "schema": SCHEMA,
                "aggregate_status": aggregate_status,
                "profiles": profiles,
            }
            arguments.output.parent.mkdir(parents=True, exist_ok=True)
            arguments.output.write_text(
                json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
            )
            if aggregate_status != "PASS":
                return 1
        else:
            entry = selected_profile(manifest, arguments.selected)
            if arguments.command == "get":
                if arguments.field == "parameters":
                    print(json.dumps(entry["parameters"], separators=(",", ":"), sort_keys=True))
                elif arguments.field == "flows":
                    print(" ".join(entry["flows"]))
                else:
                    print(entry.get("tops", {}).get(arguments.field, ""))
            else:
                evidence = {
                    "schema": SCHEMA,
                    "profile": entry["name"],
                    "parameters": entry["parameters"],
                    "flows": entry["flows"],
                    "tops": {
                        "design": arguments.design_top,
                        "testbench": arguments.testbench_top,
                        "formal": arguments.formal_top,
                        "pyuvm": arguments.pyuvm_top,
                    },
                }
                arguments.output.parent.mkdir(parents=True, exist_ok=True)
                arguments.output.write_text(
                    json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8"
                )
    except (ProfileError, json.JSONDecodeError, KeyError, IndexError) as error:
        print(f"parameter profile error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
