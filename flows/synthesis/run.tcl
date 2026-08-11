if {[info exists env(TECH_SETUP_TCL)] && $env(TECH_SETUP_TCL) ne ""} {
  source $env(TECH_SETUP_TCL)
}

set_svf $env(WORK_DIR)/synopsys_synthesis/$env(DESIGN_TOP).svf
analyze -format sverilog -vcs "-f $env(RTL_FILELIST)"
elaborate $env(DESIGN_TOP)
current_design $env(DESIGN_TOP)
link
source $env(CONSTRAINT_DIR)/timing.sdc
check_design
compile_ultra

file mkdir $env(REPORT_DIR)/synopsys_synthesis
report_qor > $env(REPORT_DIR)/synopsys_synthesis/qor.rpt
report_area -hierarchy > $env(REPORT_DIR)/synopsys_synthesis/area.rpt
report_timing -max_paths 20 > $env(REPORT_DIR)/synopsys_synthesis/timing.rpt
report_power > $env(REPORT_DIR)/synopsys_synthesis/power.rpt
write -format ddc -hierarchy -output $env(WORK_DIR)/synopsys_synthesis/$env(DESIGN_TOP).ddc
write -format verilog -hierarchy -output $env(WORK_DIR)/synopsys_synthesis/$env(DESIGN_TOP)_netlist.v
write_sdc $env(WORK_DIR)/synopsys_synthesis/$env(DESIGN_TOP).sdc
exit
