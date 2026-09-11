#!/usr/bin/env python3
"""Validate portable SDC and UPF intent without executing module-owned Tcl."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any


SCHEMA = "mosaic-static-intent-v1"
RESULT_SCHEMA = "mosaic-static-intent-result-v1"
NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_.-]*$")

SDC_OPTIONS = {
    "create_clock": ({"-name", "-period", "-waveform"}, {"-add"}),
    "create_generated_clock": (
        {
            "-name",
            "-source",
            "-master_clock",
            "-divide_by",
            "-multiply_by",
            "-edges",
            "-edge_shift",
            "-duty_cycle",
        },
        {"-add", "-combinational", "-invert"},
    ),
    "set_clock_uncertainty": (
        {"-from", "-to", "-rise_from", "-rise_to", "-fall_from", "-fall_to"},
        {"-setup", "-hold", "-rise", "-fall"},
    ),
    "set_input_delay": (
        {"-clock", "-reference_pin"},
        {"-add_delay", "-clock_fall", "-level_sensitive", "-max", "-min", "-network_latency_included", "-source_latency_included"},
    ),
    "set_output_delay": (
        {"-clock", "-reference_pin"},
        {"-add_delay", "-clock_fall", "-level_sensitive", "-max", "-min", "-network_latency_included", "-source_latency_included"},
    ),
    "set_max_delay": ({"-from", "-to", "-through"}, {"-datapath_only", "-ignore_clock_latency", "-rise", "-fall"}),
    "set_false_path": (
        {"-from", "-to", "-through", "-rise_from", "-rise_to", "-fall_from", "-fall_to"},
        {"-setup", "-hold", "-rise", "-fall"},
    ),
    "set_clock_groups": ({"-group", "-name"}, {"-asynchronous", "-exclusive", "-logically_exclusive", "-physically_exclusive", "-allow_paths"}),
    "set_input_transition": (set(), {"-rise", "-fall", "-max", "-min"}),
    "set_load": (set(), {"-subtract_pin_load", "-pin_load", "-wire_load", "-max", "-min"}),
    "set_case_analysis": (set(), set()),
}

UPF_OPTIONS = {
    "set_design_top": (set(), set()),
    "create_power_domain": ({"-elements", "-scope"}, {"-include_scope", "-atomic"}),
    "create_supply_port": ({"-domain", "-direction"}, set()),
    "create_supply_net": ({"-domain", "-resolve"}, {"-reuse"}),
    "connect_supply_net": ({"-ports", "-pins"}, {"-reuse"}),
    "set_domain_supply_net": ({"-primary_power_net", "-primary_ground_net", "-secondary_power_net", "-secondary_ground_net"}, set()),
    "add_port_state": ({"-state"}, set()),
    "create_pst": ({"-supplies"}, set()),
    "add_pst_state": ({"-pst", "-state"}, set()),
    "add_power_state": ({"-state", "-supply_expr", "-logic_expr", "-simstate"}, set()),
    "set_port_attributes": ({"-ports", "-elements", "-driver_supply", "-receiver_supply", "-feedthrough"}, set()),
    "set_isolation": ({"-domain", "-applies_to", "-clamp_value", "-isolation_power_net", "-isolation_ground_net", "-location", "-elements", "-source", "-sink", "-diff_supply_only"}, {"-no_isolation"}),
    "set_isolation_control": ({"-domain", "-isolation_signal", "-isolation_sense", "-location"}, set()),
    "set_level_shifter": ({"-domain", "-applies_to", "-rule", "-location", "-elements", "-source", "-sink", "-input_supply_set", "-output_supply_set", "-threshold"}, {"-no_shift"}),
    "set_retention": ({"-domain", "-retention_power_net", "-retention_ground_net", "-save_signal", "-restore_signal", "-elements"}, set()),
    "set_retention_control": ({"-domain", "-save_signal", "-restore_signal"}, set()),
    "create_power_switch": ({"-domain", "-input_supply_port", "-output_supply_port", "-control_port", "-on_state", "-off_state", "-ack_port"}, set()),
}

QUERY_COMMANDS = {
    "get_ports",
    "get_clocks",
    "get_pins",
    "get_cells",
    "all_inputs",
    "all_outputs",
    "remove_from_collection",
}

POLICY_REQUIREMENTS = {
    "sequential": {"create_clock", "set_clock_uncertainty", "set_input_delay", "set_output_delay"},
    "combinational": {"set_max_delay"},
    "clock_gating": {"create_clock", "create_generated_clock", "set_clock_uncertainty", "set_input_delay"},
    "reset_synchronizer": {"create_clock", "set_clock_uncertainty", "set_output_delay"},
}

POLICY_FORBIDDEN = {
    "sequential": set(),
    "combinational": {"create_clock", "create_generated_clock", "set_false_path", "set_clock_groups"},
    "clock_gating": {"set_false_path", "set_clock_groups", "set_output_delay"},
    "reset_synchronizer": {"set_clock_groups"},
}

STRATEGY_COMMANDS = {
    "isolation": "set_isolation",
    "level_shifting": "set_level_shifter",
    "retention": "set_retention",
    "power_switch": "create_power_switch",
}


class IntentError(ValueError):
    """Report invalid configuration or unsupported portable Tcl syntax."""


@dataclass
class Call:
    """One captured SDC or UPF command."""

    command: str
    arguments: list[dict[str, Any]]
    source: str
    line: int

    def canonical(self) -> str:
        """Return a stable representation for duplicate and consistency checks."""
        return json.dumps(
            {
                "command": self.command,
                "arguments": [canonical_value(value) for value in self.arguments],
            },
            sort_keys=True,
            separators=(",", ":"),
        )


def canonical_value(value: dict[str, Any]) -> dict[str, Any]:
    """Normalize numeric literals recursively while retaining Tcl value kinds."""
    if value.get("kind") == "literal":
        raw = str(value["value"])
        try:
            normalized = format(Decimal(raw).normalize(), "f")
        except InvalidOperation:
            normalized = raw
        return {"kind": "literal", "value": normalized}
    if value.get("kind") == "query":
        return {
            "kind": "query",
            "command": value["command"],
            "arguments": [
                canonical_value(argument) for argument in value.get("arguments", [])
            ],
        }
    return value


def finding(code: str, message: str, source: str = "", line: int = 0) -> dict[str, Any]:
    """Build one actionable error finding."""
    result: dict[str, Any] = {"code": code, "severity": "error", "message": message}
    if source:
        result["source"] = source
    if line:
        result["line"] = line
    return result


def split_commands(text: str, path: Path) -> list[tuple[str, int]]:
    """Split a Tcl file into commands without evaluating substitutions."""
    text = re.sub(r"\\\r?\n[ \t]*", " ", text)
    commands: list[tuple[str, int]] = []
    buffer: list[str] = []
    braces = 0
    brackets = 0
    quoted = False
    escaped = False
    line = 1
    command_line = 1
    only_space = True
    index = 0
    while index < len(text):
        character = text[index]
        if escaped:
            buffer.append(character)
            escaped = False
        elif character == "\\":
            buffer.append(character)
            escaped = True
        elif character == '"' and braces == 0:
            quoted = not quoted
            buffer.append(character)
            only_space = False
        elif not quoted and character == "{" and brackets >= 0:
            braces += 1
            buffer.append(character)
            only_space = False
        elif not quoted and character == "}" and braces:
            braces -= 1
            buffer.append(character)
        elif not quoted and braces == 0 and character == "[":
            brackets += 1
            buffer.append(character)
            only_space = False
        elif not quoted and braces == 0 and character == "]":
            if brackets == 0:
                raise IntentError(f"{path}:{line}: unmatched closing bracket")
            brackets -= 1
            buffer.append(character)
        elif not quoted and braces == 0 and brackets == 0 and character == "#" and only_space:
            while index < len(text) and text[index] != "\n":
                index += 1
            if index >= len(text):
                break
            character = "\n"
        elif not quoted and braces == 0 and brackets == 0 and character in {"\n", ";"}:
            command = "".join(buffer).strip()
            if command:
                commands.append((command, command_line))
            buffer = []
            only_space = True
            command_line = line + (character == "\n")
        else:
            buffer.append(character)
            if not character.isspace():
                only_space = False
        if character == "\n":
            line += 1
            if not buffer:
                command_line = line
        index += 1
    if quoted or braces or brackets:
        raise IntentError(f"{path}:{line}: unterminated Tcl grouping")
    command = "".join(buffer).strip()
    if command:
        commands.append((command, command_line))
    return commands


def split_words(command: str, source: str, line: int) -> list[str]:
    """Split one Tcl command while preserving grouped and nested words."""
    words: list[str] = []
    start: int | None = None
    braces = 0
    brackets = 0
    quoted = False
    escaped = False
    for index, character in enumerate(command):
        if start is None:
            if character.isspace():
                continue
            start = index
        if escaped:
            escaped = False
        elif character == "\\":
            escaped = True
        elif character == '"' and braces == 0:
            quoted = not quoted
        elif not quoted and character == "{" and brackets == 0:
            braces += 1
        elif not quoted and character == "}" and brackets == 0:
            braces -= 1
        elif not quoted and braces == 0 and character == "[":
            brackets += 1
        elif not quoted and braces == 0 and character == "]":
            brackets -= 1
        elif character.isspace() and not quoted and braces == 0 and brackets == 0:
            words.append(command[start:index])
            start = None
        if braces < 0 or brackets < 0:
            raise IntentError(f"{source}:{line}: malformed Tcl grouping")
    if start is not None:
        words.append(command[start:])
    if quoted or braces or brackets:
        raise IntentError(f"{source}:{line}: malformed Tcl word")
    return words


def list_items(text: str, source: str, line: int) -> list[str]:
    """Decode the literal Tcl lists used by the portable subset."""
    values = split_words(text, source, line)
    result = []
    for value in values:
        if value.startswith("{") and value.endswith("}"):
            value = value[1:-1].strip()
        if any(marker in value for marker in ("[", "]", "$", ";")):
            raise IntentError(f"{source}:{line}: substitutions are not supported inside literal lists")
        result.append(value.strip('"'))
    return result


def parse_value(word: str, source: str, line: int) -> dict[str, Any]:
    """Parse one literal, list, or supported collection expression."""
    if "$" in word:
        raise IntentError(f"{source}:{line}: variable substitution is unsupported")
    if word.startswith("{") and word.endswith("}"):
        return {"kind": "list", "items": list_items(word[1:-1], source, line)}
    if word.startswith("[") and word.endswith("]"):
        nested_words = split_words(word[1:-1].strip(), source, line)
        if not nested_words:
            raise IntentError(f"{source}:{line}: empty command substitution")
        command = nested_words[0]
        if command not in QUERY_COMMANDS:
            raise IntentError(f"{source}:{line}: unsupported query command {command}")
        arguments = [parse_value(item, source, line) for item in nested_words[1:]]
        expected = {"all_inputs": 0, "all_outputs": 0, "remove_from_collection": 2}
        if command in expected and len(arguments) != expected[command]:
            raise IntentError(
                f"{source}:{line}: {command} expects {expected[command]} arguments"
            )
        if command in {"get_ports", "get_clocks", "get_pins", "get_cells"} and not arguments:
            raise IntentError(f"{source}:{line}: {command} requires an object pattern")
        return {"kind": "query", "command": command, "arguments": arguments}
    if word.startswith('"') and word.endswith('"'):
        word = word[1:-1]
    if any(marker in word for marker in ("[", "]", "{", "}", ";")):
        raise IntentError(f"{source}:{line}: unsupported Tcl word {word!r}")
    return {"kind": "literal", "value": word.replace("\\ ", " ")}


def parse_file(path: Path, language: str) -> list[Call]:
    """Capture every command in one SDC or UPF file."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise IntentError(f"Cannot read {path}: {error}") from error
    supported = SDC_OPTIONS if language == "sdc" else UPF_OPTIONS
    calls = []
    for command_text, line in split_commands(text, path):
        words = split_words(command_text, str(path), line)
        command = words[0]
        if command not in supported:
            raise IntentError(f"{path}:{line}: unsupported {language.upper()} command {command}")
        arguments = [parse_value(word, str(path), line) for word in words[1:]]
        validate_options(command, arguments, supported[command], path, line)
        calls.append(Call(command, arguments, str(path), line))
    return calls


