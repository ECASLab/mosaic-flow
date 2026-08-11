#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

run_and_record synopsys_synthesis "${SYNTH_BIN:-dc_shell}" -f \
  "${FLOW_ROOT}/flows/synthesis/run.tcl"
