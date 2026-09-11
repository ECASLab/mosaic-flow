#!/usr/bin/env python3
"""Validate declarative HDL coverage requirements and emit release evidence."""

from __future__ import annotations

import argparse
import fnmatch
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any


SCHEMA = "mosaic-coverage-policy-v1"
METRICS = {"line", "branch", "toggle", "user"}
COVERPOINT_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_$]*$")
NATIVE_RECORD = re.compile(r"^C '(.*)'\s+([0-9]+)$")


class QualificationError(ValueError):
    """Describe a policy or evidence problem that the module owner can fix."""


@dataclass(frozen=True)
class CoverageRecord:
    """One normalized coverage counter from native or LCOV evidence."""

    source: str
    line: int
    metric: str
    name: str
    hits: int
    origin: str


def object_with_keys(value: Any, label: str, allowed: set[str], required: set[str]) -> dict[str, Any]:
    """Require an object with an exact, documented key vocabulary."""
    if not isinstance(value, dict):
        raise QualificationError(f"{label} must be an object")
    unknown = set(value) - allowed
    missing = required - set(value)
    if unknown:
        raise QualificationError(f"{label} has unknown fields: {', '.join(sorted(unknown))}")
    if missing:
        raise QualificationError(f"{label} is missing fields: {', '.join(sorted(missing))}")
    return value


def nonempty_string(value: Any, label: str) -> str:
    """Require one nonempty string without silently coercing values."""
    if not isinstance(value, str) or not value.strip():
        raise QualificationError(f"{label} must be a nonempty string")
    return value.strip()


def load_policy(path: Path, module_root: Path) -> dict[str, Any]:
    """Load and strictly validate the versioned module policy."""
    try:
        policy = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise QualificationError(f"Coverage policy is missing: {path}") from error
    except json.JSONDecodeError as error:
        raise QualificationError(
            f"Coverage policy is invalid JSON at line {error.lineno}, column {error.colno}: {error.msg}"
        ) from error

    object_with_keys(
        policy,
        "policy",
        {"schema", "scope", "thresholds", "coverpoints", "exclusions", "formal"},
        {"schema", "thresholds", "coverpoints", "exclusions", "formal"},
    )
    if policy["schema"] != SCHEMA:
        raise QualificationError(f"policy.schema must be {SCHEMA}")

    scope = object_with_keys(policy.get("scope", {}), "policy.scope", {"include", "exclude"}, set())
    for field in ("include", "exclude"):
        values = scope.get(field, [])
        if not isinstance(values, list) or not all(isinstance(item, str) and item for item in values):
            raise QualificationError(f"policy.scope.{field} must be an array of nonempty strings")
    if "include" in scope and not scope["include"]:
        raise QualificationError("policy.scope.include must not be empty")

    thresholds = object_with_keys(policy["thresholds"], "policy.thresholds", METRICS, set())
    for metric, threshold in thresholds.items():
        if isinstance(threshold, bool) or not isinstance(threshold, (int, float)) or not 0 <= threshold <= 100:
            raise QualificationError(f"thresholds.{metric} must be a number from 0 through 100")

    coverpoints = policy["coverpoints"]
    if not isinstance(coverpoints, list):
        raise QualificationError("policy.coverpoints must be an array")
    seen_coverpoints: set[str] = set()
    for index, item in enumerate(coverpoints):
        item = object_with_keys(item, f"coverpoints[{index}]", {"name", "minimum_hits"}, {"name", "minimum_hits"})
        name = nonempty_string(item["name"], f"coverpoints[{index}].name")
        if not COVERPOINT_NAME.fullmatch(name):
            raise QualificationError(f"coverpoints[{index}].name is not a valid SystemVerilog label")
        if name in seen_coverpoints:
            raise QualificationError(f"Duplicate coverpoint requirement: {name}")
        seen_coverpoints.add(name)
        minimum = item["minimum_hits"]
        if isinstance(minimum, bool) or not isinstance(minimum, int) or minimum < 1:
            raise QualificationError(f"coverpoints[{index}].minimum_hits must be a positive integer")

    exclusions = policy["exclusions"]
    if not isinstance(exclusions, list):
        raise QualificationError("policy.exclusions must be an array")
    seen_exclusions: set[str] = set()
    for index, item in enumerate(exclusions):
        item = object_with_keys(
            item,
            f"exclusions[{index}]",
            {"source", "metric", "reason", "owner", "scope"},
            {"source", "metric", "reason", "owner", "scope"},
        )
        source = nonempty_string(item["source"], f"exclusions[{index}].source")
        source_path = PurePosixPath(source)
        if source_path.is_absolute() or ".." in source_path.parts:
            raise QualificationError(f"exclusions[{index}].source must be module-relative")
        if not (module_root / source_path).is_file():
            raise QualificationError(f"exclusions[{index}].source does not exist: {source}")
        if item["metric"] not in METRICS:
            raise QualificationError(f"exclusions[{index}].metric must name a supported metric")
        nonempty_string(item["reason"], f"exclusions[{index}].reason")
        nonempty_string(item["owner"], f"exclusions[{index}].owner")
        item_scope = object_with_keys(
            item["scope"], f"exclusions[{index}].scope", {"line_start", "line_end", "name"}, set()
        )
        if not item_scope:
            raise QualificationError(f"exclusions[{index}].scope must not be empty")
        for field in ("line_start", "line_end"):
            if field in item_scope and (
                isinstance(item_scope[field], bool)
                or not isinstance(item_scope[field], int)
                or item_scope[field] < 1
            ):
                raise QualificationError(f"exclusions[{index}].scope.{field} must be a positive integer")
        if "line_end" in item_scope and "line_start" not in item_scope:
            raise QualificationError(f"exclusions[{index}].scope.line_end requires line_start")
        if item_scope.get("line_end", item_scope.get("line_start", 1)) < item_scope.get("line_start", 1):
            raise QualificationError(f"exclusions[{index}] has an inverted line range")
        if "name" in item_scope:
            nonempty_string(item_scope["name"], f"exclusions[{index}].scope.name")
        fingerprint = json.dumps(item, sort_keys=True)
        if fingerprint in seen_exclusions:
            raise QualificationError(f"Duplicate exclusion at index {index}")
        seen_exclusions.add(fingerprint)

    formal = object_with_keys(policy["formal"], "policy.formal", {"required"}, {"required"})
    if not isinstance(formal["required"], bool):
        raise QualificationError("policy.formal.required must be true or false")
    return policy