def literal(value: dict[str, Any], label: str) -> str:
    """Return a literal value or reject a selector/list at a scalar position."""
    if value.get("kind") != "literal" or not value.get("value"):
        raise IntentError(f"{label} must be a nonempty literal")
    return str(value["value"])


def validate_options(
    command: str,
    arguments: list[dict[str, Any]],
    specification: tuple[set[str], set[str]],
    path: Path,
    line: int,
) -> None:
    """Reject unsupported options and missing option values."""
    value_options, flags = specification
    index = 0
    while index < len(arguments):
        value = arguments[index]
        if value.get("kind") == "literal" and str(value.get("value", "")).startswith("-"):
            option = str(value["value"])
            if option in flags:
                index += 1
                continue
            if option not in value_options:
                try:
                    Decimal(option)
                except InvalidOperation as error:
                    raise IntentError(
                        f"{path}:{line}: unsupported option {option} for {command}"
                    ) from error
                index += 1
                continue
            if index + 1 >= len(arguments):
                raise IntentError(f"{path}:{line}: option {option} has no value")
            index += 2
            continue
        index += 1


def decoded(call: Call) -> tuple[list[dict[str, Any]], dict[str, list[dict[str, Any]]], set[str]]:
    """Separate positional values, repeated options, and flags."""
    value_options, valid_flags = (SDC_OPTIONS | UPF_OPTIONS)[call.command]
    positional: list[dict[str, Any]] = []
    options: dict[str, list[dict[str, Any]]] = {}
    flags: set[str] = set()
    index = 0
    while index < len(call.arguments):
        value = call.arguments[index]
        if value.get("kind") == "literal" and value.get("value") in valid_flags:
            flags.add(str(value["value"]))
            index += 1
        elif value.get("kind") == "literal" and value.get("value") in value_options:
            option = str(value["value"])
            options.setdefault(option, []).append(call.arguments[index + 1])
            index += 2
        else:
            positional.append(value)
            index += 1
    return positional, options, flags


