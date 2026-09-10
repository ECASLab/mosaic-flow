# MOSAIC_FLOW_IDS: Ordered registry of every flow known to the shared Make API.
# Add an ID here only when its FLOW_<id>, FLOW_DEPENDENCIES_<id>, target, and
# quality-gate policy are also defined.
MOSAIC_FLOW_IDS := \
	verible_lint \
	verible_format \
	slang_elaboration \
	verilator_lint \
	yosys_synthesis \
	symbiyosys_formal \
	eqy_equivalence \
	verilator_sim \
	pyuvm_open_source \
	coverage_qualification \
	openroad \
	vcs_sim \
	pyuvm_commercial \
	vc_lint \
	vc_cdc \
	sg_cdc \
	sg_dft \
	vc_lp \
	synopsys_synthesis \
	synopsys_primetime \
	synopsys_primepower

# FLOW_<id> variables accept enabled or disabled. These defaults are deliberately
# overridable from $(MODULE_ROOT)/config/flows.mk or the make command line.

# FLOW_verible_lint: Run Verible syntax and style linting.
FLOW_verible_lint ?= enabled
# FLOW_verible_format: Check SystemVerilog formatting without modifying sources.
FLOW_verible_format ?= enabled
# FLOW_slang_elaboration: Elaborate the RTL hierarchy with Slang.
FLOW_slang_elaboration ?= enabled
# FLOW_verilator_lint: Run Verilator structural and semantic linting.
FLOW_verilator_lint ?= enabled
# FLOW_yosys_synthesis: Run generic, technology-independent Yosys synthesis.
FLOW_yosys_synthesis ?= enabled
# FLOW_symbiyosys_formal: Run formal proof and configured cover reachability.
FLOW_symbiyosys_formal ?= enabled
# FLOW_eqy_equivalence: Compare RTL with the Yosys-generated netlist using EQY.
FLOW_eqy_equivalence ?= enabled
# FLOW_verilator_sim: Run the module-owned SystemVerilog testbench with Verilator.
FLOW_verilator_sim ?= enabled
# FLOW_pyuvm_open_source: Run PyUVM through Verilator or Icarus when opted in.
FLOW_pyuvm_open_source ?= disabled
# FLOW_coverage_qualification: Enforce module-owned HDL and formal coverage policy.
FLOW_coverage_qualification ?= disabled
# FLOW_openroad: Run optional PDK-backed physical implementation with OpenROAD.
FLOW_openroad ?= enabled
# FLOW_vcs_sim: Run the module-owned SystemVerilog testbench with VCS.
FLOW_vcs_sim ?= enabled
# FLOW_pyuvm_commercial: Run PyUVM through VCS or Xcelium when opted in.
FLOW_pyuvm_commercial ?= disabled
# FLOW_vc_lint: Run licensed Synopsys VC SpyGlass RTL linting.
FLOW_vc_lint ?= enabled
# FLOW_vc_cdc: Run licensed Synopsys VC SpyGlass clock-domain-crossing checks.
FLOW_vc_cdc ?= enabled
# FLOW_sg_cdc: Run licensed SpyGlass CDC as the alternate CDC backend.
FLOW_sg_cdc ?= enabled
# FLOW_sg_dft: Run licensed SpyGlass design-for-test static checks.
FLOW_sg_dft ?= enabled
# FLOW_vc_lp: Run licensed VC LP checks against the module power intent.
FLOW_vc_lp ?= enabled
# FLOW_synopsys_synthesis: Run technology-mapped synthesis with Design Compiler.
FLOW_synopsys_synthesis ?= enabled
# FLOW_synopsys_primetime: Run static timing analysis with PrimeTime.
FLOW_synopsys_primetime ?= enabled
# FLOW_synopsys_primepower: Run activity-based power analysis with PrimePower.
FLOW_synopsys_primepower ?= enabled

