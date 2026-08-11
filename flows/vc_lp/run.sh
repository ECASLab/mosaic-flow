#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

run_and_record vc_lp "${VC_LP_BIN:-vc_static_shell}" -mode lp \
  -f "${FLOW_ROOT}/flows/vc_lp/run.tcl"