def scalar_option(call: Call, name: str, required: bool = False) -> str | None:
    """Read one non-repeated literal option."""
    _, options, _ = decoded(call)
    values = options.get(name, [])
    if len(values) > 1:
        raise IntentError(f"{call.source}:{call.line}: {call.command} repeats {name}")
    if not values:
        if required:
            raise IntentError(f"{call.source}:{call.line}: {call.command} requires {name}")
        return None
    return literal(values[0], f"{call.command} {name}")


def positional_name(call: Call) -> str:
    """Return the first positional resource name."""
    positional, _, _ = decoded(call)
    if not positional:
        raise IntentError(f"{call.source}:{call.line}: {call.command} requires a name")
    return literal(positional[0], call.command)


def value_items(value: dict[str, Any]) -> list[str]:
    """Return names from a literal or literal-list value."""
    if value.get("kind") == "literal":
        return [str(value["value"])]
    if value.get("kind") == "list":
        return [str(item) for item in value["items"]]
    raise IntentError("Expected a literal object list")


def query_names(value: dict[str, Any], query: str) -> list[str] | None:
    """Return concrete names selected by one collection query."""
    if value.get("kind") != "query" or value.get("command") != query:
        return None
    names: list[str] = []
    for argument in value.get("arguments", []):
        names.extend(value_items(argument))
    return names


def selector_covers(value: dict[str, Any], port: str, direction: str) -> bool:
    """Determine whether a supported selector constrains one expected port."""
    direct = query_names(value, "get_ports")
    if direct is not None:
        return port in direct
    if value.get("kind") != "query":
        return False
    command = value.get("command")
    if command == f"all_{direction}s":
        return True
    if command == "remove_from_collection":
        arguments = value.get("arguments", [])
        if len(arguments) != 2 or not selector_covers(arguments[0], port, direction):
            return False
        removed = query_names(arguments[1], "get_ports")
        return removed is not None and port not in removed
    return False


