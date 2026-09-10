# Configuration reference

## Configuration files

| File | Owner | Purpose |
| --- | --- | --- |
| `mosaic-flow/config/flows.mk` | Methodology | Canonical IDs, default states, default dependencies |
| `mosaic-flow/config/tool-versions.env` | Methodology | Pinned downloadable versions and checksums |
| `mosaic-flow/config/tools.mk` | Methodology | Tool cache, `PATH`, and executable defaults |
| Module `config/design.mk` | Module | Top names, paths, constraints, technology inputs |
| Module `config/flows.mk` | Module | Enabled and disabled flows, dependency overrides |
| Module `flows/<name>/...` | Module | Tool-specific design intent and waivers |

Multi-module repositories replace the two module configuration rows with
`config/modules.json`, `config/modules/<module>.mk`, and
`config/modules/<module>-flows.mk`. The complete contract is documented in
[Multi-module projects](multi-module-projects.md).

A parameterized module may add `config/parameter-profiles.json`. Multi-module
repositories use `config/parameter-profiles/<module>.json`. See
[Parameter-profile qualification](parameter-profiles.md) for the schema and
execution contract.

## Precedence and override rules

Shared flow defaults use `?=`. The module's `config/flows.mk` is included after
the shared file and normally uses `:=`, so module policy replaces the default.

For a one-run diagnostic, a Make command-line assignment overrides an ordinary
Makefile assignment:

```sh
make FLOW_symbiyosys_formal=disabled open-source
make FLOW_DEPENDENCIES_eqy_equivalence="yosys_synthesis" open-equivalence
```

Tool executable defaults also use `?=` and can be supplied through the
environment or command line:

```sh
VERILATOR_CMD=/opt/verilator/bin/verilator make open-lint
make YOSYS_CMD=/opt/yosys/bin/yosys open-synth
```

Technology credentials and site paths should come from the local environment or
an untracked environment setup script. They must not be committed. No site file
is implicitly sourced by the Make API.

The compatibility variable `DISABLED_FLOWS` is folded into the resolved
disabled list by `mk/module.mk`. Prefer explicit `FLOW_<id>` settings in the
module for durable policy.

## Flow states

Every canonical flow has exactly one state:

```make
FLOW_<canonical-id> := enabled
FLOW_<canonical-id> := disabled
```

Only lowercase `enabled` and `disabled` are valid. A disabled flow records
`SKIP` when its target is invoked. It is not silently omitted.

Examples:

```make
FLOW_openroad := disabled
FLOW_symbiyosys_formal := enabled
FLOW_sg_cdc := disabled
FLOW_vc_cdc := enabled
```

Canonical IDs are listed in the [flow catalog](flows.md).

`DISABLED_FLOWS` remains available for diagnostics and compatibility:

```sh
make DISABLED_FLOWS="symbiyosys_formal eqy_equivalence" open-source
```

The special `cdc` alias disables whichever CDC engine is selected:

```sh
make DISABLED_FLOWS=cdc CDC_TOOL=vc synopsys-quality-gate
```

Do not use the alias inside a dependency list. Dependencies always use canonical
IDs.

## Dependencies

Dependencies are whitespace-separated canonical flow IDs:

```make
FLOW_DEPENDENCIES_eqy_equivalence := yosys_synthesis
FLOW_DEPENDENCIES_synopsys_primetime := synopsys_synthesis
FLOW_DEPENDENCIES_synopsys_primepower := vcs_sim synopsys_synthesis
```

An assignment replaces the complete shared list. It does not append to it.

The default dependencies represent direct artifact consumption:

| Flow | Default dependencies | Reason |
| --- | --- | --- |
| `eqy_equivalence` | `yosys_synthesis` | EQY reads the Yosys netlist |
| `synopsys_primetime` | `synopsys_synthesis` | PrimeTime reads the synthesis DDC and SDC |
| `synopsys_primepower` | `vcs_sim synopsys_synthesis` | PrimePower reads SAIF activity plus synthesis DDC and SDC |

All other default lists are empty. A project may add policy dependencies even
when no file is directly consumed. For example:

```make
FLOW_DEPENDENCIES_openroad := yosys_synthesis verilator_sim
```

The configuration validator rejects:

- Unknown dependency IDs
- A flow that depends on itself
- Dependency cycles
- An enabled flow that depends on a disabled flow
- Unknown names in `DISABLED_FLOWS`
- Missing or invalid flow states

Make encodes valid dependencies as prerequisites. `ci/run_flow.sh` also requires
each dependency's `status.txt` to contain `PASS` before launching a dependent
tool.

## Diagnostic force mode

Run a disabled target without changing project policy:

```sh
make open-formal FORCE_FLOW=1
```

This is only a debugging aid. The aggregate gate still expects `SKIP` because
the flow remains disabled in the resolved configuration. `FORCE_FLOW` does not
force a dependent flow past a missing or failed dependency.

## CDC engine selection

`CDC_TOOL` selects the implementation behind `make synopsys-cdc`:

```sh
make synopsys-cdc CDC_TOOL=vc
make synopsys-cdc CDC_TOOL=sg
```

Valid values are `vc` and `sg`. The selected canonical result is `vc_cdc` or
`sg_cdc`. Enable the selected engine in project policy and disable the other
unless both are intentionally run as separate checks.

## Design and path variables

The shared environment adapter requires these variables for every tool adapter:

| Variable | Meaning |
| --- | --- |
| `MODULE_ROOT` | Absolute root of the consuming module |
| `FLOW_ROOT` | Root of the selected `mosaic-flow` checkout |
| `DESIGN_TOP` | Synthesizable top-level module |
| `TB_TOP` | Simulation top-level module |
| `FORMAL_TOP` | Formal harness top-level module |
| `DUT_INSTANCE` | Hierarchical DUT instance used for activity annotation |
| `RTL_FILELIST` | Ordered synthesizable source file list |
| `TB_FILELIST` | Ordered simulation source file list |
| `PROPERTY_FILELIST` | Shared SystemVerilog property and sequence dependencies |
| `ASSERTION_FILELIST` | Shared SystemVerilog assertion and bind file list |
| `COVERAGE_FILELIST` | Shared SystemVerilog coverage model and bind file list |
| `CONSTRAINT_DIR` | Directory containing synthesis `timing.sdc` |
| `REPORT_DIR` | Root for persistent, reviewable results |
| `WORK_DIR` | Root for disposable tool databases and generated netlists |
| `PARAMETER_PROFILE_MANIFEST` | Optional module-owned profile manifest path |
| `PROFILE` | Selected named profile for one invocation |
| `PROFILE_TARGET` | Target dispatched by `all-profiles`, default `open-source` |
| `PROFILE_JOBS` | Maximum concurrent profile jobs, default `JOBS` or `0` |

When `PROFILE` is selected, the flow exports `PROFILE_PARAMETERS_JSON`,
`PROFILE_APPLICABLE_FLOWS`, and `MOSAIC_PROFILE_ACTIVE` to adapters. These are
methodology implementation variables and should not be assigned by consumers.
The selected name is appended to `REPORT_DIR` and `WORK_DIR` after module
selection.

When `mk/project.mk` selects a manifest entry, `REPORT_DIR` and `WORK_DIR`
default to `reports/<module>` and `work/<module>`.

Flow-specific inputs are required when their flow is enabled:

| Variable | Consumer |
| --- | --- |
| `VERILATOR_WAIVER_FILE` | Verilator lint |
| `VERIBLE_WAIVER_FILE` | Verible lint |
| `VERIBLE_RULES_FILE` | Verible lint |
| `FORMAL_CONFIG` | SymbiYosys |
| `FORMAL_COVER_CONFIG` | SymbiYosys cover reachability task |
| `EQUIVALENCE_CONFIG` | EQY |
| `OPENROAD_CONFIG` | OpenROAD Flow Scripts |
| `SYNTHESIS_CONSTRAINT_FILE` | Module convention for synthesis SDC |
| `CDC_CONFIG` | VC CDC or SpyGlass CDC adapter |
| `DFT_CONFIG` | SpyGlass DFT adapter |
| `UPF_CONFIG` | VC LP adapter |
| `OPENROAD_PLATFORM` | Platform selected by the module's OpenROAD config |
| `ACTIVITY_FILE` | SAIF consumed by PrimePower |
| `PYUVM_TEST_MODULE` | Importable Python module containing the PyUVM tests |
| `PYUVM_FILELIST` | RTL file list compiled for the PyUVM top |
| `PYUVM_TOP` | HDL top visible to cocotb, defaulting to `DESIGN_TOP` |
| `PYUVM_TEST_PATH` | Directory prepended to the Python import path |
| `PYUVM_OPEN_SIMULATOR` | Open-source cocotb simulator, `verilator` by default |
| `PYUVM_COMMERCIAL_SIMULATOR` | Commercial simulator, `vcs` by default |
| `PYUVM_COVERAGE` | Enable simulator-native coverage with `enabled` or `disabled` |
| `PYUVM_WAVES` | Enable waveform generation with `enabled` or `disabled` |
| `PYUVM_TESTCASE` | Optional PyUVM test class filter |
| `PYUVM_COMPILE_ARGS` | Additional shell-parsed simulator compile arguments |
| `PYUVM_RUN_ARGS` | Additional shell-parsed simulator run arguments |
| `PYUVM_PLUSARGS` | Additional shell-parsed HDL plusargs |
| `SIM_COVERAGE` | Enable native coverage in normal simulation |

## Release evidence variables

The shared `release-manifest` target derives its standard input set from the
design, flow, filelist, constraint, waiver, formal, physical, and power-intent
variables above. These variables extend or qualify the release record:

| Variable | Default | Purpose |
| --- | --- | --- |
| `RELEASE_MODULE_NAME` | `MODULE` or `DESIGN_TOP` | Stable module identity |
| `MODULE_REVISION` | Empty | Explicit 40-digit module commit, required in CI |
| `METHODOLOGY_REVISION` | Empty | Explicit 40-digit `mosaic-flow` commit, required in CI |
| `RELEASE_EXECUTION_CONTEXT` | `native` | Context label and output namespace |
| `RELEASE_ALLOW_DIRTY` | `disabled` | Permit and record a dirty tree for local diagnostics |
| `RELEASE_MODULE_DIRTY` | Empty | Explicit packaged-module dirty-state attestation |
| `RELEASE_METHODOLOGY_DIRTY` | Empty | Explicit packaged-methodology dirty-state attestation |
| `RELEASE_TECHNOLOGY` | `technology-independent` | Technology context name |
| `RELEASE_TECHNOLOGY_METADATA_JSON` | `{}` | PDK, library, corner, or technology details |
| `RELEASE_METADATA_JSON` | `{}` | Deterministic module-owned annotations |
| `RELEASE_EXECUTION_METADATA_JSON` | `{}` | Volatile runner or container annotations |
| `RELEASE_SUPPLEMENTAL_GATES` | Empty | Required module-owned status IDs |
| `RELEASE_ADDITIONAL_INPUTS` | Empty | Extra required files or directories to hash |
| `RELEASE_ADDITIONAL_EVIDENCE` | Empty | Extra generated files to index and hash |
| `RELEASE_ADDITIONAL_TOOLS_JSON` | `[]` | Extra tool version commands and associated flows |
| `RELEASE_COVERAGE_EVIDENCE_JSON` | `[]` | Extra coverage kind, producer, and path records |
| `RELEASE_MANIFEST_DIR` | `REPORT_DIR/release_manifest/<context>` | Manifest output directory |

`RELEASE_INPUT_FILES` and `RELEASE_FILELISTS` are exported derived lists used
by the generator. Consumers should extend `RELEASE_ADDITIONAL_INPUTS` instead
of replacing these implementation variables. The JSON formats and release
policy are documented in [Release evidence](release-evidence.md).

PyUVM is opt-in. A module enables its portable and commercial policies
independently:

```make
FLOW_pyuvm_open_source := enabled
FLOW_pyuvm_commercial := disabled

export PYUVM_TEST_MODULE := test_my_module
export PROPERTY_FILELIST := $(MODULE_ROOT)/filelists/properties.f
export ASSERTION_FILELIST := $(MODULE_ROOT)/filelists/assertions.f
export COVERAGE_FILELIST := $(MODULE_ROOT)/filelists/coverage.f
export FORMAL_COVER_CONFIG := $(FLOW_CONFIG_ROOT)/symbiyosys/formal_cover.sby
```

When `pyuvm_open_source` is enabled, `make open-source` runs it and the
open-source quality gate requires `PASS`. A disabled PyUVM flow records `SKIP`.
VCS and Xcelium remain explicit local flows and are never required by the
GitHub-hosted methodology workflow.

Run the configured backends with:

```sh
make open-pyuvm
make PYUVM_COMMERCIAL_SIMULATOR=vcs commercial-pyuvm
make PYUVM_COMMERCIAL_SIMULATOR=xcelium commercial-pyuvm
```

The PyUVM filelist parser accepts source paths, `+incdir+`, `+define+`, and
nested `-f` or `-F` entries. Put simulator-specific options in
`PYUVM_COMPILE_ARGS` instead of a shared filelist.

`PROPERTY_FILELIST`, `ASSERTION_FILELIST`, and `COVERAGE_FILELIST` keep reusable
temporal definitions, checking directives, and coverage directives separate.
Normal SystemVerilog simulation and PyUVM compile the lists in that order. The
module's SymbiYosys proof and cover configurations must read the corresponding
sources in their `[script]` and `[files]` sections.

For broad simulator compatibility, keep module-specific sequences in one
`.svh` file and compose them into properties in a second `.svh` file. Include
the property file inside each assertion or coverage wrapper module. Packages may
be used only after every required simulator and formal frontend has qualified
that construct. Prefer named, interface-specific properties over generic
properties with untyped formal arguments, which are not implemented
consistently by current open-source SystemVerilog frontends.

The Yosys frontend does not support every concurrent SVA construct. A wrapper
may select an equivalent procedural implementation only when
`MOSAIC_YOSYS_FORMAL` is defined, while keeping both implementations in the same
source module. Other formal tools should use the shared concurrent properties.

Do not assume that the Yosys frontend applies a simulation-oriented `bind`.
Keep each assertion or coverage model inside a reusable wrapper. Bind that
wrapper to the DUT when `MOSAIC_FORMAL` is not defined, and explicitly
instantiate the same wrapper in the formal harness when `MOSAIC_FORMAL` is
defined. This preserves one verification wrapper without allowing a vacuous
formal run.

When `COVERAGE_FILELIST` is nonempty, `FORMAL_COVER_CONFIG` is required and
`open-formal` runs both the proof and cover reachability tasks. `SIM_COVERAGE`
defaults to `enabled`. Verilator exports `coverage.dat` and `coverage.info`,
while VCS retains its native `coverage.vdb` database.

The current Design Compiler adapter reads
`$(CONSTRAINT_DIR)/timing.sdc`. Keep `SYNTHESIS_CONSTRAINT_FILE` consistent with
that path until the adapter is changed to consume the variable directly.

## Technology and site variables

| Variable | Purpose |
| --- | --- |
| `TECH_SETUP_TCL` | Optional Tcl sourced by Design Compiler, PrimeTime, and PrimePower |
| `TARGET_LIBRARY` | Site or project target libraries when used by setup Tcl |
| `LINK_LIBRARY` | Site or project link libraries when used by setup Tcl |
| `OPERATING_CONDITION` | Requested timing or power corner when used by setup Tcl |
| `OPENROAD_FLOW_ROOT` | Checkout root of OpenROAD Flow Scripts |

The shared Tcl currently sources `TECH_SETUP_TCL` when it is nonempty. The other
technology variables are exported for the site setup to consume. Their exact
interpretation is intentionally site-owned because library naming and corner
setup differ by PDK.

Example local shell setup:

```sh
export TECH_SETUP_TCL="$HOME/site/mosaic/technology_setup.tcl"
export TARGET_LIBRARY="/pdk/lib/target.db"
export LINK_LIBRARY="* /pdk/lib/target.db"
export OPERATING_CONDITION="slow"
make synopsys-synth
```

