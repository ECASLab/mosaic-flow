# Getting started

## Prerequisites

For the portable open-source flow, use:

- Linux x86-64 for automatic binary installation
- GNU Make
- GNU `xargs` from findutils for multi-module parallel execution
- Bash
- Git
- Python 3
- `curl`, `tar`, and `sha256sum`
- Network access during the first tool installation

On another host architecture, use the module repository's `linux/amd64` Docker
flow. OpenROAD and all Synopsys tools have separate requirements described in
the [flow catalog](flows.md).

## Add the methodology to a module

From the root of a module repository, add the independently versioned flow as a
Git submodule:

```sh
git submodule add <mosaic-flow-repository-url> mosaic-flow
git submodule update --init --recursive
```

Use a release tag or qualified commit in the submodule. Do not copy the shared
scripts into the module repository. The gitlink is the module's methodology
version.

The separate `mosaic-module-template` repository is a complete consumer example.
The `tests/fixture-module/` directory in this repository is a smaller example
intended for methodology testing.

## Create the consumer Makefile

The root Makefile should only establish the module root and import the shared
API:

```make
SHELL := /usr/bin/env bash

export MODULE_ROOT := $(CURDIR)
export FLOW_ROOT ?= $(abspath $(MODULE_ROOT)/mosaic-flow)

include config/design.mk
include $(FLOW_ROOT)/config/tools.mk
include $(FLOW_ROOT)/mk/module.mk
```

Keeping this file thin lets a methodology update change orchestration and tool
versions by moving one Git pointer.

Repositories with multiple independently selectable RTL modules should import
`mk/project.mk` instead. See [Multi-module projects](multi-module-projects.md)
for the manifest, module profile, concurrent execution, and CI contracts.

## Define the module contract

Create `config/design.mk` with at least these values:

```make
export DESIGN_TOP := my_module
export TB_TOP := $(DESIGN_TOP)_tb
export FORMAL_TOP := $(DESIGN_TOP)_formal
export DUT_INSTANCE := $(TB_TOP)/dut

export FLOW_CONFIG_ROOT := $(MODULE_ROOT)/flows
export RTL_FILELIST := $(MODULE_ROOT)/filelists/rtl.f
export TB_FILELIST := $(MODULE_ROOT)/filelists/tb.f
export PROPERTY_FILELIST := $(MODULE_ROOT)/filelists/properties.f
export ASSERTION_FILELIST := $(MODULE_ROOT)/filelists/assertions.f
export COVERAGE_FILELIST := $(MODULE_ROOT)/filelists/coverage.f
export PYUVM_TEST_MODULE := test_my_module
export VERILATOR_WAIVER_FILE := $(FLOW_CONFIG_ROOT)/verilator_lint/waivers.vlt
export VERIBLE_WAIVER_FILE := $(FLOW_CONFIG_ROOT)/verible/waivers.txt
export VERIBLE_RULES_FILE := $(FLOW_CONFIG_ROOT)/verible/rules
export FORMAL_CONFIG := $(FLOW_CONFIG_ROOT)/symbiyosys/formal.sby
export FORMAL_COVER_CONFIG := $(FLOW_CONFIG_ROOT)/symbiyosys/formal_cover.sby
export EQUIVALENCE_CONFIG := $(FLOW_CONFIG_ROOT)/eqy/equivalence.eqy
export OPENROAD_CONFIG := $(FLOW_CONFIG_ROOT)/openroad/config.mk
export SYNTHESIS_CONSTRAINT_FILE := $(FLOW_CONFIG_ROOT)/synthesis/timing.sdc
export CDC_CONFIG := $(FLOW_CONFIG_ROOT)/cdc/constraints.tcl
export DFT_CONFIG := $(FLOW_CONFIG_ROOT)/sg_dft/constraints.tcl
export UPF_CONFIG := $(FLOW_CONFIG_ROOT)/vc_lp/power.upf
export CONSTRAINT_DIR := $(FLOW_CONFIG_ROOT)/synthesis

export REPORT_DIR := $(MODULE_ROOT)/reports
export WORK_DIR := $(MODULE_ROOT)/work
export ACTIVITY_FILE ?= $(WORK_DIR)/vcs_sim/$(DESIGN_TOP).saif
```