def numeric_equal(first: str, second: object) -> bool:
    """Compare numeric policy values without formatting sensitivity."""
    try:
        return Decimal(first) == Decimal(str(second))
    except InvalidOperation:
        return False


def call_identity(call: Call) -> tuple[str, str]:
    """Build a semantic identity used to detect conflicting declarations."""
    if call.command in {"set_design_top"}:
        return call.command, "singleton"
    if call.command in {
        "create_clock",
        "create_generated_clock",
        "create_power_domain",
        "create_supply_port",
        "create_supply_net",
        "create_pst",
        "set_isolation",
        "set_level_shifter",
        "set_retention",
        "create_power_switch",
    }:
        name = scalar_option(call, "-name") if call.command in {"create_clock", "create_generated_clock"} else None
        return call.command, name or positional_name(call)
    if call.command == "set_domain_supply_net":
        return call.command, positional_name(call)
    if call.command in {
        "set_clock_uncertainty",
        "set_input_delay",
        "set_output_delay",
        "set_max_delay",
    }:
        positional, options, flags = decoded(call)
        selector_options = {
            option: values
            for option, values in options.items()
            if option in {"-clock", "-from", "-to", "-through"}
        }
        identity = json.dumps(
            {
                "selector_options": [
                    (option, [canonical_value(value) for value in values])
                    for option, values in sorted(selector_options.items())
                ],
                "selector": canonical_value(positional[-1]) if len(positional) > 1 else None,
                "flags": sorted(flags),
            },
            sort_keys=True,
        )
        return call.command, identity
    return call.command, call.canonical()


def duplicate_findings(calls: list[Call]) -> list[dict[str, Any]]:
    """Detect exact duplicate and conflicting singleton/resource commands."""
    results: list[dict[str, Any]] = []
    exact: dict[str, Call] = {}
    identities: dict[tuple[str, str], Call] = {}
    connected_objects: dict[str, tuple[str, Call]] = {}
    for call in calls:
        canonical = call.canonical()
        if canonical in exact:
            results.append(
                finding(
                    "duplicate_command",
                    f"Duplicate {call.command} repeats line {exact[canonical].line}",
                    call.source,
                    call.line,
                )
            )
            continue
        exact[canonical] = call
        identity = call_identity(call)
        if identity in identities and identities[identity].canonical() != canonical:
            results.append(
                finding(
                    "conflicting_command",
                    f"Conflicting {call.command} declaration for {identity[1]!r}; first declared at line {identities[identity].line}",
                    call.source,
                    call.line,
                )
            )
        else:
            identities[identity] = call
        if call.command == "connect_supply_net":
            net = positional_name(call)
            _, options, _ = decoded(call)
            for option in ("-ports", "-pins"):
                for value in options.get(option, []):
                    objects = query_names(value, "get_ports")
                    if objects is None:
                        objects = value_items(value)
                    for connected in objects:
                        previous = connected_objects.get(connected)
                        if previous and previous[0] != net:
                            results.append(
                                finding(
                                    "conflicting_command",
                                    f"Supply object {connected} is connected to both {previous[0]} and {net}",
                                    call.source,
                                    call.line,
                                )
                            )
                        else:
                            connected_objects[connected] = (net, call)
    return results


def require_string_array(value: object, label: str) -> list[str]:
    """Validate one unique string array from the expectation file."""
    if not isinstance(value, list) or not all(isinstance(item, str) and item for item in value):
        raise IntentError(f"{label} must be a string array")
    if len(value) != len(set(value)):
        raise IntentError(f"{label} contains duplicate values")
    return value


def resolve_module_path(module_root: Path, declared: object, label: str) -> Path:
    """Resolve and confine one module-owned configuration path."""
    if not isinstance(declared, (str, Path)) or not str(declared):
        raise IntentError(f"{label} must be a nonempty path")
    declared_path = Path(declared)
    if declared_path.is_absolute():
        path = declared_path.resolve()
    else:
        working_path = declared_path.resolve()
        path = working_path if working_path.exists() else (module_root / declared_path).resolve()
    try:
        path.relative_to(module_root.resolve())
    except ValueError as error:
        raise IntentError(f"{label} must be inside MODULE_ROOT: {path}") from error
    return path


