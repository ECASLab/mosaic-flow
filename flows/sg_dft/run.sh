#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

run_and_record sg_dft "${SG_DFT_BIN:-sg_shell}" \
  -tcl "${FLOW_ROOT}/flows/sg_dft/run.tcl"
