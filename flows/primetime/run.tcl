if {[info exists env(TECH_SETUP_TCL)] && $env(TECH_SETUP_TCL) ne ""} {
  source $env(TECH_SETUP_TCL)
}

read_ddc $env(WORK_DIR)/synopsys_synthesis/$env(DESIGN_TOP).ddc
current_design $env(DESIGN_TOP)
read_sdc $env(WORK_DIR)/synopsys_synthesis/$env(DESIGN_TOP).sdc
update_timing

file mkdir $env(REPORT_DIR)/synopsys_primetime
check_timing -verbose > $env(REPORT_DIR)/synopsys_primetime/check_timing.rpt
report_global_timing > $env(REPORT_DIR)/synopsys_primetime/global_timing.rpt
report_timing -delay_type max -max_paths 20 > $env(REPORT_DIR)/synopsys_primetime/setup.rpt
report_timing -delay_type min -max_paths 20 > $env(REPORT_DIR)/synopsys_primetime/hold.rpt
report_constraint -all_violators > $env(REPORT_DIR)/synopsys_primetime/violations.rpt

set setup_violations [get_timing_paths -delay_type max -slack_lesser_than 0.0]
set hold_violations [get_timing_paths -delay_type min -slack_lesser_than 0.0]
if {[sizeof_collection $setup_violations] > 0 ||
    [sizeof_collection $hold_violations] > 0} {
  error "PrimeTime found setup or hold violations"
}
exit
