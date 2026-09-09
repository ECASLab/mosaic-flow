export DESIGN_TOP := beta
export TB_TOP := $(DESIGN_TOP)_tb
export FORMAL_TOP := $(DESIGN_TOP)_formal
export DUT_INSTANCE := $(TB_TOP)/dut

export RTL_FILELIST := $(call mosaic_resolve_filelist,rtl.f)
export TB_FILELIST := $(call mosaic_resolve_filelist,tb.f)
export FORMAL_CONFIG := $(call mosaic_resolve_flow_config,symbiyosys,formal.sby)
export CONSTRAINT_DIR := $(MODULE_ROOT)/constraints

export VERIBLE_FORMAT_PATHS := rtl/beta.sv