def validate_sdc_profile(profile: dict[str, Any], module_root: Path) -> tuple[list[Call], list[dict[str, Any]]]:
    """Validate one named SDC profile and its interface policy."""
    allowed = {
        "name",
        "path",
        "kind",
        "expected_ports",
        "clocks",
        "generated_clocks",
        "intentional_exceptions",
        "forbidden_commands",
    }
    unknown = sorted(set(profile) - allowed)
    if unknown:
        raise IntentError(f"SDC profile has unknown fields: {', '.join(unknown)}")
    name = profile.get("name")
    kind = profile.get("kind")
    if not isinstance(name, str) or not NAME.fullmatch(name):
        raise IntentError("SDC profile name is invalid")
    if kind not in POLICY_REQUIREMENTS:
        raise IntentError(f"SDC profile {name} has an unsupported kind")
    path = resolve_module_path(module_root, profile.get("path"), f"SDC profile {name} path")
    calls = parse_file(path, "sdc")
    results = duplicate_findings(calls)
    commands = {call.command for call in calls}
    for required in sorted(POLICY_REQUIREMENTS[kind] - commands):
        results.append(finding("missing_command", f"{name} ({kind}) requires {required}", str(path)))
    if kind == "combinational" and "set_max_delay" in commands:
        complete_path = False
        for call in calls:
            if call.command != "set_max_delay":
                continue
            _, options, _ = decoded(call)
            from_values = options.get("-from", [])
            to_values = options.get("-to", [])
            if (
                len(from_values) == 1
                and from_values[0].get("command") == "all_inputs"
                and len(to_values) == 1
                and to_values[0].get("command") == "all_outputs"
            ):
                complete_path = True
        if not complete_path:
            results.append(
                finding(
                    "incomplete_max_delay",
                    f"{name} requires set_max_delay from all inputs to all outputs",
                    str(path),
                )
            )
    forbidden = POLICY_FORBIDDEN[kind] | set(
        require_string_array(profile.get("forbidden_commands", []), f"SDC profile {name} forbidden_commands")
    )
    for call in calls:
        if call.command in forbidden:
            results.append(finding("forbidden_command", f"{name} forbids {call.command}", call.source, call.line))

    expected_ports = profile.get("expected_ports", {})
    if not isinstance(expected_ports, dict) or set(expected_ports) - {"clock", "input_delay", "output_delay"}:
        raise IntentError(f"SDC profile {name} expected_ports is invalid")
    port_commands = {"clock": "create_clock", "input_delay": "set_input_delay", "output_delay": "set_output_delay"}
    directions = {"clock": "input", "input_delay": "input", "output_delay": "output"}
    for role, command in port_commands.items():
        ports = require_string_array(expected_ports.get(role, []), f"SDC profile {name} expected_ports.{role}")
        matching = [call for call in calls if call.command == command]
        for port in ports:
            covered = False
            for call in matching:
                positional, _, _ = decoded(call)
                if positional and selector_covers(positional[-1], port, directions[role]):
                    covered = True
                    break
            if not covered:
                results.append(finding("missing_port_constraint", f"{name} does not constrain expected {role} port {port}", str(path)))

    clocks = profile.get("clocks", [])
    if not isinstance(clocks, list):
        raise IntentError(f"SDC profile {name} clocks must be an array")
    for expected in clocks:
        if not isinstance(expected, dict) or set(expected) != {"name", "period", "port"}:
            raise IntentError(f"SDC profile {name} clock expectation is invalid")
        matched = False
        for call in calls:
            if call.command != "create_clock":
                continue
            positional, _, _ = decoded(call)
            clock_name = scalar_option(call, "-name", required=True)
            period = scalar_option(call, "-period", required=True)
            if clock_name == expected["name"] and numeric_equal(period or "", expected["period"]) and positional and selector_covers(positional[-1], str(expected["port"]), "input"):
                matched = True
        if not matched:
            results.append(finding("missing_clock", f"{name} lacks expected clock {expected['name']} on {expected['port']}", str(path)))

    generated = profile.get("generated_clocks", [])
    if not isinstance(generated, list):
        raise IntentError(f"SDC profile {name} generated_clocks must be an array")
    for expected in generated:
        required_fields = {"name", "source_port", "output_port", "combinational"}
        if not isinstance(expected, dict) or set(expected) != required_fields or not isinstance(expected["combinational"], bool):
            raise IntentError(f"SDC profile {name} generated-clock expectation is invalid")
        matched = False
        for call in calls:
            if call.command != "create_generated_clock":
                continue
            positional, options, flags = decoded(call)
            source_values = options.get("-source", [])
            if (
                scalar_option(call, "-name", required=True) == expected["name"]
                and len(source_values) == 1
                and query_names(source_values[0], "get_ports") == [expected["source_port"]]
                and positional
                and selector_covers(positional[-1], str(expected["output_port"]), "output")
                and ("-combinational" in flags) == expected["combinational"]
            ):
                matched = True
        if not matched:
            results.append(finding("missing_generated_clock", f"{name} lacks expected generated clock {expected['name']}", str(path)))

    expected_exceptions = profile.get("intentional_exceptions", [])
    if not isinstance(expected_exceptions, list):
        raise IntentError(f"SDC profile {name} intentional_exceptions must be an array")
    normalized_expected = []
    for exception in expected_exceptions:
        if not isinstance(exception, dict) or set(exception) != {"command", "from_ports", "to_ports"} or exception["command"] != "set_false_path":
            raise IntentError(f"SDC profile {name} has an invalid intentional exception")
        normalized_expected.append(
            (
                exception["command"],
                tuple(require_string_array(exception["from_ports"], "exception from_ports")),
                tuple(require_string_array(exception["to_ports"], "exception to_ports")),
            )
        )
    actual_exceptions = []
    for call in calls:
        if call.command != "set_false_path":
            continue
        _, options, _ = decoded(call)
        from_values = options.get("-from", [])
        to_values = options.get("-to", [])
        from_ports = query_names(from_values[0], "get_ports") if len(from_values) == 1 else None
        to_ports = query_names(to_values[0], "get_ports") if len(to_values) == 1 else []
        if from_ports is None or to_ports is None:
            results.append(finding("broad_exception", f"{name} contains a non-port or broad false path", call.source, call.line))
            continue
        actual_exceptions.append(("set_false_path", tuple(from_ports), tuple(to_ports)))
    for exception in actual_exceptions:
        if exception not in normalized_expected:
            results.append(finding("undeclared_exception", f"{name} contains an undeclared asynchronous exception {exception}", str(path)))
    for exception in normalized_expected:
        if exception not in actual_exceptions:
            results.append(finding("missing_exception", f"{name} lacks declared asynchronous exception {exception}", str(path)))
    return calls, results


