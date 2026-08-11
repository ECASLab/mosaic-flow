if {[info exists env(TECH_SETUP_TCL)] && $env(TECH_SETUP_TCL) ne ""} {
  source $env(TECH_SETUP_TCL)
}

read_ddc $env(WORK_DIR)/synopsys_synthesis/$env(DESIGN_TOP).ddc
current_design $env(DESIGN_TOP)
read_sdc $env(WORK_DIR)/synopsys_synthesis/$env(DESIGN_TOP).sdc
read_saif $env(ACTIVITY_FILE) -instance_name $env(DUT_INSTANCE)
update_timing
update_power

file mkdir $env(REPORT_DIR)/synopsys_primepower
report_power -hierarchy > $env(REPORT_DIR)/synopsys_primepower/hierarchical_power.rpt
report_power > $env(REPORT_DIR)/synopsys_primepower/power.rpt
report_switching_activity > $env(REPORT_DIR)/synopsys_primepower/activity.rpt
exit