def normalize_source(source: str, module_root: Path) -> str:
    """Normalize simulator paths to a module-relative POSIX spelling when possible."""
    path = Path(source)
    if path.is_absolute():
        try:
            return path.resolve().relative_to(module_root.resolve()).as_posix()
        except ValueError:
            return path.as_posix()
    text = PurePosixPath(source).as_posix()
    while text.startswith("./"):
        text = text[2:]
    return text


def parse_native(path: Path, module_root: Path) -> list[CoverageRecord]:
    """Parse Verilator's tagged native counters without assuming page names."""
    if not path.is_file():
        return []
    records: list[CoverageRecord] = []
    for line_number, raw_line in enumerate(path.read_text(encoding="latin-1").splitlines(), 1):
        if not raw_line.startswith("C "):
            continue
        match = NATIVE_RECORD.fullmatch(raw_line)
        if not match:
            raise QualificationError(f"Malformed native coverage record at {path}:{line_number}")
        tagged, hits_text = match.groups()
        fields: dict[str, str] = {}
        for part in tagged.split("\x01"):
            if "\x02" in part:
                key, value = part.split("\x02", 1)
                fields[key] = value
        metric = fields.get("t", "")
        if metric not in METRICS:
            continue
        try:
            source_line = int(fields.get("l", "0"))
        except ValueError as error:
            raise QualificationError(f"Invalid native source line at {path}:{line_number}") from error
        records.append(
            CoverageRecord(
                normalize_source(fields.get("f", ""), module_root),
                source_line,
                metric,
                fields.get("o", ""),
                int(hits_text),
                "verilator_native",
            )
        )
    return records


def parse_lcov(path: Path, module_root: Path) -> list[CoverageRecord]:
    """Parse LCOV lines and split Verilator transition branches from control branches."""
    if not path.is_file():
        return []
    records: list[CoverageRecord] = []
    source = ""
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if raw_line.startswith("SF:"):
            source = normalize_source(raw_line[3:], module_root)
        elif raw_line.startswith("DA:"):
            if not source:
                raise QualificationError(f"LCOV DA record precedes SF at {path}:{line_number}")
            fields = raw_line[3:].split(",")
            if len(fields) < 2:
                raise QualificationError(f"Malformed LCOV DA record at {path}:{line_number}")
            records.append(CoverageRecord(source, int(fields[0]), "line", "", int(fields[1]), "lcov"))
        elif raw_line.startswith("BRDA:"):
            if not source:
                raise QualificationError(f"LCOV BRDA record precedes SF at {path}:{line_number}")
            fields = raw_line[5:].split(",", 3)
            if len(fields) != 4:
                raise QualificationError(f"Malformed LCOV BRDA record at {path}:{line_number}")
            metric = "toggle" if "->" in fields[2] else "branch"
            hits = 0 if fields[3] == "-" else int(fields[3])
            records.append(CoverageRecord(source, int(fields[0]), metric, fields[2], hits, "lcov"))
    return records


