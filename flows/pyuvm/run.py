#!/usr/bin/env python3
"""Run one module-owned PyUVM test through a cocotb simulator adapter."""

from __future__ import annotations

import os
import platform
import shlex
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from cocotb_tools.runner import get_runner
from importlib.metadata import version


def split_env(name: str) -> list[str]:
    """Parse one optional shell-style argument variable without invoking a shell."""
    return shlex.split(os.environ.get(name, ""))


def parse_filelist(
    path: Path, module_root: Path
) -> tuple[list[Path], list[Path], dict[str, str]]:
    """Expand a portable HDL filelist into sources, include paths, and defines.

    Relative entries, including entries in nested filelists, are interpreted
    from MODULE_ROOT to match the contract used by the other flow adapters.
    """
    sources: list[Path] = []
    includes: list[Path] = []
    defines: dict[str, str] = {}

    tokens = shlex.split(path.read_text(encoding="utf-8"), comments=True)
    token_index = 0
    while token_index < len(tokens):
        token = tokens[token_index]
        if token in {"-f", "-F"}:
            token_index += 1
            nested = Path(tokens[token_index])
            nested = nested if nested.is_absolute() else module_root / nested
            nested_sources, nested_includes, nested_defines = parse_filelist(nested, module_root)
            sources.extend(nested_sources)
            includes.extend(nested_includes)
            defines.update(nested_defines)
        elif token.startswith("+incdir+"):
            for include in token.removeprefix("+incdir+").split("+"):
                include_path = Path(include)
                includes.append(include_path if include_path.is_absolute() else module_root / include_path)
        elif token.startswith("+define+"):
            definition = token.removeprefix("+define+")
            name, separator, value = definition.partition("=")
            defines[name] = value if separator else "1"
        elif token.startswith(("+", "-")):
            raise ValueError(f"Unsupported filelist token: {token}")
        else:
            source = Path(token)
            sources.append(source if source.is_absolute() else module_root / source)
        token_index += 1

    return sources, includes, defines


def simulator_arguments(
    simulator: str, coverage: bool, work_dir: Path
) -> tuple[list[str], list[str]]:
    """Return compile-time and run-time options for a cocotb simulator backend."""
    build_args = split_env("PYUVM_COMPILE_ARGS")
    test_args = split_env("PYUVM_RUN_ARGS")

    if simulator == "verilator":
        build_args = [
            "--timing",
            "--assert",
            "-Wall",
            "-Wno-BLKSEQ",
            "-Wno-SYNCASYNCNET",
        ] + build_args
        if coverage:
            build_args.append("--coverage")
    elif simulator == "icarus":
        build_args = ["-g2012"] + build_args
    elif simulator == "vcs":
        build_args = ["-full64", "-sverilog", "-assert", "svaext"] + build_args
        if coverage:
            coverage_dir = work_dir / "coverage.vdb"
            build_args.extend(
                ["-cm", "line+cond+tgl+assert", "-cm_dir", str(coverage_dir)]
            )
            test_args.extend(
                ["-cm", "line+cond+tgl+assert", "-cm_dir", str(coverage_dir)]
            )
    elif simulator == "xcelium":
        build_args = ["-sv"] + build_args
        if coverage:
            coverage_dir = work_dir / "cov_work"
            build_args.extend(
                ["-coverage", "all", "-covoverwrite", "-covworkdir", str(coverage_dir)]
            )
            test_args.extend(["-coverage", "all", "-covworkdir", str(coverage_dir)])

    return build_args, test_args


def export_verilator_coverage(work_dir: Path, report_dir: Path) -> None:
    """Copy Verilator's native database and export an LCOV-compatible report."""
    coverage_files = list(work_dir.rglob("coverage.dat"))
    if not coverage_files:
        raise RuntimeError("Verilator did not produce coverage.dat")
    coverage_data = coverage_files[0]
    shutil.copy2(coverage_data, report_dir / "coverage.dat")
    subprocess.run(
        [
            os.environ.get("VERILATOR_COVERAGE_CMD", "verilator_coverage"),
            "--write-info",
            str(report_dir / "coverage.info"),
            str(coverage_data),
        ],
        check=True,
    )


def validate_results(results_xml: Path) -> None:
    """Require at least one executed test and no JUnit failures or errors."""
    if not results_xml.is_file():
        raise RuntimeError("cocotb did not produce the required results.xml")
    root = ET.parse(results_xml).getroot()
    suites = [root] if root.tag == "testsuite" else list(root.iter("testsuite"))
    tests = sum(int(suite.get("tests", "0")) for suite in suites)
    failures = sum(int(suite.get("failures", "0")) for suite in suites)
    errors = sum(int(suite.get("errors", "0")) for suite in suites)
    if tests < 1 or failures or errors:
        raise RuntimeError(
            f"PyUVM results are not clean: tests={tests}, failures={failures}, errors={errors}"
        )


