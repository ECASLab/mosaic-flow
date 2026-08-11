#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

run_and_record vc_lint "${VC_LINT_BIN:-vc_static_shell}" -mode lint \
  -f "${FLOW_ROOT}/flows/vc_lint/run.tcl"