All paths in file lists should be valid when commands run from `MODULE_ROOT`.
The current Verible and Yosys adapters accept blank lines, comments, source
paths, and `+incdir+<path>`. Tool-specific switches in a shared RTL file list may
not be portable.

See [Configuration](configuration.md#design-and-path-variables) for optional
technology variables and the exact meaning of each setting.

## Qualify parameterized elaborations

Add `config/parameter-profiles.json` when materially different parameter values
need independently attributable evidence. Declare boundary values, nominal
settings, feature toggles, and the flows required for each profile. Then run:

```sh
make profile-manifest-check
make profile-list
make clean all-profiles PROFILE_JOBS=4
```

Once a manifest exists, select `PROFILE=<name>` for individual flow targets.
The methodology applies the exact parameter set and writes isolated work and
reports below that profile name. The complete schema, evidence policy, and CI
examples are in [Parameter-profile qualification](parameter-profiles.md).

## Understand PyUVM, SVA, and coverage

PyUVM does not import or call SystemVerilog assertions from Python. PyUVM
provides stimulus, sequencing, and Python-side checking. Cocotb connects that
Python environment to an HDL simulator, and the simulator compiles and executes
the DUT, assertions, and SystemVerilog coverage together.

```text
PyUVM test
    |
    | drives and observes signals through cocotb
    v
HDL simulator
    |-- DUT from PYUVM_FILELIST
    |-- sequences and properties from PROPERTY_FILELIST
    |-- assertion wrappers from ASSERTION_FILELIST
    `-- coverage wrappers from COVERAGE_FILELIST
```

The relationship is established during compilation:

1. The PyUVM adapter reads `PYUVM_FILELIST`, `PROPERTY_FILELIST`,
   `ASSERTION_FILELIST`, and `COVERAGE_FILELIST` in that order.
2. It passes the resulting sources, include directories, and definitions to the
   cocotb simulator runner.
3. Assertion and coverage bind files attach their wrapper modules to the DUT.
4. The Python test drives the DUT while the simulator evaluates the bound SVA
   and cover properties concurrently.
5. A terminating SVA failure causes the simulator and PyUVM flow to fail. The
   flow records `FAIL` even if the Python stimulus itself completed correctly.

A module should keep each verification concern in its own source area:

```text
verif/
|-- properties/             Shared sequences and properties
|-- assertions/             assert property directives and bind wrapper
|-- coverage/               cover property directives and bind wrapper
|-- formal/                 Formal harness
`-- pyuvm/                  Python tests, agents, monitors, and scoreboards

filelists/
|-- properties.f
|-- assertions.f
|-- coverage.f
`-- rtl.f
```

There are two complementary kinds of coverage:

| Coverage | Owner | Result |
| --- | --- | --- |
| SystemVerilog assertion, cover, line, branch, and toggle coverage | HDL simulator | Native simulator database and exported reports |
| Functional coverage sampled by the verification environment | PyUVM test | `functional-coverage.json` |

`PYUVM_COVERAGE=enabled` enables native simulator coverage collection. It does
not replace Python functional coverage, and Python functional coverage does not
prove that the bound SVA or HDL cover properties were exercised. Review both
forms of evidence for release.

Normal SystemVerilog simulation, PyUVM, and formal verification consume the
same module-owned property, assertion, and coverage sources. Yosys may select a
procedural equivalent from the same wrapper when it cannot parse a concurrent
SVA construct. See [Configuration](configuration.md#design-and-path-variables)
for the wrapper and `MOSAIC_YOSYS_FORMAL` conventions.

## Select project flows

Create `config/flows.mk`. Begin with every portable gate enabled. Disable a flow
only when it is genuinely outside the module's supported policy:

```make
FLOW_verible_lint := enabled
FLOW_verible_format := enabled
FLOW_slang_elaboration := enabled
FLOW_verilator_lint := enabled
FLOW_yosys_synthesis := enabled
FLOW_symbiyosys_formal := enabled
FLOW_eqy_equivalence := enabled
FLOW_verilator_sim := enabled
FLOW_pyuvm_open_source := disabled
FLOW_openroad := disabled

FLOW_vcs_sim := enabled
FLOW_pyuvm_commercial := disabled
FLOW_vc_lint := enabled
FLOW_vc_cdc := enabled
FLOW_sg_cdc := disabled
FLOW_sg_dft := enabled
FLOW_vc_lp := enabled
FLOW_synopsys_synthesis := enabled
FLOW_synopsys_primetime := enabled
FLOW_synopsys_primepower := enabled
```

Keep default dependencies unless the module produces or consumes different
artifacts:

```make
FLOW_DEPENDENCIES_eqy_equivalence := yosys_synthesis
FLOW_DEPENDENCIES_synopsys_primetime := synopsys_synthesis
FLOW_DEPENDENCIES_synopsys_primepower := vcs_sim synopsys_synthesis
```

Check the resolved policy before running tools:

```sh
make flow-config-check
```

## Run the first portable checks

List the available targets and prepare the pinned tool cache:

```sh
make help
make setup-open-source
```

Run quick frontend checks while bringing up a new module:

```sh
make open-style-lint
make open-format-check
make open-elaborate
make open-lint
```

Then run the complete portable acceptance gate:

```sh
make clean open-source
```

The first portable target downloads missing pinned tools to
`${XDG_CACHE_HOME:-$HOME/.cache}/mosaic`. Set `MOSAIC_TOOLS_ROOT` to share a
different cache location:

```sh
make MOSAIC_TOOLS_ROOT=/tools/mosaic setup-open-source
```

Automatic installation currently supports Linux x86-64. It verifies the pinned
archives before use.

## Inspect results

Every flow has a canonical ID and writes to:

```text
reports/<flow-id>/
work/<flow-id>/
```

Start with `reports/<flow-id>/status.txt`, then inspect the flow log. `PASS` and
`SKIP` can be acceptable depending on project policy. `FAIL`, `BLOCKED`, and a
missing result are not accepted by an aggregate quality gate.

See [Results and quality gates](results-and-quality-gates.md) for the exact
status contract.

## Prepare licensed local flows

Before running a Synopsys target:

1. Load the site's license and executable environment.
2. Point `TECH_SETUP_TCL` at an untracked technology setup script if needed.
3. Set target and link libraries or define them in the technology setup.
4. Complete and qualify any release-specific adapter that still fails with an
   explicit `not configured` error.
5. Ensure the testbench writes SAIF activity at `ACTIVITY_FILE` for PrimePower.
6. Check executable discovery with `make synopsys-check-env`.

Then run a selected stage or the complete local gate:

```sh
make synopsys-sim
make synopsys-synth
make synopsys-sta
make synopsys-power
make synopsys-all CDC_TOOL=vc
```

No commercial tool is run by this repository's GitHub-hosted workflow.

## Common first-run failures

**A portable executable is missing**

Run `make setup-open-source`. If an incomplete cache directory is reported,
remove only the named incomplete version directory and rerun setup.

**Automatic setup rejects the platform**

Use the module's Docker workflow on non-Linux or non-x86-64 hosts.

**Flow configuration is invalid**

Run `make flow-config-check`. Resolve unknown IDs, invalid states, cycles, or an
enabled flow whose dependency is disabled.

**A flow is `BLOCKED`**

Read `reports/<flow-id>/block_reason.txt`. Run and pass the named dependency,
then rerun the target.

**A disabled target does not satisfy the gate after `FORCE_FLOW=1`**

This is intentional. A forced diagnostic execution does not change project
policy. Rerun the target without `FORCE_FLOW` to record the expected `SKIP`, or
enable it in `config/flows.mk`.

**A Synopsys adapter immediately reports that it is not configured**

Some static adapters are release-specific placeholders. Follow the qualification
process in [Methodology development](development.md#qualifying-commercial-adapters).
