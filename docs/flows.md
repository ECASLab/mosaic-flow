# Flow catalog

## How to read this catalog

Each flow has a canonical ID used by configuration, dependencies, report
directories, and quality gates. The Make target is the public user interface.
The adapter is owned by `mosaic-flow`. Design-specific inputs are owned by the
module repository.

All target paths below are relative to the module root unless identified as
shared methodology paths.

## Summary

| Canonical ID | Make target | Tool | Gate | Default dependencies |
| --- | --- | --- | --- | --- |
| `verible_lint` | `open-style-lint` | Verible | Open-source | None |
| `verible_format` | `open-format-check` | Verible | Open-source | None |
| `slang_elaboration` | `open-elaborate` | Slang | Open-source | None |
| `verilator_lint` | `open-lint` | Verilator | Open-source | None |
| `yosys_synthesis` | `open-synth` | Yosys | Open-source | None |
| `symbiyosys_formal` | `open-formal` | SymbiYosys | Open-source | None |
| `eqy_equivalence` | `open-equivalence` | EQY | Open-source | `yosys_synthesis` |
| `verilator_sim` | `open-sim` | Verilator | Open-source | None |
| `openroad` | `open-physical` | OpenROAD Flow Scripts | Optional | None |
| `vcs_sim` | `synopsys-sim` | VCS | Commercial | None |
| `vc_lint` | `synopsys-lint` | VC SpyGlass | Commercial | None |
| `vc_cdc` | `synopsys-cdc CDC_TOOL=vc` | VC SpyGlass | Commercial | None |
| `sg_cdc` | `synopsys-cdc CDC_TOOL=sg` | SpyGlass | Commercial | None |
| `sg_dft` | `synopsys-dft` | SpyGlass | Commercial | None |
| `vc_lp` | `synopsys-lp` | VC LP | Commercial | None |
| `synopsys_synthesis` | `synopsys-synth` | Design Compiler | Commercial | None |
| `synopsys_primetime` | `synopsys-sta` | PrimeTime | Commercial | `synopsys_synthesis` |
| `synopsys_primepower` | `synopsys-power` | PrimePower | Commercial | `vcs_sim synopsys_synthesis` |

`open-source` and `synopsys-all` are aggregate targets. They do not have their
own canonical flow IDs.

## Open-source flows

### Verible style lint

- **ID:** `verible_lint`
- **Target:** `make open-style-lint`
- **Adapter:** [`flows/verible/run_lint.sh`](../flows/verible/run_lint.sh)
- **Inputs:** `RTL_FILELIST`, `VERIBLE_RULES_FILE`, `VERIBLE_WAIVER_FILE`
- **Reports:** `reports/verible_lint/lint.log`, `status.txt`

The adapter reads synthesizable sources from the RTL file list, loads the
module's selected rules and reviewed waiver file, and makes parser or lint
violations fatal. Include-directory entries are ignored by this adapter because
the lint invocation receives source paths directly. Other option-like file-list
entries are rejected.

Rules and waivers belong to the module because coding policy exceptions must be
reviewed in the context of the RTL they affect.