def source_selected(source: str, policy: dict[str, Any]) -> bool:
    """Apply optional module-owned include and exclude globs."""
    scope = policy.get("scope", {})
    includes = scope.get("include", ["*"])
    excludes = scope.get("exclude", [])
    return any(fnmatch.fnmatchcase(source, pattern) for pattern in includes) and not any(
        fnmatch.fnmatchcase(source, pattern) for pattern in excludes
    )


def exclusion_matches(exclusion: dict[str, Any], record: CoverageRecord) -> bool:
    """Match one reviewed exclusion against one normalized evidence counter."""
    if exclusion["source"] != record.source or exclusion["metric"] != record.metric:
        return False
    scope = exclusion["scope"]
    start = scope.get("line_start")
    end = scope.get("line_end", start)
    if start is not None and not start <= record.line <= end:
        return False
    return "name" not in scope or scope["name"] == record.name


def select_records(native: list[CoverageRecord], lcov: list[CoverageRecord]) -> list[CoverageRecord]:
    """Prefer typed native metrics and use LCOV only where native lacks a metric."""
    selected: list[CoverageRecord] = []
    for metric in sorted(METRICS):
        native_metric = [record for record in native if record.metric == metric]
        selected.extend(native_metric or [record for record in lcov if record.metric == metric])
    return selected


def qualify(
    policy: dict[str, Any],
    records: list[CoverageRecord],
    formal_result: str,
    formal_reached: int,
    source_name: str,
) -> tuple[dict[str, Any], list[str]]:
    """Apply exclusions, percentages, named points, and formal reachability."""
    failures: list[str] = []
    scoped = [record for record in records if source_selected(record.source, policy)]
    exclusion_results: list[dict[str, Any]] = []
    excluded_indexes: set[int] = set()
    for exclusion_index, exclusion in enumerate(policy["exclusions"]):
        matches = [index for index, record in enumerate(scoped) if exclusion_matches(exclusion, record)]
        if not matches:
            failures.append(
                f"exclusion[{exclusion_index}] is stale or unmatched: "
                f"{exclusion['metric']} {exclusion['source']} {exclusion['scope']}"
            )
        excluded_indexes.update(matches)
        exclusion_results.append({**exclusion, "matched_records": len(matches)})

    effective = [record for index, record in enumerate(scoped) if index not in excluded_indexes]
    metric_results: dict[str, dict[str, Any]] = {}
    for metric in sorted(METRICS):
        metric_records = [record for record in effective if record.metric == metric]
        hit = sum(record.hits > 0 for record in metric_records)
        total = len(metric_records)
        percent = 100.0 * hit / total if total else None
        threshold = policy["thresholds"].get(metric)
        passed = threshold is None or (percent is not None and percent >= threshold)
        if threshold is not None and total == 0:
            failures.append(f"{metric} threshold {threshold:g}% has no matching coverage counters")
        elif threshold is not None and not passed:
            failures.append(f"{metric} coverage {percent:.2f}% is below threshold {threshold:g}%")
        metric_results[metric] = {
            "total": total,
            "hit": hit,
            "excluded": sum(
                record.metric == metric for index, record in enumerate(scoped) if index in excluded_indexes
            ),
            "percent": None if percent is None else round(percent, 4),
            "threshold": threshold,
            "passed": passed,
        }

    coverpoint_results: list[dict[str, Any]] = []
    user_records = [record for record in effective if record.metric == "user"]
    for requirement in policy["coverpoints"]:
        matching = [record for record in user_records if record.name == requirement["name"]]
        hits = sum(record.hits for record in matching)
        passed = bool(matching) and hits >= requirement["minimum_hits"]
        if not matching:
            failures.append(f"required coverpoint {requirement['name']} is absent from native HDL coverage")
        elif not passed:
            failures.append(
                f"coverpoint {requirement['name']} has {hits} hits, requires {requirement['minimum_hits']}"
            )
        coverpoint_results.append({**requirement, "hits": hits, "records": len(matching), "passed": passed})

    formal_required = policy["formal"]["required"]
    if formal_required and formal_result != "PASS":
        failures.append(f"formal cover reachability is {formal_result}, expected PASS for all cover statements")
    elif formal_required and formal_reached < 1:
        failures.append("formal cover configuration reached no cover statements")
    formal = {
        "required": formal_required,
        "status": formal_result if formal_required else "SKIP",
        "reached_statements": formal_reached if formal_required else 0,
    }
    status = "FAIL" if failures else "PASS"
    summary = {
        "schema": "mosaic-coverage-qualification-v1",
        "status": status,
        "source": source_name,
        "metrics": metric_results,
        "coverpoints": coverpoint_results,
        "exclusions": exclusion_results,
        "formal": formal,
        "failures": failures,
    }
    return summary, failures


