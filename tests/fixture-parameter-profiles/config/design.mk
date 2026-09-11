export DESIGN_TOP := profile_fixture
export TB_TOP := $(DESIGN_TOP)_tb
export FORMAL_TOP := $(DESIGN_TOP)_formal
export DUT_INSTANCE := $(TB_TOP)/dut

export RTL_FILELIST := $(MODULE_ROOT)/filelists/rtl.f
export TB_FILELIST := $(MODULE_ROOT)/filelists/tb.f
export PYUVM_FILELIST := $(RTL_FILELIST)
export PYUVM_TOP := $(DESIGN_TOP)
export PYUVM_TEST_MODULE := test_profile_fixture
export PYUVM_TEST_PATH := $(MODULE_ROOT)/verif/pyuvm
export PYUVM_COVERAGE := disabled

export VERILATOR_WAIVER_FILE := $(MODULE_ROOT)/config/verilator_waivers.vlt
export VERIBLE_WAIVER_FILE := $(MODULE_ROOT)/config/verible_waivers.txt
export VERIBLE_RULES_FILE := $(MODULE_ROOT)/config/verible.rules
export FORMAL_CONFIG := $(MODULE_ROOT)/config/formal.sby
export EQUIVALENCE_CONFIG := $(MODULE_ROOT)/config/equivalence.eqy
export OPENROAD_CONFIG := $(MODULE_ROOT)/config/openroad.mk
export CONSTRAINT_DIR := $(MODULE_ROOT)/constraints
export PARAMETER_PROFILE_MANIFEST := $(MODULE_ROOT)/config/parameter-profiles.json
export REPORT_DIR := $(MODULE_ROOT)/reports
export WORK_DIR := $(MODULE_ROOT)/work
