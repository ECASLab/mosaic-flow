#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

run_and_record synopsys_primetime "${PRIMETIME_BIN:-pt_shell}" -f \
  "${FLOW_ROOT}/flows/primetime/run.tcl"
