#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=flow_selection.sh
source "${flow_root}/ci/flow_selection.sh"

case "${CDC_TOOL:-vc}" in
  vc)
    cdc_flow=vc_cdc
    cdc_command="${VC_CDC_BIN:-vc_static_shell}"
    ;;
  sg)
    cdc_flow=sg_cdc
    cdc_command="${SG_CDC_BIN:-sg_shell}"
    ;;
  *)
    echo "CDC_TOOL must be vc or sg" >&2
    exit 2
    ;;
esac

missing=0
declare -A checked_commands=()
check_command() {
  local flow_name="$1"
  local command_name="$2"

  if flow_is_disabled "${flow_name}"; then
    return
  fi

  if [[ -n "${checked_commands[${command_name}]:-}" ]]; then
    return
  fi
  checked_commands["${command_name}"]=1

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Missing executable for ${flow_name}: ${command_name}" >&2
    missing=1
  fi
}

check_command vcs_sim "${SIM_BIN:-vcs}"
check_command vc_lint "${VC_LINT_BIN:-vc_static_shell}"
check_command "${cdc_flow}" "${cdc_command}"
check_command sg_dft "${SG_DFT_BIN:-sg_shell}"
check_command vc_lp "${VC_LP_BIN:-vc_static_shell}"
check_command synopsys_synthesis "${SYNTH_BIN:-dc_shell}"
check_command synopsys_primetime "${PRIMETIME_BIN:-pt_shell}"
check_command synopsys_primepower "${PRIMEPOWER_BIN:-pt_shell}"

if [[ "${missing}" -ne 0 ]]; then
  echo "Configure the licensed local Synopsys environment before running this flow." >&2
  exit 2
fi

echo "Synopsys executables are available"
