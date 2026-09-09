#!/usr/bin/env python3
"""Validate and query a MOSAIC multi-module project manifest."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


SCHEMA = "mosaic-modules-v1"
MODULE_NAME = re.compile(r"^[a-z][a-z0-9_]*$")


class ManifestError(ValueError):
    """Report a user-correctable manifest or project-layout error."""


def load_manifest(path: Path, module_root: Path) -> dict[str, Any]:
    """Load and validate one manifest and its canonical module config files."""
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ManifestError(f"Module manifest does not exist: {path}") from error
    except json.JSONDecodeError as error:
        raise ManifestError(
            f"Invalid JSON in {path}:{error.lineno}:{error.colno}: {error.msg}"
        ) from error

    if not isinstance(manifest, dict):
        raise ManifestError("Module manifest root must be a JSON object")
    if manifest.get("schema") != SCHEMA:
        raise ManifestError(f"Module manifest schema must be {SCHEMA!r}")

    entries = manifest.get("include")
    if not isinstance(entries, list) or not entries:
        raise ManifestError("Module manifest 'include' must be a nonempty array")

    names: set[str] = set()
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise ManifestError(f"Module entry {index} must be a JSON object")
        name = entry.get("name")
        if not isinstance(name, str) or not MODULE_NAME.fullmatch(name):
            raise ManifestError(
                f"Module entry {index} has invalid name {name!r}; expected "
                "lowercase letters, digits, and underscores"
            )
        if name in names:
            raise ManifestError(f"Duplicate module name: {name}")
        names.add(name)

        design_config = module_root / "config" / "modules" / f"{name}.mk"
        flow_config = module_root / "config" / "modules" / f"{name}-flows.mk"
        if not design_config.is_file():
            raise ManifestError(
                f"Module {name} is missing design configuration: {design_config}"
            )
        if not flow_config.is_file():
            raise ManifestError(
                f"Module {name} is missing flow policy: {flow_config}"
            )

    return manifest


def parse_args() -> argparse.Namespace:
    """Parse the command used by Make and CI integrations."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate", "list", "matrix"))
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--module-root", required=True, type=Path)
    parser.add_argument("--selected", default="")
    parser.add_argument("--quiet", action="store_true")
    return parser.parse_args()


def main() -> int:
    """Validate the manifest and render the requested deterministic view."""
    arguments = parse_args()
    manifest_path = arguments.manifest.resolve()
    module_root = arguments.module_root.resolve()

    try:
        manifest = load_manifest(manifest_path, module_root)
        entries = manifest["include"]
        names = [entry["name"] for entry in entries]
        if arguments.selected and arguments.selected not in names:
            raise ManifestError(
                f"Unknown MODULE {arguments.selected!r}; registered modules: "
                f"{', '.join(names)}"
            )
    except ManifestError as error:
        print(f"module manifest error: {error}", file=sys.stderr)
        return 2

    if arguments.command == "list":
        print("\n".join(names))
    elif arguments.command == "matrix":
        print(json.dumps({"include": entries}, separators=(",", ":"), sort_keys=True))
    elif not arguments.quiet:
        print(f"Validated {len(names)} modules from {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
