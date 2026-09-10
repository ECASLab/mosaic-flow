# Import pinned versions before deriving cache paths or executable defaults.
include $(FLOW_ROOT)/config/tool-versions.env

# MOSAIC_TOOLS_ROOT: Shared installation/cache root. Override for a site-wide
# tool cache. The default follows XDG_CACHE_HOME and otherwise uses HOME/.cache.
MOSAIC_TOOLS_ROOT ?= $(if $(XDG_CACHE_HOME),$(XDG_CACHE_HOME),$(HOME)/.cache)/mosaic
# OSS_CAD_SUITE_ROOT: Derived root of the pinned OSS CAD Suite installation.
OSS_CAD_SUITE_ROOT := $(MOSAIC_TOOLS_ROOT)/oss-cad-suite/$(OSS_CAD_SUITE_VERSION)
# VERIBLE_ROOT: Derived root of the pinned Verible installation.
VERIBLE_ROOT := $(MOSAIC_TOOLS_ROOT)/verible/$(VERIBLE_VERSION)
# SLANG_ROOT: Derived root of the pinned Slang installation.
SLANG_ROOT := $(MOSAIC_TOOLS_ROOT)/slang/$(SLANG_VERSION)
# PYUVM_ROOT: Derived virtual-environment root. The environment revision permits
# cache invalidation when installation policy changes without a package update.
PYUVM_ROOT := $(MOSAIC_TOOLS_ROOT)/pyuvm/$(PYUVM_VERSION)-cocotb-$(COCOTB_VERSION)-env$(PYUVM_ENVIRONMENT_VERSION)

# Export the resolved cache root for installers and child flow processes.
export MOSAIC_TOOLS_ROOT
# PATH: Prefer pinned PyUVM, Verible, Slang, and OSS CAD Suite executables while
# retaining the caller's existing PATH for licensed and system tools.
export PATH := $(PYUVM_ROOT)/bin:$(VERIBLE_ROOT)/bin:$(SLANG_ROOT)/bin:$(OSS_CAD_SUITE_ROOT)/bin:$(PATH)

# SIMULATOR: Backend selected by the shared non-PyUVM simulation adapter.
export SIMULATOR ?=vcs
# SIM_BIN: VCS-compatible simulator executable used when SIMULATOR is vcs.
export SIM_BIN ?=vcs
# VERILATOR_CMD: Verilator executable used for lint and normal simulation.
export VERILATOR_CMD ?=verilator
# YOSYS_CMD: Yosys executable used for generic synthesis.
export YOSYS_CMD ?=yosys
# SBY_CMD: SymbiYosys executable used for formal proof and reachability.
export SBY_CMD ?=sby
# EQY_CMD: EQY executable used for RTL-to-netlist equivalence.
export EQY_CMD ?=eqy
# IVERILOG_CMD: Pinned OSS CAD Suite compiler used by four-state qualification.
export IVERILOG_CMD ?=iverilog
# VVP_CMD: Icarus runtime used by four-state qualification cases.
export VVP_CMD ?=vvp
# SLANG_CMD: Slang executable used for SystemVerilog elaboration.
export SLANG_CMD ?=slang
# VERIBLE_LINT_CMD: Verible executable used for syntax and style linting.
export VERIBLE_LINT_CMD ?=verible-verilog-lint
# VERIBLE_FORMAT_CMD: Verible executable used for formatting checks.
export VERIBLE_FORMAT_CMD ?=verible-verilog-format
# VERIBLE_FORMAT_ARGS: Optional whitespace-separated formatting policy arguments,
# such as --indentation_spaces=4, supplied by the selected module profile.
export VERIBLE_FORMAT_ARGS ?=
# VERIBLE_FORMAT_PATHS: Whitespace-separated module-owned files or directories
# checked by the formatter. Multi-module profiles should narrow the default paths.
export VERIBLE_FORMAT_PATHS ?=rtl verif
# OPENROAD_CMD: OpenROAD executable used by the physical implementation adapter.
export OPENROAD_CMD ?=openroad
# VC_LINT_BIN: VC SpyGlass executable used by the licensed lint adapter.
export VC_LINT_BIN ?=vc_static_shell
# VC_CDC_BIN: VC SpyGlass executable used by the licensed CDC adapter.
export VC_CDC_BIN ?=vc_static_shell
# SG_CDC_BIN: SpyGlass executable used by the alternate licensed CDC adapter.
export SG_CDC_BIN ?=sg_shell
# SG_DFT_BIN: SpyGlass executable used for design-for-test static checks.
export SG_DFT_BIN ?=sg_shell
# VC_LP_BIN: VC LP executable used for low-power intent checks.
export VC_LP_BIN ?=vc_static_shell
# SYNTH_BIN: Design Compiler executable used for technology-mapped synthesis.
export SYNTH_BIN ?=dc_shell
# PRIMETIME_BIN: PrimeTime executable used for static timing analysis.
export PRIMETIME_BIN ?=pt_shell
# PRIMEPOWER_BIN: PrimeTime/PrimePower executable used for power analysis.
export PRIMEPOWER_BIN ?=pt_shell

