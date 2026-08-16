# Architecture

## Purpose

`mosaic-flow` is the independently versioned methodology used by MOSAIC
repositories. It provides repeatable commands, pinned open-source tool versions,
adapters for open-source and licensed tools, explicit dependencies, and
machine-readable quality results.

The methodology is separate from any one hardware block so a flow correction or
tool upgrade can be qualified once, released, and adopted by updating a module's
pinned repository revision. Module repositories remain independently releasable
and retain ownership of all design intent.

## Ownership boundary

`mosaic-flow` owns methodology:

- Public Make targets and aggregate quality gates
- Canonical flow IDs, default states, and default artifact dependencies
- Tool invocation wrappers and shared Tcl adapters
- Status, report, and work-directory conventions
- Pinned open-source tool versions and installation scripts
- CI tests for methodology quality and a design-independent fixture
- The adapter between a module configuration and OpenROAD Flow Scripts

Each consuming module repository owns design intent:

- Synthesizable RTL and public packages
- Testbench sources, assertions, formal harnesses, and reference models
- Ordered RTL and verification file lists
- Top-level names and module-specific paths
- Timing, CDC, DFT, and low-power constraints
- Formal, equivalence, and physical implementation configuration
- Lint and style waivers with review records
- Generated reports and release evidence for that module revision

This boundary prevents a shared methodology release from silently changing RTL,
constraints, or approved exceptions in every consumer.

## Repository hierarchy

```text
mosaic-flow/
|-- .github/workflows/       CI that qualifies this methodology repository
|-- ci/                      Orchestration, validation, installers, and gates
|-- config/
|   |-- flows.mk             Canonical flow registry and shared defaults
|   |-- tool-versions.env    Pinned downloadable tool versions and checksums
|   `-- tools.mk             Executable names, cache roots, and PATH setup
|-- docs/                    User and maintainer documentation
|-- flows/
|   |-- common/              Environment validation and status helper
|   |-- <tool-or-stage>/     Shared shell and Tcl adapters
|   `-- ...
|-- mk/module.mk             Make API imported by module repositories
|-- tests/
|   |-- fixture-module/      Minimal independent consumer used by CI
|   `-- test_quality_gate.sh Configuration and quality-gate unit tests
|-- README.md                Repository overview
`-- VERSION                  Methodology semantic version
```

A typical consumer mirrors flow names for module-owned inputs:

```text
my-module/
|-- rtl/                     Synthesizable design
|-- verif/                   Testbench, assertions, and formal harness
|-- filelists/               Ordered source lists
|-- config/
|   |-- design.mk            Module identity and input paths
|   `-- flows.mk             Enabled flows and dependency overrides
|-- flows/
|   |-- cdc/                 CDC intent
|   |-- eqy/                 Equivalence configuration
|   |-- openroad/            PDK-backed implementation configuration
|   |-- sg_dft/              DFT intent
|   |-- symbiyosys/          Formal configuration
|   |-- synthesis/           Timing constraints
|   |-- vc_lp/               UPF power intent
|   |-- verible/             Style policy and waivers
|   `-- verilator_lint/      Verilator waivers
|-- mosaic-flow/             Pinned Git submodule
|-- reports/                 Reviewable generated results
|-- work/                    Disposable tool databases and netlists
`-- Makefile                 Thin importer of the shared methodology
```

The mirrored `flows/<name>/` layout makes ownership visible. The shared
directory says how a tool is invoked. The module directory says what that tool
must know about this design.

## Import model

The module Makefile is intentionally small:

```make
SHELL := /usr/bin/env bash

export MODULE_ROOT := $(CURDIR)
export FLOW_ROOT ?= $(abspath $(MODULE_ROOT)/mosaic-flow)

include config/design.mk
include $(FLOW_ROOT)/config/tools.mk
include $(FLOW_ROOT)/mk/module.mk
```

`mosaic-flow` should normally be a Git submodule. The module's gitlink pins the
exact methodology revision. This follows a component model where the consumer
selects a qualified methodology revision rather than copying scripts and then
allowing them to diverge.

`FLOW_ROOT` can point to a development checkout for temporary qualification:

```sh
make FLOW_ROOT=/path/to/mosaic-flow open-source
```

The module's recorded submodule revision remains the release authority.

## Execution lifecycle

Every flow target follows the same control path:

1. GNU Make loads shared defaults and then the module's overrides.
2. `flow-config-check` validates states and the complete dependency graph.
3. Make runs declared prerequisite targets first, including under `make -j`.
4. `ci/run_flow.sh` checks whether the selected flow is disabled.
5. The runner checks that every declared dependency recorded `PASS`.
6. The tool adapter validates common environment variables and invokes the tool.
7. The adapter writes logs and a final status below `reports/<flow-id>/`.
8. An aggregate gate verifies that every required flow has the exact expected
   status for the resolved project policy.

Make prerequisites prevent normal out-of-order execution. The report check is a
second boundary that protects direct script invocation, stale build graphs, and
partially completed runs.

## Configuration layers

Configuration is intentionally split by responsibility:

1. `mosaic-flow/config/flows.mk` defines shared flow defaults.
2. Module `config/design.mk` defines identity, paths, and technology inputs.
3. Module `config/flows.mk` selects flows and may replace dependencies.
4. `mosaic-flow/config/tools.mk` supplies executable defaults and tool paths.
5. Environment or Make command-line assignments provide site and one-run
   overrides.

Shared flow settings use `?=` so consumers can replace them without editing the
submodule. Module settings normally use `:=` so project policy is explicit.
Command-line Make assignments have the highest practical precedence for a
diagnostic run.

See [Configuration](configuration.md) for the complete contract.

## Open-source and commercial boundary

The portable gate runs on GitHub-hosted Linux runners and contains only
open-source tools. Pinned binaries are installed into a user cache and are also
used by module container images.

Synopsys flows run only in a licensed local or self-hosted environment. The
repository provides common entry points and report contracts, but it does not
ship licenses, technology libraries, or site setup. Some release-specific static
analysis Tcl adapters are deliberate fail-fast placeholders until they are
implemented and qualified against the installed Synopsys release. See the
[commercial flow catalog](flows.md#commercial-flows) before attempting signoff.

## Design principles

- **One command surface:** module owners use the same Make API in CI and locally.
- **Explicit policy:** every known flow is `enabled` or `disabled`.
- **Evidence over inference:** disabled and blocked checks record a status and a
  reason.
- **Fail closed:** missing results, unknown dependencies, cycles, and unwaived
  violations fail the relevant gate.
- **Reproducible portable tools:** downloadable releases and checksums are pinned.
- **Local ownership of intent:** constraints and waivers travel with the RTL they
  govern.
- **Independent qualification:** this repository tests itself with a fixture
  before module repositories update their pinned revision.
