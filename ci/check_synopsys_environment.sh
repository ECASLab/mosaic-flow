#!/usr/bin/env bash
set -euo pipefail

required_commands=(
  "${SIM_BIN:-vcs}"
  "${VC_LINT_BIN:-vc_static_shell}"
  "${VC_CDC_BIN:-vc_static_shell}"
  "${SG_DFT_BIN:-sg_shell}"
  "${VC_LP_BIN:-vc_static_shell}"
  "${SYNTH_BIN:-dc_shell}"
  "${PRIMETIME_BIN:-pt_shell}"
  "${PRIMEPOWER_BIN:-pt_shell}"
)

missing=0
declare -A checked_commands=()
for command_name in "${required_commands[@]}"; do
  if [[ -n "${checked_commands[${command_name}]:-}" ]]; then
    continue
  fi
  checked_commands["${command_name}"]=1

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Missing Synopsys executable: ${command_name}" >&2
    missing=1
  fi
done

if [[ "${missing}" -ne 0 ]]; then
  echo "Configure the licensed local Synopsys environment before running this flow." >&2
  exit 2
fi

echo "Synopsys executables are available"
