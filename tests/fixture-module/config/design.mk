export DESIGN_TOP := flow_fixture
export TB_TOP := $(DESIGN_TOP)_tb
export FORMAL_TOP := $(DESIGN_TOP)_formal
export DUT_INSTANCE := $(TB_TOP)/dut
export RTL_FILELIST := $(CURDIR)/filelists/rtl.f
export TB_FILELIST := $(CURDIR)/filelists/tb.f

# Keep reusable temporal declarations, checking, and coverage independently
# selectable while preserving their required compilation order.
export PROPERTY_FILELIST := $(CURDIR)/filelists/properties.f
export ASSERTION_FILELIST := $(CURDIR)/filelists/assertions.f
export COVERAGE_FILELIST := $(CURDIR)/filelists/coverage.f

# The PyUVM fixture drives the synthesizable DUT directly. Assertions and
# coverage are appended by the shared adapter from the filelists above.
export PYUVM_FILELIST := $(CURDIR)/filelists/rtl.f
export PYUVM_TOP := $(DESIGN_TOP)
export PYUVM_TEST_MODULE := test_flow_fixture
export PYUVM_TEST_PATH := $(CURDIR)/verif/pyuvm
export PYUVM_COVERAGE := enabled
export VERILATOR_WAIVER_FILE := $(CURDIR)/config/verilator_waivers.vlt
export VERIBLE_WAIVER_FILE := $(CURDIR)/config/verible_waivers.txt
export VERIBLE_RULES_FILE := $(CURDIR)/config/verible.rules

# Proof and cover reachability use separate SymbiYosys tasks.
export FORMAL_CONFIG := $(CURDIR)/config/formal.sby
export FORMAL_COVER_CONFIG := $(CURDIR)/config/formal_cover.sby
export COVERAGE_QUALIFICATION_POLICY := $(CURDIR)/config/coverage-policy.json
export COVERAGE_QUALIFICATION_SOURCE := verilator_sim
export EQUIVALENCE_CONFIG := $(CURDIR)/config/equivalence.eqy
export OPENROAD_CONFIG := $(CURDIR)/config/openroad.mk
export CONSTRAINT_DIR := $(CURDIR)/constraints
export REPORT_DIR := $(CURDIR)/reports
export WORK_DIR := $(CURDIR)/work
export ACTIVITY_FILE ?=$(WORK_DIR)/vcs_sim/$(DESIGN_TOP).saif