# FLOW_DEPENDENCIES_<id> variables contain space-separated canonical flow IDs.
# The Make API executes those prerequisite targets first. Modules may replace a
# list when their artifact graph differs from the shared default.

# FLOW_DEPENDENCIES_verible_lint: Verible lint has no artifact prerequisite.
FLOW_DEPENDENCIES_verible_lint ?=
# FLOW_DEPENDENCIES_verible_format: Formatting is source-only and independent.
FLOW_DEPENDENCIES_verible_format ?=
# FLOW_DEPENDENCIES_slang_elaboration: Slang elaborates source files directly.
FLOW_DEPENDENCIES_slang_elaboration ?=
# FLOW_DEPENDENCIES_verilator_lint: Verilator lint reads source files directly.
FLOW_DEPENDENCIES_verilator_lint ?=
# FLOW_DEPENDENCIES_yosys_synthesis: Generic synthesis reads RTL directly.
FLOW_DEPENDENCIES_yosys_synthesis ?=
# FLOW_DEPENDENCIES_symbiyosys_formal: Formal tasks own their source harnesses.
FLOW_DEPENDENCIES_symbiyosys_formal ?=
# FLOW_DEPENDENCIES_eqy_equivalence: EQY requires the Yosys-generated netlist.
FLOW_DEPENDENCIES_eqy_equivalence ?= yosys_synthesis
# FLOW_DEPENDENCIES_verilator_sim: Verilator simulation builds from source.
FLOW_DEPENDENCIES_verilator_sim ?=
# FLOW_DEPENDENCIES_pyuvm_open_source: PyUVM builds its simulator model itself.
FLOW_DEPENDENCIES_pyuvm_open_source ?=
# FLOW_DEPENDENCIES_coverage_qualification: Normal simulation produces the
# default native coverage source. Override this with pyuvm_open_source when
# COVERAGE_QUALIFICATION_SOURCE selects PyUVM, or clear it for a dedicated run.
FLOW_DEPENDENCIES_coverage_qualification ?= verilator_sim
# FLOW_DEPENDENCIES_openroad: OpenROAD owns its build graph by default.
FLOW_DEPENDENCIES_openroad ?=
# FLOW_DEPENDENCIES_vcs_sim: VCS simulation builds from source.
FLOW_DEPENDENCIES_vcs_sim ?=
# FLOW_DEPENDENCIES_pyuvm_commercial: Commercial PyUVM builds its own model.
FLOW_DEPENDENCIES_pyuvm_commercial ?=
# FLOW_DEPENDENCIES_vc_lint: VC Lint reads source and module configuration.
FLOW_DEPENDENCIES_vc_lint ?=
# FLOW_DEPENDENCIES_vc_cdc: VC CDC reads source and CDC intent directly.
FLOW_DEPENDENCIES_vc_cdc ?=
# FLOW_DEPENDENCIES_sg_cdc: SpyGlass CDC reads source and CDC intent directly.
FLOW_DEPENDENCIES_sg_cdc ?=
# FLOW_DEPENDENCIES_sg_dft: SpyGlass DFT reads source and DFT intent directly.
FLOW_DEPENDENCIES_sg_dft ?=
# FLOW_DEPENDENCIES_vc_lp: VC LP reads source and UPF directly.
FLOW_DEPENDENCIES_vc_lp ?=
# FLOW_DEPENDENCIES_synopsys_synthesis: Design Compiler reads RTL directly.
FLOW_DEPENDENCIES_synopsys_synthesis ?=
# FLOW_DEPENDENCIES_synopsys_primetime: PrimeTime requires the DC netlist.
FLOW_DEPENDENCIES_synopsys_primetime ?= synopsys_synthesis
# FLOW_DEPENDENCIES_synopsys_primepower: Power needs VCS activity and a DC netlist.
FLOW_DEPENDENCIES_synopsys_primepower ?= vcs_sim synopsys_synthesis