More information: [Verible lint rules](https://chipsalliance.github.io/verible/lint.html)
and the [Verible project documentation](https://chipsalliance.github.io/verible/README.html).

### Verible format check

- **ID:** `verible_format`
- **Target:** `make open-format-check`
- **Adapter:** [`flows/verible/run_format.sh`](../flows/verible/run_format.sh)
- **Inputs:** all `*.sv` and `*.svh` files below module `rtl/` and `verif/`
- **Reports:** `reports/verible_format/format.log`, `status.txt`

This is a verification-only formatting check. It compares every source file
against Verible's output and never modifies RTL. Any difference or formatter
convergence failure fails the flow.

More information: [Verible formatter](https://chipsalliance.github.io/verible/verilog_format.html).

### Slang compilation and elaboration

- **ID:** `slang_elaboration`
- **Target:** `make open-elaborate`
- **Adapter:** [`flows/slang/run.sh`](../flows/slang/run.sh)
- **Inputs:** `RTL_FILELIST`, `DESIGN_TOP`
- **Reports:** `reports/slang_elaboration/elaboration.log`, `status.txt`

Slang parses, type-checks, and elaborates the complete RTL as one compilation
unit. This provides a SystemVerilog frontend independent from Verilator and
Yosys. It is useful for finding language, hierarchy, width, and elaboration
issues before simulation or synthesis.

More information: [Slang user manual](https://www.sv-lang.com/user-manual.html).

### Verilator lint

- **ID:** `verilator_lint`
- **Target:** `make open-lint`
- **Draft waiver target:** `make open-waiver-draft`
- **Adapter:** [`flows/verilator_lint/run.sh`](../flows/verilator_lint/run.sh)
- **Inputs:** `RTL_FILELIST`, `DESIGN_TOP`, `VERILATOR_WAIVER_FILE`
- **Reports:** `reports/verilator_lint/lint.log`, `status.txt`

The adapter runs `--lint-only --sv --Wall`. Warnings are fatal unless the
module's control file contains a narrowly scoped exception. The draft target
runs with nonfatal warnings and writes
`reports/verilator_lint/suggested_waivers.vlt`. It never approves or copies a
waiver.

More information: [Verilator User's Guide](https://verilator.org/guide/latest/),
including its control-file and warning references.

### Yosys generic synthesis

- **ID:** `yosys_synthesis`
- **Target:** `make open-synth`
- **Adapter:** [`flows/yosys_synthesis/run.sh`](../flows/yosys_synthesis/run.sh)
- **Inputs:** `RTL_FILELIST`, `DESIGN_TOP`
- **Reports:** `reports/yosys_synthesis/synthesis.log`, `statistics.rpt`, `status.txt`
- **Work products:** `work/yosys_synthesis/<top>.json`, `<top>_netlist.v`

This portable synthesis check reads SystemVerilog, resolves include directories,
checks hierarchy, lowers processes, performs generic synthesis, and runs
structural checks before and after synthesis. It does not map to a PDK and is not
an area, timing, or power signoff result.

The generated Verilog netlist is consumed by the default EQY configuration.

More information: [Yosys documentation](https://yosyshq.readthedocs.io/projects/yosys/en/latest/).

### SymbiYosys formal verification

- **ID:** `symbiyosys_formal`
- **Target:** `make open-formal`
- **Adapter:** [`flows/symbiyosys/run.sh`](../flows/symbiyosys/run.sh)
- **Inputs:** `FORMAL_CONFIG` and all sources referenced by the module's `.sby` file
- **Reports:** `reports/symbiyosys_formal/formal.log`, `status.txt`
- **Work products:** complete SymbiYosys database below `work/symbiyosys_formal/`

The module owns proof modes, engines, depth, formal harness, assumptions,
assertions, and cover statements. The adapter succeeds only when SymbiYosys
returns successfully and its work directory contains `PASS`.

More information: [SymbiYosys documentation](https://yosyshq.readthedocs.io/projects/sby/en/stable/).

### EQY equivalence

- **ID:** `eqy_equivalence`
- **Target:** `make open-equivalence`
- **Adapter:** [`flows/eqy/run.sh`](../flows/eqy/run.sh)
- **Inputs:** `EQUIVALENCE_CONFIG`, module RTL, Yosys netlist
- **Reports:** `reports/eqy_equivalence/equivalence.log`, `status.txt`
- **Work products:** complete EQY database below `work/eqy_equivalence/`
- **Default dependency:** `yosys_synthesis`

The module's `.eqy` file defines the golden RTL, gate netlist, preparation, and
proof strategies. The adapter succeeds only when EQY returns successfully and
writes a `PASS` marker. The default dependency ensures the netlist exists and
was generated by a passing synthesis run.

More information: [EQY documentation](https://yosyshq.readthedocs.io/projects/eqy/en/latest/).

### Verilator simulation

- **ID:** `verilator_sim`
- **Target:** `make open-sim`
- **Adapter:** [`flows/sim/run.sh`](../flows/sim/run.sh)
- **Inputs:** `TB_FILELIST`, `TB_TOP`
- **Reports:** `reports/verilator_sim/compile.log`, `run.log`, `status.txt`
- **Work products:** generated model and executable below `work/verilator_sim/obj_dir/`

The adapter compiles a standalone executable with timing support and assertions
enabled through `--timing --assert`. It then executes the testbench binary. A
compile error, assertion failure that terminates simulation, testbench failure,
or nonzero simulation exit fails the flow.

Assertions only provide release evidence when the testbench reaches the relevant
conditions. Module verification must also define meaningful stimulus, checking,
and coverage goals.

More information: [Verilator User's Guide](https://verilator.org/guide/latest/).

### OpenROAD physical implementation

- **ID:** `openroad`
- **Target:** `make open-physical`
- **Adapter:** [`flows/openroad/run.sh`](../flows/openroad/run.sh)
- **Inputs:** `OPENROAD_FLOW_ROOT`, `OPENROAD_CONFIG`, PDK and platform collateral
- **Reports:** `reports/openroad/run.log`, `status.txt`
- **Work products:** managed by the selected OpenROAD Flow Scripts checkout

This optional adapter invokes OpenROAD Flow Scripts with the module-owned design
configuration. It is not part of `make open-source` because it requires a
selected PDK, compatible libraries, LEF data, and physical constraints.

Set `OPENROAD_FLOW_ROOT` to a qualified OpenROAD Flow Scripts checkout. The
module configuration must select its platform, top, source files, SDC, and
physical targets. The exact physical result hierarchy is owned by OpenROAD Flow
Scripts rather than copied into the module's `work/openroad/` directory.

More information: [OpenROAD Flow](https://openroad-flow-scripts.readthedocs.io/en/latest/mainREADME.html)
and its [configuration tutorial](https://openroad-flow-scripts.readthedocs.io/en/latest/tutorials/FlowTutorial.html).

## Commercial flows

Commercial flows require licensed local executables and technology setup. They
are never launched by this repository's GitHub-hosted workflow.

Run `make synopsys-check-env` to check executable discovery for all enabled
commercial flows. This confirms command availability only. It does not qualify
licenses, PDK data, constraints, adapter semantics, or signoff policy.

### VCS simulation

- **ID:** `vcs_sim`
- **Target:** `make synopsys-sim`
- **Adapter:** [`flows/sim/run.sh`](../flows/sim/run.sh)
- **Inputs:** `TB_FILELIST`, `TB_TOP`, optional simulator flags from the environment
- **Reports:** `reports/vcs_sim/compile.log`, `run.log`, `status.txt`
- **Work products:** `work/vcs_sim/simv` and simulator-generated data

VCS compiles and runs the same module-owned testbench file list used by the
portable simulation. The testbench or local VCS setup must write SAIF at
`ACTIVITY_FILE` when PrimePower is enabled.

More information: [Synopsys VCS](https://www.synopsys.com/verification/simulation/vcs.html).

### VC Lint

- **ID:** `vc_lint`
- **Target:** `make synopsys-lint`
- **Adapter:** [`flows/vc_lint/run.tcl`](../flows/vc_lint/run.tcl)
- **Expected inputs:** `RTL_FILELIST`, `DESIGN_TOP`, approved local goals and waivers
- **Reports:** `reports/vc_lint/run.log`, `status.txt`
- **Readiness:** **release-specific placeholder**

The shared Tcl intentionally raises an error until it is adapted to the installed
VC SpyGlass release. A qualified implementation must read and elaborate the RTL,
run the approved lint goals, emit reviewable reports, and return nonzero for any
unwaived release-blocking violation.

More information: [Synopsys VC SpyGlass](https://www.synopsys.com/verification/static-and-formal-verification/vc-spyglass.html).

### VC CDC

- **ID:** `vc_cdc`
- **Target:** `make synopsys-cdc CDC_TOOL=vc`
- **Adapter:** [`flows/cdc/vc_run.tcl`](../flows/cdc/vc_run.tcl)
- **Expected inputs:** `RTL_FILELIST`, `DESIGN_TOP`, `CDC_CONFIG`
- **Reports:** `reports/vc_cdc/run.log`, `status.txt`
- **Readiness:** **release-specific placeholder**

The final adapter must load module clock, reset, synchronization, and crossing
intent, then run approved structural and functional CDC goals. Every unwaived
crossing covered by release policy must cause a nonzero result.

More information: [Synopsys VC SpyGlass](https://www.synopsys.com/verification/static-and-formal-verification/vc-spyglass.html).

### SpyGlass CDC

- **ID:** `sg_cdc`
- **Target:** `make synopsys-cdc CDC_TOOL=sg`
- **Adapter:** [`flows/cdc/sg_run.tcl`](../flows/cdc/sg_run.tcl)
- **Expected inputs:** `RTL_FILELIST`, `DESIGN_TOP`, `CDC_CONFIG`
- **Reports:** `reports/sg_cdc/run.log`, `status.txt`
- **Readiness:** **release-specific placeholder**

This is the alternative CDC engine. Its qualification criteria are the same as
VC CDC, but command syntax and goal setup must match the installed SpyGlass
release.

More information is normally available through the licensed Synopsys
SolvNetPlus documentation associated with the installed release.

### SpyGlass DFT

- **ID:** `sg_dft`
- **Target:** `make synopsys-dft`
- **Adapter:** [`flows/sg_dft/run.tcl`](../flows/sg_dft/run.tcl)
- **Expected inputs:** `RTL_FILELIST`, `DESIGN_TOP`, `DFT_CONFIG`
- **Reports:** `reports/sg_dft/run.log`, `status.txt`
- **Readiness:** **release-specific placeholder**

The final adapter must run the project's approved controllability,
observability, test-clock, reset, and scan-readiness goals. Unwaived violations
must fail the flow.

Product and command documentation is available through the installed SpyGlass
release and Synopsys SolvNetPlus.

### VC LP

- **ID:** `vc_lp`
- **Target:** `make synopsys-lp`
- **Adapter:** [`flows/vc_lp/run.tcl`](../flows/vc_lp/run.tcl)
- **Expected inputs:** `RTL_FILELIST`, `DESIGN_TOP`, `UPF_CONFIG`
- **Reports:** `reports/vc_lp/run.log`, `status.txt`
- **Readiness:** **release-specific placeholder**

The qualified adapter must load RTL and UPF, verify structural low-power intent,
power states, isolation, retention, and relevant sequencing policy, then fail on
every unwaived release-blocking violation.

More information: [Synopsys VC LP](https://www.synopsys.com/verification/static-and-formal-verification/vc-lp.html).

### Design Compiler synthesis

- **ID:** `synopsys_synthesis`
- **Target:** `make synopsys-synth`
- **Adapter:** [`flows/synthesis/run.tcl`](../flows/synthesis/run.tcl)
- **Inputs:** `RTL_FILELIST`, `DESIGN_TOP`, `CONSTRAINT_DIR/timing.sdc`, optional `TECH_SETUP_TCL`
- **Reports:** `qor.rpt`, `area.rpt`, `timing.rpt`, `power.rpt`, `run.log`, `status.txt`
- **Work products:** SVF, DDC, mapped Verilog netlist, generated SDC

The adapter analyzes SystemVerilog, elaborates and links the top, loads timing
constraints, checks the design, and runs `compile_ultra`. A technology setup must
provide target and link libraries plus any required operating conditions.

More information: [Synopsys Design Compiler](https://www.synopsys.com/implementation-and-signoff/rtl-synthesis-test/design-compiler.html).

### PrimeTime static timing analysis

- **ID:** `synopsys_primetime`
- **Target:** `make synopsys-sta`
- **Adapter:** [`flows/primetime/run.tcl`](../flows/primetime/run.tcl)
- **Inputs:** synthesis DDC and SDC, optional `TECH_SETUP_TCL`
- **Reports:** `check_timing.rpt`, `global_timing.rpt`, `setup.rpt`, `hold.rpt`, `violations.rpt`, `run.log`, `status.txt`
- **Default dependency:** `synopsys_synthesis`

The adapter updates timing, reports setup and hold paths plus all constraint
violators, and raises an error when any setup or hold path has negative slack.
The current flow analyzes the synthesized design. Post-layout signoff requires
additional extraction and physical context beyond this adapter.

More information: [Synopsys PrimeTime](https://www.synopsys.com/implementation-and-signoff/signoff/primetime.html).

### PrimePower analysis

- **ID:** `synopsys_primepower`
- **Target:** `make synopsys-power`
- **Adapter:** [`flows/primepower/run.tcl`](../flows/primepower/run.tcl)
- **Inputs:** synthesis DDC and SDC, `ACTIVITY_FILE`, `DUT_INSTANCE`, optional `TECH_SETUP_TCL`
- **Reports:** `hierarchical_power.rpt`, `power.rpt`, `activity.rpt`, `run.log`, `status.txt`
- **Default dependencies:** `vcs_sim`, `synopsys_synthesis`

The shell wrapper requires the SAIF file to exist before launching PrimePower.
The Tcl adapter reads the synthesized design and constraints, annotates activity
at `DUT_INSTANCE`, updates timing and power, then reports hierarchical power and
switching activity. Review activity coverage before accepting a power result.

More information: [Synopsys PrimePower](https://www.synopsys.com/implementation-and-signoff/signoff/primepower.html).

## Aggregate targets

### Portable gate

```sh
make open-source
```

This runs Verible lint and format, Slang elaboration, Verilator lint, Yosys
synthesis, SymbiYosys formal, EQY equivalence, and Verilator simulation. It then
applies the open-source quality gate. OpenROAD is intentionally excluded.

### Commercial static checks

```sh
make synopsys-static CDC_TOOL=vc
```

This runs VC Lint, the selected CDC engine, SpyGlass DFT, and VC LP. The four
release-specific adapters must be implemented before this aggregate can pass.

### Complete commercial gate

```sh
make synopsys-all CDC_TOOL=vc
```

This includes an executable-availability prerequisite, runs VCS simulation, all
selected static checks, Design Compiler synthesis, PrimeTime, and PrimePower,
then validates the commercial result set. Run `make synopsys-check-env`
explicitly as a preflight before an expensive local run.