def write_summary(path: Path, summary: dict[str, Any]) -> None:
    """Write deterministic, reviewable machine evidence."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def command_inspect(arguments: argparse.Namespace) -> int:
    """Expose validated policy fields to the shell adapter."""
    policy = load_policy(arguments.policy.resolve(), arguments.module_root.resolve())
    if arguments.field == "formal.required":
        print("true" if policy["formal"]["required"] else "false")
    return 0


def command_qualify(arguments: argparse.Namespace) -> int:
    """Normalize evidence, evaluate policy, and always preserve a JSON result."""
    output = arguments.output.resolve()
    try:
        policy = load_policy(arguments.policy.resolve(), arguments.module_root.resolve())
        native = parse_native(arguments.native.resolve(), arguments.module_root.resolve())
        lcov = parse_lcov(arguments.lcov.resolve(), arguments.module_root.resolve())
        if not native and not lcov:
            raise QualificationError("No native or LCOV coverage counters were found")
        summary, failures = qualify(
            policy,
            select_records(native, lcov),
            arguments.formal_result,
            arguments.formal_reached,
            arguments.source,
        )
    except (OSError, UnicodeError, ValueError) as error:
        failures = [str(error)]
        summary = {
            "schema": "mosaic-coverage-qualification-v1",
            "status": "FAIL",
            "source": arguments.source,
            "metrics": {},
            "coverpoints": [],
            "exclusions": [],
            "formal": {
                "required": None,
                "status": arguments.formal_result,
                "reached_statements": arguments.formal_reached,
            },
            "failures": failures,
        }
    write_summary(output, summary)
    for failure in failures:
        print(f"Coverage qualification: {failure}", file=sys.stderr)
    if failures:
        return 1
    print(f"Coverage qualification passed using {arguments.source}")
    return 0


def command_failure(arguments: argparse.Namespace) -> int:
    """Preserve a structured result for adapter failures before qualification."""
    summary = {
        "schema": "mosaic-coverage-qualification-v1",
        "status": "FAIL",
        "source": arguments.source,
        "metrics": {},
        "coverpoints": [],
        "exclusions": [],
        "formal": {
            "required": None,
            "status": arguments.formal_result,
            "reached_statements": 0,
        },
        "failures": [arguments.message],
    }
    write_summary(arguments.output.resolve(), summary)
    return 0


def parser() -> argparse.ArgumentParser:
    """Build the command-line contract used by Make and unit fixtures."""
    root = argparse.ArgumentParser(description=__doc__)
    subparsers = root.add_subparsers(dest="command", required=True)

    inspect = subparsers.add_parser("inspect", help="validate and read policy controls")
    inspect.add_argument("--policy", type=Path, required=True)
    inspect.add_argument("--module-root", type=Path, required=True)
    inspect.add_argument("--field", choices=["formal.required"], required=True)
    inspect.set_defaults(function=command_inspect)

    qualify_parser = subparsers.add_parser("qualify", help="qualify collected HDL coverage")
    qualify_parser.add_argument("--policy", type=Path, required=True)
    qualify_parser.add_argument("--module-root", type=Path, required=True)
    qualify_parser.add_argument("--native", type=Path, required=True)
    qualify_parser.add_argument("--lcov", type=Path, required=True)
    qualify_parser.add_argument("--source", required=True)
    qualify_parser.add_argument("--formal-result", choices=["PASS", "FAIL", "SKIP"], required=True)
    qualify_parser.add_argument("--formal-reached", type=int, default=0)
    qualify_parser.add_argument("--output", type=Path, required=True)
    qualify_parser.set_defaults(function=command_qualify)

    failure = subparsers.add_parser("record-failure", help="record an early adapter failure")
    failure.add_argument("--source", required=True)
    failure.add_argument("--message", required=True)
    failure.add_argument("--formal-result", choices=["PASS", "FAIL", "SKIP"], default="SKIP")
    failure.add_argument("--output", type=Path, required=True)
    failure.set_defaults(function=command_failure)
    return root


def main() -> int:
    """Run one selected coverage-policy operation."""
    arguments = parser().parse_args()
    try:
        return arguments.function(arguments)
    except QualificationError as error:
        print(f"Coverage qualification: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
