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
