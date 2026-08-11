#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

if [[ ! -f "${ACTIVITY_FILE}" ]]; then
  echo "PrimePower requires ACTIVITY_FILE: ${ACTIVITY_FILE}" >&2
  exit 2
fi

run_and_record synopsys_primepower "${PRIMEPOWER_BIN:-pt_shell}" -f \
  "${FLOW_ROOT}/flows/primepower/run.tcl"
