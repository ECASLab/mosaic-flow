export DESIGN_NAME = flow_fixture
export PLATFORM = $(OPENROAD_PLATFORM)
export VERILOG_FILES = $(REPO_ROOT)/rtl/flow_fixture.sv
export SDC_FILE = $(REPO_ROOT)/constraints/openroad.sdc
export DIE_AREA = 0 0 60 60
export CORE_AREA = 5 5 55 55
export SKIP_CTS_REPAIR_TIMING = 1