# PROPERTY_FILELIST: Optional list of include paths and reusable SystemVerilog
# sequence/property dependencies. Compiled before assertion and coverage lists.
export PROPERTY_FILELIST ?=
# ASSERTION_FILELIST: Optional ordered list of assertion modules and bind files.
export ASSERTION_FILELIST ?=
# COVERAGE_FILELIST: Optional ordered list of coverage modules and bind files.
export COVERAGE_FILELIST ?=
# FORMAL_COVER_CONFIG: SymbiYosys cover-mode configuration. Required when
# COVERAGE_FILELIST is nonempty and the formal flow is enabled.
export FORMAL_COVER_CONFIG ?=
# SIM_COVERAGE: Enable or disable native coverage for normal simulation.
# Accepted values are enabled and disabled.
export SIM_COVERAGE ?=enabled
# VERILATOR_COVERAGE_CMD: Utility used to export coverage.dat as coverage.info.
export VERILATOR_COVERAGE_CMD ?=verilator_coverage
# COVERAGE_QUALIFICATION_POLICY: Module-owned declarative coverage requirements.
export COVERAGE_QUALIFICATION_POLICY ?=$(MODULE_ROOT)/config/coverage-policy.json
# COVERAGE_QUALIFICATION_SOURCE: Existing evidence producer or dedicated rerun.
# Accepted values are verilator_sim, pyuvm_open_source, and dedicated.
export COVERAGE_QUALIFICATION_SOURCE ?=verilator_sim
# COVERAGE_QUALIFICATION_TOOL: Shared policy validator and evidence normalizer.
export COVERAGE_QUALIFICATION_TOOL ?=$(FLOW_ROOT)/ci/coverage_qualification.py
# QUALIFICATION_CAMPAIGN_MANIFEST: Module-owned negative and four-state case declarations.
export QUALIFICATION_CAMPAIGN_MANIFEST ?=$(MODULE_ROOT)/config/qualification-campaigns.json
# QUALIFICATION_CAMPAIGN_TOOL: Shared declarative campaign validator and runner.
export QUALIFICATION_CAMPAIGN_TOOL ?=$(FLOW_ROOT)/ci/qualification_campaign.py
# STATIC_INTENT_CONFIG: Module-owned SDC and UPF expectation policy.
export STATIC_INTENT_CONFIG ?=$(MODULE_ROOT)/config/static-intent.json
# STATIC_INTENT_TOOL: License-independent semantic SDC and UPF validator.
export STATIC_INTENT_TOOL ?=$(FLOW_ROOT)/ci/static_intent.py

# PYUVM_PYTHON: Python interpreter from the pinned PyUVM virtual environment.
export PYUVM_PYTHON ?=$(PYUVM_ROOT)/bin/python
# PYUVM_OPEN_SIMULATOR: Open-source cocotb backend. Supported values are
# verilator and icarus; Verilator is the qualified default.
export PYUVM_OPEN_SIMULATOR ?=verilator
# PYUVM_COMMERCIAL_SIMULATOR: Licensed cocotb backend. Supported values are vcs
# and xcelium.
export PYUVM_COMMERCIAL_SIMULATOR ?=vcs
# PYUVM_TEST_MODULE: Importable Python module containing the PyUVM test classes.
export PYUVM_TEST_MODULE ?=
# PYUVM_FILELIST: DUT/source filelist for PyUVM compilation. Shared properties,
# assertions, and coverage are appended from their dedicated filelists.
export PYUVM_FILELIST ?=$(RTL_FILELIST)
# PYUVM_TOP: HDL top exposed to cocotb; defaults to the synthesizable design top.
export PYUVM_TOP ?=$(DESIGN_TOP)
# PYUVM_TEST_PATH: Directory prepended to PYTHONPATH for test module discovery.
export PYUVM_TEST_PATH ?=$(MODULE_ROOT)/verif/pyuvm
# PYUVM_TESTCASE: Optional single PyUVM test class selected for execution.
export PYUVM_TESTCASE ?=
# PYUVM_COMPILE_ARGS: Optional shell-parsed arguments appended during HDL build.
export PYUVM_COMPILE_ARGS ?=
# PYUVM_RUN_ARGS: Optional shell-parsed arguments appended during simulation.
export PYUVM_RUN_ARGS ?=
# PYUVM_PLUSARGS: Optional shell-parsed HDL plusargs passed to the simulator.
export PYUVM_PLUSARGS ?=
# PYUVM_COVERAGE: Enable or disable simulator-native coverage collection.
# Accepted values are enabled and disabled.
export PYUVM_COVERAGE ?=enabled
# PYUVM_WAVES: Enable or disable simulator waveform generation.
# Accepted values are enabled and disabled.
export PYUVM_WAVES ?=disabled