def validate_sdc(section: object, module_root: Path) -> tuple[dict[str, list[Call]], list[dict[str, Any]]]:
    """Validate all SDC profiles and cross-profile consistency rules."""
    if not isinstance(section, dict) or set(section) - {"profiles", "consistency"}:
        raise IntentError("sdc must contain profiles and optional consistency")
    profiles = section.get("profiles")
    if not isinstance(profiles, list) or not profiles:
        raise IntentError("sdc.profiles must be a nonempty array")
    calls_by_profile: dict[str, list[Call]] = {}
    results: list[dict[str, Any]] = []
    for profile in profiles:
        if not isinstance(profile, dict):
            raise IntentError("Each SDC profile must be an object")
        name = str(profile.get("name", ""))
        if name in calls_by_profile:
            raise IntentError(f"Duplicate SDC profile name {name}")
        calls, profile_findings = validate_sdc_profile(profile, module_root)
        calls_by_profile[name] = calls
        results.extend(profile_findings)
    consistency = section.get("consistency", [])
    if not isinstance(consistency, list):
        raise IntentError("sdc.consistency must be an array")
    for rule in consistency:
        if not isinstance(rule, dict) or set(rule) != {"profiles", "commands"}:
            raise IntentError("Each SDC consistency rule must contain profiles and commands")
        names = require_string_array(rule["profiles"], "consistency profiles")
        commands = require_string_array(rule["commands"], "consistency commands")
        if len(names) < 2:
            raise IntentError("A consistency rule requires at least two profiles")
        if any(name not in calls_by_profile for name in names):
            raise IntentError("A consistency rule names an unknown SDC profile")
        baseline = sorted(call.canonical() for call in calls_by_profile[names[0]] if call.command in commands)
        for name in names[1:]:
            candidate = sorted(call.canonical() for call in calls_by_profile[name] if call.command in commands)
            if candidate != baseline:
                results.append(finding("profile_mismatch", f"SDC profiles {names[0]} and {name} differ for commands: {', '.join(commands)}"))
    return calls_by_profile, results


def named_calls(calls: list[Call], command: str) -> dict[str, Call]:
    """Index named UPF declarations after structural parsing."""
    return {positional_name(call): call for call in calls if call.command == command}


def option_items(call: Call, option: str) -> list[str]:
    """Return all literal/list items attached to a repeated option."""
    _, options, _ = decoded(call)
    result: list[str] = []
    for value in options.get(option, []):
        result.extend(value_items(value))
    return result


