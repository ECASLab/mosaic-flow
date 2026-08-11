include $(FLOW_ROOT)/config/tool-versions.env

MOSAIC_TOOLS_ROOT ?= $(if $(XDG_CACHE_HOME),$(XDG_CACHE_HOME),$(HOME)/.cache)/mosaic
OSS_CAD_SUITE_ROOT := $(MOSAIC_TOOLS_ROOT)/oss-cad-suite/$(OSS_CAD_SUITE_VERSION)
VERIBLE_ROOT := $(MOSAIC_TOOLS_ROOT)/verible/$(VERIBLE_VERSION)
SLANG_ROOT := $(MOSAIC_TOOLS_ROOT)/slang/$(SLANG_VERSION)

export MOSAIC_TOOLS_ROOT
export PATH := $(VERIBLE_ROOT)/bin:$(SLANG_ROOT)/bin:$(OSS_CAD_SUITE_ROOT)/bin:$(PATH)

export SIMULATOR ?=vcs
export SIM_BIN ?=vcs
export VERILATOR_CMD ?=verilator
export YOSYS_CMD ?=yosys
export SBY_CMD ?=sby
export EQY_CMD ?=eqy
export SLANG_CMD ?=slang
export VERIBLE_LINT_CMD ?=verible-verilog-lint
export VERIBLE_FORMAT_CMD ?=verible-verilog-format
export OPENROAD_CMD ?=openroad
export VC_LINT_BIN ?=vc_static_shell
export VC_CDC_BIN ?=vc_static_shell
export SG_CDC_BIN ?=sg_shell
export SG_DFT_BIN ?=sg_shell
export VC_LP_BIN ?=vc_static_shell
export SYNTH_BIN ?=dc_shell
export PRIMETIME_BIN ?=pt_shell
export PRIMEPOWER_BIN ?=pt_shell