def record_versions(simulator: str, report_dir: Path) -> None:
    """Record the exact Python, verification, and simulator tool versions."""
    simulator_commands = {
        "verilator": ["verilator", "--version"],
        "icarus": ["iverilog", "-V"],
        "vcs": ["vcs", "-ID"],
        "xcelium": ["xrun", "-version"],
    }
    command = simulator_commands[simulator]
    executable = shutil.which(command[0])
    if executable is None:
        raise FileNotFoundError(f"Simulator executable is not in PATH: {command[0]}")
    completed = subprocess.run(
        [executable, *command[1:]], capture_output=True, text=True, check=False
    )
    simulator_version = (completed.stdout or completed.stderr).strip()
    contents = [
        f"python={platform.python_version()}",
        f"pyuvm={version('pyuvm')}",
        f"cocotb={version('cocotb')}",
        f"simulator={simulator}",
        f"simulator_executable={executable}",
        "simulator_version<<EOF",
        simulator_version,
        "EOF",
    ]
    (report_dir / "versions.log").write_text("\n".join(contents) + "\n", encoding="utf-8")


def main() -> None:
    """Compile the shared HDL verification layers and run the selected PyUVM test."""
    module_root = Path(os.environ["MODULE_ROOT"]).resolve()
    report_dir = Path(os.environ["PYUVM_REPORT_DIR"]).resolve()
    work_dir = Path(os.environ["PYUVM_WORK_DIR"]).resolve()
    simulator = os.environ["PYUVM_SIMULATOR"]
    coverage = os.environ.get("PYUVM_COVERAGE", "enabled") == "enabled"
    record_versions(simulator, report_dir)

    # Ordering is part of the public contract: design sources first, reusable
    # temporal definitions next, then assertion and coverage wrappers.
    filelists = [Path(os.environ["PYUVM_FILELIST"])]
    property_filelist = os.environ.get("PROPERTY_FILELIST", "")
    if property_filelist:
        filelists.append(Path(property_filelist))
    assertion_filelist = os.environ.get("ASSERTION_FILELIST", "")
    if assertion_filelist:
        filelists.append(Path(assertion_filelist))
    coverage_filelist = os.environ.get("COVERAGE_FILELIST", "")
    if coverage_filelist:
        filelists.append(Path(coverage_filelist))

    sources: list[Path] = []
    includes: list[Path] = []
    defines: dict[str, str] = {}
    for filelist in filelists:
        filelist = filelist if filelist.is_absolute() else module_root / filelist
        parsed_sources, parsed_includes, parsed_defines = parse_filelist(
            filelist, module_root
        )
        sources.extend(parsed_sources)
        includes.extend(parsed_includes)
        defines.update(parsed_defines)

    missing_sources = [str(source) for source in sources if not source.is_file()]
    if missing_sources:
        raise FileNotFoundError(f"Missing PyUVM HDL sources: {', '.join(missing_sources)}")

    build_args, test_args = simulator_arguments(simulator, coverage, work_dir)
    test_path = Path(os.environ.get("PYUVM_TEST_PATH", module_root / "verif" / "pyuvm"))
    python_path = [str(test_path.resolve())]
    if os.environ.get("PYTHONPATH"):
        python_path.append(os.environ["PYTHONPATH"])
    os.environ["PYTHONPATH"] = os.pathsep.join(python_path)
    for path_entry in reversed(python_path):
        if path_entry not in sys.path:
            sys.path.insert(0, path_entry)

    # PyUVM never imports SVA. The simulator compiles these collected HDL
    # sources, and bind wrappers evaluate alongside Python-driven stimulus.
    runner = get_runner(simulator)
    runner.build(
        sources=sources,
        includes=includes,
        defines=defines,
        build_args=build_args,
        hdl_toplevel=os.environ["PYUVM_TOP"],
        always=True,
        build_dir=work_dir,
        cwd=module_root,
        waves=os.environ.get("PYUVM_WAVES", "disabled") == "enabled",
        log_file=report_dir / "compile.log",
    )
    runner.test(
        test_module=os.environ["PYUVM_TEST_MODULE"],
        testcase=os.environ.get("PYUVM_TESTCASE") or None,
        hdl_toplevel=os.environ["PYUVM_TOP"],
        hdl_toplevel_lang="verilog",
        test_args=test_args,
        plusargs=split_env("PYUVM_PLUSARGS"),
        extra_env={"PYTHONPATH": os.environ["PYTHONPATH"]},
        build_dir=work_dir,
        test_dir=work_dir,
        results_xml=str(report_dir / "results.xml"),
        waves=os.environ.get("PYUVM_WAVES", "disabled") == "enabled",
        log_file=report_dir / "simulation.log",
    )

    validate_results(report_dir / "results.xml")

    if coverage and simulator == "verilator":
        export_verilator_coverage(work_dir, report_dir)


if __name__ == "__main__":
    main()