def validate_upf(section: object, module_root: Path) -> tuple[list[Call], list[dict[str, Any]]]:
    """Validate portable UPF resources, references, states, and strategies."""
    if not isinstance(section, dict) or set(section) != {"path", "top", "mode", "required", "forbidden_strategies"}:
        raise IntentError("upf must contain path, top, mode, required, and forbidden_strategies")
    if not isinstance(section["top"], str) or not NAME.fullmatch(section["top"]):
        raise IntentError("upf.top is invalid")
    if section["mode"] not in {"always_on", "boundary"}:
        raise IntentError("upf.mode must be always_on or boundary")
    path = resolve_module_path(module_root, section["path"], "UPF path")
    calls = parse_file(path, "upf")
    results = duplicate_findings(calls)
    tops = [positional_name(call) for call in calls if call.command == "set_design_top"]
    if tops != [section["top"]]:
        results.append(finding("design_top_mismatch", f"Expected one set_design_top {section['top']}, found {tops}", str(path)))

    required = section["required"]
    required_keys = {
        "power_domains",
        "supply_ports",
        "supply_nets",
        "supply_connections",
        "domain_supplies",
        "port_states",
        "power_state_tables",
        "power_states",
        "port_attribute_ports",
        "isolation",
        "level_shifting",
        "retention",
    }
    if not isinstance(required, dict) or set(required) - required_keys:
        raise IntentError("upf.required contains an unknown category")
    expected = {key: require_string_array(required.get(key, []), f"upf.required.{key}") for key in required_keys}

    resources = {
        "power_domains": named_calls(calls, "create_power_domain"),
        "supply_ports": named_calls(calls, "create_supply_port"),
        "supply_nets": named_calls(calls, "create_supply_net"),
        "power_state_tables": named_calls(calls, "create_pst"),
        "isolation": named_calls(calls, "set_isolation"),
        "level_shifting": named_calls(calls, "set_level_shifter"),
        "retention": named_calls(calls, "set_retention"),
    }
    for category, declarations in resources.items():
        for name in expected[category]:
            if name not in declarations:
                results.append(finding("missing_intent", f"UPF lacks required {category} declaration {name}", str(path)))

    domains = set(resources["power_domains"])
    supply_ports = set(resources["supply_ports"])
    supply_nets = set(resources["supply_nets"])
    domain_supplies = named_calls(calls, "set_domain_supply_net")
    connections = named_calls(calls, "connect_supply_net")
    for name in expected["domain_supplies"]:
        if name not in domain_supplies:
            results.append(finding("missing_intent", f"UPF lacks domain supply assignment for {name}", str(path)))
    for name in expected["supply_connections"]:
        if name not in connections:
            results.append(finding("missing_intent", f"UPF lacks supply connection for {name}", str(path)))
    for call in calls:
        if call.command in {"create_supply_port", "create_supply_net"}:
            domain = scalar_option(call, "-domain")
            if domain and domain not in domains:
                results.append(finding("unknown_reference", f"{call.command} references unknown domain {domain}", call.source, call.line))
        elif call.command == "connect_supply_net":
            net = positional_name(call)
            if net not in supply_nets:
                results.append(finding("unknown_reference", f"connect_supply_net references unknown net {net}", call.source, call.line))
        elif call.command == "set_domain_supply_net":
            domain = positional_name(call)
            if domain not in domains:
                results.append(finding("unknown_reference", f"set_domain_supply_net references unknown domain {domain}", call.source, call.line))
            for option in ("-primary_power_net", "-primary_ground_net", "-secondary_power_net", "-secondary_ground_net"):
                net = scalar_option(call, option)
                if net and net not in supply_nets:
                    results.append(finding("unknown_reference", f"{option} references unknown supply net {net}", call.source, call.line))

    port_state_names: set[str] = set()
    states_by_supply: dict[str, set[str]] = {}
    for call in calls:
        if call.command != "add_port_state":
            continue
        supply = positional_name(call)
        if supply not in supply_ports and supply not in supply_nets:
            results.append(finding("unknown_reference", f"add_port_state references unknown supply {supply}", call.source, call.line))
        states: set[str] = set()
        _, options, _ = decoded(call)
        for state in options.get("-state", []):
            items = value_items(state)
            if len(items) < 2:
                results.append(finding("incomplete_power_state", f"Port state on {supply} must contain a name and value", call.source, call.line))
            else:
                states.add(items[0])
                port_state_names.add(f"{supply}.{items[0]}")
        states_by_supply.setdefault(supply, set()).update(states)
    for expected_state in expected["port_states"]:
        if expected_state not in port_state_names:
            results.append(finding("missing_intent", f"UPF lacks required port state {expected_state}", str(path)))

    power_states: set[str] = set()
    pst_supplies: dict[str, list[str]] = {}
    for name, call in resources["power_state_tables"].items():
        supplies = option_items(call, "-supplies")
        pst_supplies[name] = supplies
        if not supplies:
            results.append(finding("incomplete_power_state", f"Power-state table {name} has no supplies", call.source, call.line))
        for supply in supplies:
            if supply not in states_by_supply:
                results.append(finding("incomplete_power_state", f"Power-state table {name} supply {supply} has no port states", call.source, call.line))
        if not any(
            candidate.command == "add_pst_state"
            and scalar_option(candidate, "-pst") == name
            for candidate in calls
        ):
            results.append(finding("incomplete_power_state", f"Power-state table {name} has no states", call.source, call.line))
    for call in calls:
        if call.command == "add_pst_state":
            state = positional_name(call)
            pst = scalar_option(call, "-pst", required=True) or ""
            values = option_items(call, "-state")
            power_states.add(f"{pst}.{state}")
            if pst not in pst_supplies:
                results.append(finding("unknown_reference", f"Power state {state} references unknown table {pst}", call.source, call.line))
            elif len(values) != len(pst_supplies[pst]):
                results.append(finding("incomplete_power_state", f"Power state {pst}.{state} has {len(values)} values for {len(pst_supplies[pst])} supplies", call.source, call.line))
            else:
                for supply, value in zip(pst_supplies[pst], values):
                    if value not in states_by_supply.get(supply, set()):
                        results.append(finding("unknown_reference", f"Power state {pst}.{state} uses unknown state {value} for {supply}", call.source, call.line))
        elif call.command == "add_power_state":
            target = positional_name(call)
            _, options, _ = decoded(call)
            states = options.get("-state", [])
            if not states:
                results.append(finding("incomplete_power_state", f"add_power_state for {target} has no -state", call.source, call.line))
            for state in states:
                items = value_items(state)
                if not items:
                    results.append(finding("incomplete_power_state", f"add_power_state for {target} has an empty state", call.source, call.line))
                else:
                    power_states.add(f"{target}.{items[0]}")
    for expected_state in expected["power_states"]:
        if expected_state not in power_states:
            results.append(finding("missing_intent", f"UPF lacks required power state {expected_state}", str(path)))

    attributed_ports: set[str] = set()
    for call in calls:
        if call.command == "set_port_attributes":
            _, options, _ = decoded(call)
            for value in options.get("-ports", []):
                ports = query_names(value, "get_ports")
                attributed_ports.update(ports if ports is not None else value_items(value))
    for port in expected["port_attribute_ports"]:
        if port not in attributed_ports:
            results.append(finding("missing_intent", f"UPF lacks required port attributes for {port}", str(path)))

    strategy_names = {category: set(resources[category]) for category in ("isolation", "level_shifting", "retention")}
    strategy_names["power_switch"] = set(named_calls(calls, "create_power_switch"))
    forbidden = set(require_string_array(section["forbidden_strategies"], "upf.forbidden_strategies"))
    unknown_strategies = forbidden - set(STRATEGY_COMMANDS)
    if unknown_strategies:
        raise IntentError(f"Unknown forbidden UPF strategies: {', '.join(sorted(unknown_strategies))}")
    if section["mode"] == "always_on":
        forbidden |= set(STRATEGY_COMMANDS)
    for strategy in sorted(forbidden):
        for strategy_name in sorted(strategy_names[strategy]):
            call = named_calls(calls, STRATEGY_COMMANDS[strategy])[strategy_name]
            results.append(finding("forbidden_strategy", f"UPF forbids {strategy} strategy {strategy_name}", call.source, call.line))

    mandatory_options = {
        "set_isolation": {"-domain", "-applies_to", "-clamp_value"},
        "set_level_shifter": {"-domain", "-applies_to", "-rule"},
        "set_retention": {"-domain", "-retention_power_net", "-retention_ground_net", "-save_signal", "-restore_signal"},
    }
    for call in calls:
        if call.command not in mandatory_options:
            continue
        _, options, _ = decoded(call)
        missing = sorted(mandatory_options[call.command] - set(options))
        if missing:
            results.append(finding("incomplete_strategy", f"{call.command} {positional_name(call)} lacks options: {', '.join(missing)}", call.source, call.line))
        domain = scalar_option(call, "-domain")
        if domain and domain not in domains:
            results.append(finding("unknown_reference", f"{call.command} references unknown domain {domain}", call.source, call.line))
    isolation_controls = set(named_calls(calls, "set_isolation_control"))
    for name, call in resources["isolation"].items():
        if name not in isolation_controls:
            results.append(finding("incomplete_strategy", f"Isolation strategy {name} has no set_isolation_control", call.source, call.line))
    return calls, results