## Executable overrides

| Variable | Default command | Flow |
| --- | --- | --- |
| `SIM_BIN` | `vcs` | VCS simulation |
| `VERILATOR_CMD` | `verilator` | Verilator lint and simulation |
| `YOSYS_CMD` | `yosys` | Generic synthesis |
| `SBY_CMD` | `sby` | Formal verification |
| `EQY_CMD` | `eqy` | Equivalence checking |
| `SLANG_CMD` | `slang` | Compilation and elaboration |
| `VERIBLE_LINT_CMD` | `verible-verilog-lint` | Style lint |
| `VERIBLE_FORMAT_CMD` | `verible-verilog-format` | Format check |
| `OPENROAD_CMD` | `openroad` | Reserved direct OpenROAD executable override |
| `VC_LINT_BIN` | `vc_static_shell` | VC Lint |
| `VC_CDC_BIN` | `vc_static_shell` | VC CDC |
| `SG_CDC_BIN` | `sg_shell` | SpyGlass CDC |
| `SG_DFT_BIN` | `sg_shell` | SpyGlass DFT |
| `VC_LP_BIN` | `vc_static_shell` | VC LP |
| `SYNTH_BIN` | `dc_shell` | Design Compiler |
| `PRIMETIME_BIN` | `pt_shell` | PrimeTime |
| `PRIMEPOWER_BIN` | `pt_shell` | PrimePower |

The current OpenROAD wrapper invokes the OpenROAD Flow Scripts Makefile. It
uses `OPENROAD_FLOW_ROOT` and `OPENROAD_CONFIG` rather than invoking
`OPENROAD_CMD` directly.

`VERIBLE_FORMAT_ARGS` provides whitespace-separated formatter options such as
`--indentation_spaces=4`. `VERIBLE_FORMAT_PATHS` selects the module-owned files
or directories checked by the formatting flow and defaults to `rtl verif`.

## Multi-module variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `MODULE_MANIFEST` | `$(MODULE_ROOT)/config/modules.json` | Versioned module registry |
| `MODULE` | Empty | Selected manifest entry for one flow invocation |
| `TARGET` | `open-source` | Target dispatched by `all-modules` |
| `MODULE_JOBS` | `JOBS` or `0` | Maximum concurrent module invocations; zero means unbounded |
| `MODULE_DESIGN_CONFIG` | `config/modules/<MODULE>.mk` | Selected design profile |
| `MODULE_FLOW_CONFIG` | `config/modules/<MODULE>-flows.mk` | Selected flow policy |

Use `mk/project.mk` to activate these variables. The legacy single-module
import remains supported without a manifest.

## Open-source tool cache

`config/tools.mk` prepends three versioned directories to `PATH`:

```text
${MOSAIC_TOOLS_ROOT}/verible/<version>/bin
${MOSAIC_TOOLS_ROOT}/slang/<version>/bin
${MOSAIC_TOOLS_ROOT}/oss-cad-suite/<version>/bin
```

The default cache root is `${XDG_CACHE_HOME:-$HOME/.cache}/mosaic`. Change it
without editing the methodology:

```sh
make MOSAIC_TOOLS_ROOT=/shared/eda/mosaic setup-open-source
```

Versions and archive checksums are maintained in
`config/tool-versions.env`. A methodology release must qualify any version
change with the repository fixture before consumers update their gitlink.

## Configuration examples

### Disable formal and equivalence together

```make
FLOW_symbiyosys_formal := disabled
FLOW_eqy_equivalence := disabled
```

### Require simulation before synthesis

```make
FLOW_DEPENDENCIES_yosys_synthesis := verilator_sim
```

### Use a development checkout of the methodology

```sh
make FLOW_ROOT="$HOME/src/mosaic-flow" clean open-source
```

### Display the final policy

```sh
make flow-config-check
```

The output lists enabled flows, disabled flows, and every nonempty dependency
list. Treat this output as the first diagnostic when a target is unexpectedly
skipped or blocked.
