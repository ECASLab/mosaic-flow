# Canonical flow states. Consuming projects may override these values in
# $(MODULE_ROOT)/config/flows.mk.
MOSAIC_FLOW_IDS := \
	verible_lint \
	verible_format \
	slang_elaboration \
	verilator_lint \
	yosys_synthesis \
	symbiyosys_formal \
	eqy_equivalence \
	verilator_sim \
	openroad \
	vcs_sim \
	vc_lint \
	vc_cdc \
	sg_cdc \
	sg_dft \
	vc_lp \
	synopsys_synthesis \
	synopsys_primetime \
	synopsys_primepower

FLOW_verible_lint ?= enabled
FLOW_verible_format ?= enabled
FLOW_slang_elaboration ?= enabled
FLOW_verilator_lint ?= enabled
FLOW_yosys_synthesis ?= enabled
FLOW_symbiyosys_formal ?= enabled
FLOW_eqy_equivalence ?= enabled
FLOW_verilator_sim ?= enabled
FLOW_openroad ?= enabled
FLOW_vcs_sim ?= enabled
FLOW_vc_lint ?= enabled
FLOW_vc_cdc ?= enabled
FLOW_sg_cdc ?= enabled
FLOW_sg_dft ?= enabled
FLOW_vc_lp ?= enabled
FLOW_synopsys_synthesis ?= enabled
FLOW_synopsys_primetime ?= enabled
FLOW_synopsys_primepower ?= enabled

# Dependencies use canonical flow IDs. Projects may replace any dependency
# list in their module-owned config/flows.mk.
FLOW_DEPENDENCIES_verible_lint ?=
FLOW_DEPENDENCIES_verible_format ?=
FLOW_DEPENDENCIES_slang_elaboration ?=
FLOW_DEPENDENCIES_verilator_lint ?=
FLOW_DEPENDENCIES_yosys_synthesis ?=
FLOW_DEPENDENCIES_symbiyosys_formal ?=
FLOW_DEPENDENCIES_eqy_equivalence ?= yosys_synthesis
FLOW_DEPENDENCIES_verilator_sim ?=
FLOW_DEPENDENCIES_openroad ?=
FLOW_DEPENDENCIES_vcs_sim ?=
FLOW_DEPENDENCIES_vc_lint ?=
FLOW_DEPENDENCIES_vc_cdc ?=
FLOW_DEPENDENCIES_sg_cdc ?=
FLOW_DEPENDENCIES_sg_dft ?=
FLOW_DEPENDENCIES_vc_lp ?=
FLOW_DEPENDENCIES_synopsys_synthesis ?=
FLOW_DEPENDENCIES_synopsys_primetime ?= synopsys_synthesis
FLOW_DEPENDENCIES_synopsys_primepower ?= vcs_sim synopsys_synthesis
