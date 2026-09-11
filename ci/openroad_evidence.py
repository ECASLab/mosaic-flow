#!/usr/bin/env python3
"""Validate module-owned OpenROAD deliverables and violation thresholds."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


POLICY_SCHEMA = "mosaic-openroad-evidence-policy-v1"
RESULT_SCHEMA = "mosaic-openroad-evidence-result-v1"
NAME = re.compile(r"^[a-z][a-z0-9_]*$")
IMAGE_DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
IMAGE_REFERENCE = re.compile(r"^\S+@sha256:[0-9a-f]{64}$")
DIRECTORIES = {"results", "reports", "logs", "objects"}


class EvidenceError(ValueError):
    """Report invalid policy or missing physical evidence."""


def sha256(path: Path) -> str:
    """Hash one nonempty regular file."""
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def checked_file(path: Path, label: str) -> Path:
    """Require a nonempty regular file and return its resolved path."""
    resolved = path.resolve()
    if not resolved.is_file():
        raise EvidenceError(f"Missing {label}: {resolved}")
    if resolved.stat().st_size == 0:
        raise EvidenceError(f"Empty {label}: {resolved}")
    return resolved


def relative_record(path: Path, module_root: Path) -> dict[str, Any]:
    """Describe a file with a stable module-relative path when possible."""
    resolved = path.resolve()
    try:
        display_path = resolved.relative_to(module_root.resolve()).as_posix()
    except ValueError:
        display_path = str(resolved)
    return {
        "path": display_path,
        "bytes": resolved.stat().st_size,
        "sha256": sha256(resolved),
    }


def policy_path(
    root: Path,
    entry: dict[str, Any],
    platform: str,
    design: str,
    variant: str,
) -> Path:
    """Resolve a policy path below its declared ORFS evidence directory."""
    relative = Path(entry["path"])
    if relative.is_absolute() or ".." in relative.parts:
        raise EvidenceError(f"Policy path must be relative and contained: {relative}")
    return root / entry["directory"] / platform / design / variant / relative


def validate_policy(policy: object) -> dict[str, Any]:
    """Validate the policy subset used by the dependency-free implementation."""
    if not isinstance(policy, dict) or set(policy) != {
        "schema",
        "artifacts",
        "metrics",
    }:
        raise EvidenceError("OpenROAD policy root has invalid fields")
    if policy["schema"] != POLICY_SCHEMA:
        raise EvidenceError(f"OpenROAD policy schema must be {POLICY_SCHEMA}")

    for section in ("artifacts", "metrics"):
        if not isinstance(policy[section], list) or not policy[section]:
            raise EvidenceError(f"OpenROAD policy {section} must be a nonempty array")

    names: set[str] = set()
    for index, artifact in enumerate(policy["artifacts"]):
        if not isinstance(artifact, dict) or set(artifact) != {
            "name",
            "directory",
            "path",
        }:
            raise EvidenceError(f"Artifact {index} has invalid fields")
        validate_entry(artifact, f"Artifact {index}")
        if artifact["name"] in names:
            raise EvidenceError(f"Duplicate evidence name: {artifact['name']}")
        names.add(artifact["name"])

    for index, metric in enumerate(policy["metrics"]):
        if not isinstance(metric, dict):
            raise EvidenceError(f"Metric {index} must be an object")
        allowed = {
            "name",
            "directory",
            "path",
            "pattern",
            "match",
            "minimum",
            "maximum",
        }
        if not {"name", "directory", "path", "pattern"}.issubset(metric) or not set(
            metric
        ).issubset(allowed):
            raise EvidenceError(f"Metric {index} has invalid fields")
        validate_entry(metric, f"Metric {index}")
        if metric["name"] in names:
            raise EvidenceError(f"Duplicate evidence name: {metric['name']}")
        names.add(metric["name"])
        if "minimum" not in metric and "maximum" not in metric:
            raise EvidenceError(f"Metric {metric['name']} has no threshold")
        if metric.get("match", "only") not in {"only", "first", "last"}:
            raise EvidenceError(
                f"Metric {metric['name']} match must be only, first, or last"
            )
        for threshold in ("minimum", "maximum"):
            if threshold in metric and (
                isinstance(metric[threshold], bool)
                or not isinstance(metric[threshold], int)
                or metric[threshold] < 0
            ):
                raise EvidenceError(
                    f"Metric {metric['name']} {threshold} must be a nonnegative integer"
                )
        try:
            expression = re.compile(metric["pattern"], re.MULTILINE)
        except (TypeError, re.error) as error:
            raise EvidenceError(
                f"Metric {metric['name']} has an invalid pattern: {error}"
            ) from error
        if "value" not in expression.groupindex:
            raise EvidenceError(
                f"Metric {metric['name']} pattern must define named group 'value'"
            )
    return policy


def validate_entry(entry: dict[str, Any], label: str) -> None:
    """Validate fields shared by artifact and metric entries."""
    if not isinstance(entry.get("name"), str) or not NAME.fullmatch(entry["name"]):
        raise EvidenceError(f"{label} has an invalid name")
    if entry.get("directory") not in DIRECTORIES:
        raise EvidenceError(f"{label} has an invalid directory")
    path = entry.get("path")
    if (
        not isinstance(path, str)
        or not path
        or Path(path).is_absolute()
        or ".." in Path(path).parts
    ):
        raise EvidenceError(f"{label} has an invalid relative path")


def load_policy(path: Path) -> dict[str, Any]:
    """Read and validate one JSON physical evidence policy."""
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EvidenceError(f"Cannot read OpenROAD policy {path}: {error}") from error
    return validate_policy(raw)


def qualify(args: argparse.Namespace) -> dict[str, Any]:
    """Evaluate artifacts and metrics and return normalized evidence."""
    module_root = args.module_root.resolve()
    evidence_root = args.evidence_root.resolve()
    policy_file = checked_file(args.policy, "OpenROAD evidence policy")
    design_config = checked_file(args.design_config, "OpenROAD design configuration")
    constraint = checked_file(args.constraint, "OpenROAD constraint")
    policy = load_policy(policy_file)
    failures: list[str] = []
    artifacts: list[dict[str, Any]] = []
    metrics: list[dict[str, Any]] = []

    for declaration in policy["artifacts"]:
        path = policy_path(
            evidence_root,
            declaration,
            args.platform,
            args.design,
            args.variant,
        )
        try:
            record = relative_record(
                checked_file(path, f"required artifact {declaration['name']}"),
                module_root,
            )
            artifacts.append({"name": declaration["name"], **record})
        except EvidenceError as error:
            failures.append(str(error))

    source_records: dict[Path, dict[str, Any]] = {}
    for declaration in policy["metrics"]:
        path = policy_path(
            evidence_root,
            declaration,
            args.platform,
            args.design,
            args.variant,
        )
        value: int | None = None
        passed = False
        try:
            source = checked_file(path, f"metric source {declaration['name']}")
            text = source.read_text(encoding="utf-8", errors="replace")
            expression = re.compile(declaration["pattern"], re.MULTILINE)
            matches = list(expression.finditer(text))
            selection = declaration.get("match", "only")
            if not matches or (selection == "only" and len(matches) != 1):
                raise EvidenceError(
                    f"Metric {declaration['name']} expected "
                    f"{'one' if selection == 'only' else 'at least one'} match "
                    f"in {source}, "
                    f"found {len(matches)}"
                )
            selected_match = matches[-1] if selection == "last" else matches[0]
            raw_value = selected_match.group("value")
            if not re.fullmatch(r"[0-9]+", raw_value):
                raise EvidenceError(
                    f"Metric {declaration['name']} value is not a nonnegative integer: "
                    f"{raw_value!r}"
                )
            value = int(raw_value)
            passed = (
                ("minimum" not in declaration or value >= declaration["minimum"])
                and ("maximum" not in declaration or value <= declaration["maximum"])
            )
            if not passed:
                bounds = []
                if "minimum" in declaration:
                    bounds.append(f"minimum {declaration['minimum']}")
                if "maximum" in declaration:
                    bounds.append(f"maximum {declaration['maximum']}")
                failures.append(
                    f"Metric {declaration['name']} is {value}, expected "
                    f"{' and '.join(bounds)}"
                )
            source_records.setdefault(source, relative_record(source, module_root))
        except (EvidenceError, OSError) as error:
            failures.append(str(error))

        metric: dict[str, Any] = {
            "name": declaration["name"],
            "value": value,
            "passed": passed,
            "match": declaration.get("match", "only"),
            "source": source_records.get(path.resolve(), {"path": str(path.resolve())}),
        }
        for threshold in ("minimum", "maximum"):
            if threshold in declaration:
                metric[threshold] = declaration[threshold]
        metrics.append(metric)

    image: dict[str, str] | None = None
    if args.execution_mode == "container":
        if not IMAGE_REFERENCE.fullmatch(args.image_reference) or not IMAGE_DIGEST.fullmatch(
            args.image_digest
        ):
            failures.append(
                "Container evidence requires an immutable image reference and digest"
            )
        elif not args.image_reference.endswith(f"@{args.image_digest}"):
            failures.append(
                "Container image reference digest does not match the recorded digest"
            )
        image = {
            "reference": args.image_reference,
            "digest": args.image_digest,
            "id": args.image_id,
        }

    return {
        "schema": RESULT_SCHEMA,
        "status": "PASS" if not failures else "FAIL",
        "design": {
            "name": args.design,
            "platform": args.platform,
            "variant": args.variant,
        },
        "execution": {
            "mode": args.execution_mode,
            "runtime": args.runtime,
            "runtime_version": args.runtime_version,
            "orfs_revision": args.orfs_revision,
            "image": image,
        },
        "inputs": {
            "policy": relative_record(policy_file, module_root),
            "design_config": relative_record(design_config, module_root),
            "constraint": relative_record(constraint, module_root),
        },
        "artifacts": artifacts,
        "metrics": metrics,
        "failures": failures,
    }


def parser() -> argparse.ArgumentParser:
    """Construct the command-line parser."""
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--module-root", type=Path, required=True)
    result.add_argument("--policy", type=Path, required=True)
    result.add_argument("--evidence-root", type=Path, required=True)
    result.add_argument("--design-config", type=Path, required=True)
    result.add_argument("--constraint", type=Path, required=True)
    result.add_argument("--output", type=Path, required=True)
    result.add_argument(
        "--execution-mode", choices=("local", "container"), required=True
    )
    result.add_argument("--design", required=True)
    result.add_argument("--platform", required=True)
    result.add_argument("--variant", required=True)
    result.add_argument("--runtime", default="")
    result.add_argument("--runtime-version", default="")
    result.add_argument("--orfs-revision", default="")
    result.add_argument("--image-reference", default="")
    result.add_argument("--image-digest", default="")
    result.add_argument("--image-id", default="")
    return result


def main() -> int:
    """Run qualification and always retain a result for policy failures."""
    args = parser().parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    try:
        evidence = qualify(args)
    except EvidenceError as error:
        print(f"OpenROAD evidence error: {error}", file=sys.stderr)
        return 2
    args.output.write_text(
        json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    if evidence["status"] != "PASS":
        for failure in evidence["failures"]:
            print(f"OpenROAD evidence failure: {failure}", file=sys.stderr)
        return 1
    print(f"OpenROAD physical evidence passed: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
