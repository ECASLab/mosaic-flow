CDC_TOOL ?= vc

.PHONY: help open-source open-lint open-style-lint open-format-check open-elaborate open-synth open-formal open-equivalence open-sim open-quality-gate open-waiver-draft open-physical synopsys-all synopsys-check-env synopsys-sim synopsys-lint synopsys-cdc synopsys-dft synopsys-lp synopsys-static synopsys-synth synopsys-sta synopsys-power synopsys-quality-gate clean

help:
	@sed -n 's/^## //p' "$(FLOW_ROOT)/mk/module.mk"

## open-source  Run every open-source CI check and its quality gate
open-source:
	@$(MAKE) open-style-lint
	@$(MAKE) open-format-check
	@$(MAKE) open-elaborate
	@$(MAKE) open-lint
	@$(MAKE) open-synth
	@$(MAKE) open-formal
	@$(MAKE) open-equivalence
	@$(MAKE) open-sim
	@$(MAKE) open-quality-gate

## open-style-lint Run Verible style lint with reviewed waivers
open-style-lint:
	@"$(FLOW_ROOT)/flows/verible/run_lint.sh"

## open-format-check Check SystemVerilog formatting with Verible
open-format-check:
	@"$(FLOW_ROOT)/flows/verible/run_format.sh"

## open-elaborate Compile and elaborate the RTL independently with Slang
open-elaborate:
	@"$(FLOW_ROOT)/flows/slang/run.sh"

## open-lint    Run strict open-source lint with Verilator
open-lint:
	@"$(FLOW_ROOT)/flows/verilator_lint/run.sh"

## open-waiver-draft Generate suggested Verilator waivers for review
open-waiver-draft:
	@"$(FLOW_ROOT)/flows/verilator_lint/generate_waivers.sh"

## open-synth   Run technology-independent synthesis with Yosys
open-synth:
	@"$(FLOW_ROOT)/flows/yosys_synthesis/run.sh"

## open-formal  Run formal verification with SymbiYosys
open-formal:
	@"$(FLOW_ROOT)/flows/symbiyosys/run.sh"

## open-equivalence Prove RTL-to-synthesized-netlist equivalence with EQY
open-equivalence:
	@"$(FLOW_ROOT)/flows/eqy/run.sh"

## open-sim     Compile and simulate with Verilator
open-sim:
	@SIMULATOR=verilator "$(FLOW_ROOT)/flows/sim/run.sh"

## open-quality-gate Validate all open-source results
open-quality-gate:
	@"$(FLOW_ROOT)/ci/open_source_quality_gate.sh"

## open-physical Run the optional OpenROAD PDK-backed implementation flow
open-physical:
	@"$(FLOW_ROOT)/flows/openroad/run.sh"

## synopsys-check-env Check local Synopsys executable availability
synopsys-check-env:
	@"$(FLOW_ROOT)/ci/check_synopsys_environment.sh"

## synopsys-sim Compile and simulate locally with VCS
synopsys-sim:
	@SIMULATOR=vcs "$(FLOW_ROOT)/flows/sim/run.sh"

## synopsys-lint Run VC Lint locally
synopsys-lint:
	@"$(FLOW_ROOT)/flows/vc_lint/run.sh"

## synopsys-cdc Run CDC locally with CDC_TOOL=vc or CDC_TOOL=sg
synopsys-cdc:
	@"$(FLOW_ROOT)/flows/cdc/run.sh" "$(CDC_TOOL)"

## synopsys-dft Run SpyGlass DFT checks locally
synopsys-dft:
	@"$(FLOW_ROOT)/flows/sg_dft/run.sh"

## synopsys-lp  Run VC LP checks locally
synopsys-lp:
	@"$(FLOW_ROOT)/flows/vc_lp/run.sh"

## synopsys-static Run all local Synopsys static RTL checks
synopsys-static:
	@$(MAKE) synopsys-lint
	@$(MAKE) synopsys-cdc CDC_TOOL="$(CDC_TOOL)"
	@$(MAKE) synopsys-dft
	@$(MAKE) synopsys-lp

## synopsys-synth Run technology-mapped synthesis locally
synopsys-synth:
	@"$(FLOW_ROOT)/flows/synthesis/run.sh"

## synopsys-sta Run PrimeTime static timing analysis locally
synopsys-sta:
	@"$(FLOW_ROOT)/flows/primetime/run.sh"

## synopsys-power Run PrimePower locally using annotated activity
synopsys-power:
	@"$(FLOW_ROOT)/flows/primepower/run.sh"

## synopsys-quality-gate Validate all commercial-tool results
synopsys-quality-gate:
	@"$(FLOW_ROOT)/ci/synopsys_quality_gate.sh"

## synopsys-all Run the complete licensed local Synopsys flow
synopsys-all:
	@$(MAKE) synopsys-check-env
	@$(MAKE) synopsys-sim
	@$(MAKE) synopsys-static CDC_TOOL="$(CDC_TOOL)"
	@$(MAKE) synopsys-synth
	@$(MAKE) synopsys-sta
	@$(MAKE) synopsys-power
	@$(MAKE) synopsys-quality-gate

## clean        Remove generated work and reports
clean:
	@"$(FLOW_ROOT)/ci/clean.sh"
