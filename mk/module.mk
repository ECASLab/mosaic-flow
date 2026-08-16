export CDC_TOOL ?= vc
export FORCE_FLOW ?= 0

include $(FLOW_ROOT)/config/flows.mk
-include $(MODULE_ROOT)/config/flows.mk

mosaic_flow_state_is_valid = $(and $(filter 1,$(words $(1))),$(filter $(1),enabled disabled))
MOSAIC_INVALID_FLOW_STATES := $(strip $(foreach flow,$(MOSAIC_FLOW_IDS),$(if $(call mosaic_flow_state_is_valid,$(FLOW_$(flow))),,$(flow)=$(FLOW_$(flow)))))
ifneq ($(MOSAIC_INVALID_FLOW_STATES),)
$(error Flow states must be 'enabled' or 'disabled': $(MOSAIC_INVALID_FLOW_STATES))
endif

MOSAIC_EXPLICIT_DISABLED_FLOWS := $(DISABLED_FLOWS)
override DISABLED_FLOWS := $(sort $(MOSAIC_EXPLICIT_DISABLED_FLOWS) $(foreach flow,$(MOSAIC_FLOW_IDS),$(if $(filter disabled,$(FLOW_$(flow))),$(flow))))
export DISABLED_FLOWS
export MOSAIC_FLOW_IDS
export $(foreach flow,$(MOSAIC_FLOW_IDS),FLOW_$(flow) FLOW_DEPENDENCIES_$(flow))

FLOW_RUNNER := $(FLOW_ROOT)/ci/run_flow.sh

OPEN_SOURCE_TARGETS := open-source open-style-lint open-format-check open-elaborate open-lint open-waiver-draft open-synth open-formal open-equivalence open-sim open-quality-gate
OPEN_FLOW_TARGETS := open-style-lint open-format-check open-elaborate open-lint open-synth open-formal open-equivalence open-sim

FLOW_TARGET_verible_lint := open-style-lint
FLOW_TARGET_verible_format := open-format-check
FLOW_TARGET_slang_elaboration := open-elaborate
FLOW_TARGET_verilator_lint := open-lint
FLOW_TARGET_yosys_synthesis := open-synth
FLOW_TARGET_symbiyosys_formal := open-formal
FLOW_TARGET_eqy_equivalence := open-equivalence
FLOW_TARGET_verilator_sim := open-sim
FLOW_TARGET_openroad := open-physical
FLOW_TARGET_vcs_sim := synopsys-sim
FLOW_TARGET_vc_lint := synopsys-lint
FLOW_TARGET_vc_cdc := $(if $(filter vc,$(CDC_TOOL)),synopsys-cdc)
FLOW_TARGET_sg_cdc := $(if $(filter sg,$(CDC_TOOL)),synopsys-cdc)
FLOW_TARGET_sg_dft := synopsys-dft
FLOW_TARGET_vc_lp := synopsys-lp
FLOW_TARGET_synopsys_synthesis := synopsys-synth
FLOW_TARGET_synopsys_primetime := synopsys-sta
FLOW_TARGET_synopsys_primepower := synopsys-power

MOSAIC_FLOW_TARGETS := $(sort $(foreach flow,$(MOSAIC_FLOW_IDS),$(FLOW_TARGET_$(flow))))

define mosaic_add_flow_dependencies
$(FLOW_TARGET_$(1)): $(foreach dependency,$(FLOW_DEPENDENCIES_$(1)),$(FLOW_TARGET_$(dependency)))
endef
$(foreach flow,$(MOSAIC_FLOW_IDS),$(eval $(call mosaic_add_flow_dependencies,$(flow))))

.PHONY: help flow-config-check setup-open-source $(OPEN_SOURCE_TARGETS) open-physical synopsys-all synopsys-check-env synopsys-sim synopsys-lint synopsys-cdc synopsys-dft synopsys-lp synopsys-static synopsys-synth synopsys-sta synopsys-power synopsys-quality-gate clean

help:
	@sed -n 's/^## //p' "$(FLOW_ROOT)/mk/module.mk"

## flow-config-check Validate and display the project flow selection
flow-config-check:
	@"$(FLOW_ROOT)/ci/check_flow_config.sh"

## setup-open-source Install missing pinned open-source tools in the user cache
setup-open-source:
	@"$(FLOW_ROOT)/ci/setup_open_source_tools.sh"

$(MOSAIC_FLOW_TARGETS): | flow-config-check
$(OPEN_FLOW_TARGETS) open-waiver-draft: | setup-open-source

## open-source  Run every open-source CI check and its quality gate
open-source: open-quality-gate

## open-style-lint Run Verible style lint with reviewed waivers
open-style-lint:
	@"$(FLOW_RUNNER)" verible_lint "$(FLOW_ROOT)/flows/verible/run_lint.sh"

