#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

cdc_tool="${1:-vc}"
case "${cdc_tool}" in
  vc)
    run_and_record vc_cdc "${VC_CDC_BIN:-vc_static_shell}" -mode cdc \
      -f "${FLOW_ROOT}/flows/cdc/vc_run.tcl"
    ;;
  sg)
    run_and_record sg_cdc "${SG_CDC_BIN:-sg_shell}" \
      -tcl "${FLOW_ROOT}/flows/cdc/sg_run.tcl"
    ;;
  *)
    echo "Unsupported CDC tool: ${cdc_tool}. Use vc or sg." >&2
    exit 2
    ;;
esac