def load_configuration(path: Path) -> dict[str, Any]:
    """Load and structurally validate the module-owned expectation file."""
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise IntentError(f"Cannot read static-intent configuration {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise IntentError(f"Static-intent JSON is invalid at column {error.colno}: {error.msg}") from error
    if not isinstance(config, dict) or set(config) - {"schema", "sdc", "upf"}:
        raise IntentError("Static-intent root has unknown fields")
    if config.get("schema") != SCHEMA:
        raise IntentError(f"Static-intent schema must be {SCHEMA}")
    if "sdc" not in config and "upf" not in config:
        raise IntentError("Static-intent configuration must define sdc, upf, or both")
    return config


def report_section(
    kind: str, configured: bool, calls: int, findings: list[dict[str, Any]]
) -> dict[str, Any]:
    """Create one deterministic SDC or UPF findings report."""
    status = "FAIL" if findings else "PASS" if configured else "SKIP"
    return {
        "schema": RESULT_SCHEMA,
        "kind": kind,
        "status": status,
        "commands_captured": calls,
        "findings": findings,
    }


def write_json(path: Path, value: object) -> None:
    """Write stable JSON evidence."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def validate(config_path: Path, module_root: Path, output_dir: Path) -> int:
    """Run configured SDC and UPF checks and write complete evidence."""
    sdc_findings: list[dict[str, Any]] = []
    upf_findings: list[dict[str, Any]] = []
    sdc_call_count = 0
    upf_call_count = 0
    sdc_configured = False
    upf_configured = False
    try:
        config_path = resolve_module_path(
            module_root, config_path, "Static-intent configuration"
        )
        config = load_configuration(config_path)
        if "sdc" in config:
            sdc_configured = True
            try:
                profiles, sdc_findings = validate_sdc(config["sdc"], module_root)
                sdc_call_count = sum(len(calls) for calls in profiles.values())
            except IntentError as error:
                sdc_findings = [finding("invalid_sdc_intent", str(error))]
        if "upf" in config:
            upf_configured = True
            try:
                calls, upf_findings = validate_upf(config["upf"], module_root)
                upf_call_count = len(calls)
            except IntentError as error:
                upf_findings = [finding("invalid_upf_intent", str(error))]
    except IntentError as error:
        sdc_findings = [finding("invalid_configuration", str(error))]

    sdc_report = report_section("sdc", sdc_configured, sdc_call_count, sdc_findings)
    upf_report = report_section("upf", upf_configured, upf_call_count, upf_findings)
    write_json(output_dir / "sdc-findings.json", sdc_report)
    write_json(output_dir / "upf-findings.json", upf_report)
    all_findings = sdc_findings + upf_findings
    try:
        configuration_label = str(config_path.resolve().relative_to(module_root.resolve()))
    except ValueError:
        configuration_label = str(config_path.resolve())
    summary = {
        "schema": RESULT_SCHEMA,
        "kind": "aggregate",
        "status": "PASS" if not all_findings else "FAIL",
        "configuration": configuration_label,
        "sdc": {"status": sdc_report["status"], "findings": len(sdc_findings)},
        "upf": {"status": upf_report["status"], "findings": len(upf_findings)},
    }
    write_json(output_dir / "summary.json", summary)
    (output_dir / "status.txt").write_text(f"{summary['status']}\n", encoding="utf-8")
    for item in all_findings:
        location = f"{item.get('source', '')}:{item.get('line', '')}".strip(":")
        print(f"{location + ': ' if location else ''}{item['code']}: {item['message']}", file=sys.stderr)
    return 0 if not all_findings else 1


def build_parser() -> argparse.ArgumentParser:
    """Build the command-line interface."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--module-root", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    return parser


def main() -> int:
    """Run the command-line validator."""
    arguments = build_parser().parse_args()
    return validate(arguments.config, arguments.module_root, arguments.output_dir)


if __name__ == "__main__":
    raise SystemExit(main())