## open-format-check Check SystemVerilog formatting with Verible
open-format-check:
	@"$(FLOW_RUNNER)" verible_format "$(FLOW_ROOT)/flows/verible/run_format.sh"

## open-elaborate Compile and elaborate the RTL independently with Slang
open-elaborate:
	@"$(FLOW_RUNNER)" slang_elaboration "$(FLOW_ROOT)/flows/slang/run.sh"

## open-lint    Run strict open-source lint with Verilator
open-lint:
	@"$(FLOW_RUNNER)" verilator_lint "$(FLOW_ROOT)/flows/verilator_lint/run.sh"

## open-waiver-draft Generate suggested Verilator waivers for review
open-waiver-draft:
	@"$(FLOW_ROOT)/flows/verilator_lint/generate_waivers.sh"

## open-synth   Run technology-independent synthesis with Yosys
open-synth:
	@"$(FLOW_RUNNER)" yosys_synthesis "$(FLOW_ROOT)/flows/yosys_synthesis/run.sh"

## open-formal  Run formal verification with SymbiYosys
open-formal:
	@"$(FLOW_RUNNER)" symbiyosys_formal "$(FLOW_ROOT)/flows/symbiyosys/run.sh"

## open-equivalence Prove RTL-to-synthesized-netlist equivalence with EQY
open-equivalence:
	@"$(FLOW_RUNNER)" eqy_equivalence "$(FLOW_ROOT)/flows/eqy/run.sh"

## open-sim     Compile and simulate with Verilator
open-sim:
	@SIMULATOR=verilator "$(FLOW_RUNNER)" verilator_sim "$(FLOW_ROOT)/flows/sim/run.sh"

## open-quality-gate Validate all open-source results
open-quality-gate: $(OPEN_FLOW_TARGETS)
	@"$(FLOW_ROOT)/ci/open_source_quality_gate.sh"

## open-physical Run the optional OpenROAD PDK-backed implementation flow
open-physical:
	@"$(FLOW_RUNNER)" openroad "$(FLOW_ROOT)/flows/openroad/run.sh"

## synopsys-check-env Check local Synopsys executable availability
synopsys-check-env:
	@"$(FLOW_ROOT)/ci/check_synopsys_environment.sh"

## synopsys-sim Compile and simulate locally with VCS
synopsys-sim:
	@SIMULATOR=vcs "$(FLOW_RUNNER)" vcs_sim "$(FLOW_ROOT)/flows/sim/run.sh"

## synopsys-lint Run VC Lint locally
synopsys-lint:
	@"$(FLOW_RUNNER)" vc_lint "$(FLOW_ROOT)/flows/vc_lint/run.sh"

## synopsys-cdc Run CDC locally with CDC_TOOL=vc or CDC_TOOL=sg
synopsys-cdc:
	@"$(FLOW_RUNNER)" "$(CDC_TOOL)_cdc" "$(FLOW_ROOT)/flows/cdc/run.sh" "$(CDC_TOOL)"

## synopsys-dft Run SpyGlass DFT checks locally
synopsys-dft:
	@"$(FLOW_RUNNER)" sg_dft "$(FLOW_ROOT)/flows/sg_dft/run.sh"

## synopsys-lp  Run VC LP checks locally
synopsys-lp:
	@"$(FLOW_RUNNER)" vc_lp "$(FLOW_ROOT)/flows/vc_lp/run.sh"

## synopsys-static Run all local Synopsys static RTL checks
synopsys-static: synopsys-lint synopsys-cdc synopsys-dft synopsys-lp

## synopsys-synth Run technology-mapped synthesis locally
synopsys-synth:
	@"$(FLOW_RUNNER)" synopsys_synthesis "$(FLOW_ROOT)/flows/synthesis/run.sh"

## synopsys-sta Run PrimeTime static timing analysis locally
synopsys-sta:
	@"$(FLOW_RUNNER)" synopsys_primetime "$(FLOW_ROOT)/flows/primetime/run.sh"

## synopsys-power Run PrimePower locally using annotated activity
synopsys-power:
	@"$(FLOW_RUNNER)" synopsys_primepower "$(FLOW_ROOT)/flows/primepower/run.sh"

## synopsys-quality-gate Validate all commercial-tool results
synopsys-quality-gate: synopsys-sim synopsys-static synopsys-synth synopsys-sta synopsys-power | synopsys-check-env
	@"$(FLOW_ROOT)/ci/synopsys_quality_gate.sh"

## synopsys-all Run the complete licensed local Synopsys flow
synopsys-all: synopsys-quality-gate

## clean        Remove generated work and reports
clean:
	@"$(FLOW_ROOT)/ci/clean.sh"
