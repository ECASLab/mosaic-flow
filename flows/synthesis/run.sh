#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

export PROFILE_DC_PARAMETERS=""
if [[ "${MOSAIC_PROFILE_ACTIVE:-disabled}" == "enabled" ]]; then
  PROFILE_DC_PARAMETERS="$(
    python3 "${PARAMETER_PROFILE_TOOL}" arguments \
      --parameters "${PROFILE_PARAMETERS_JSON}" --backend dc \
      --top "${DESIGN_TOP}"
  )"
  export PROFILE_DC_PARAMETERS
fi

run_and_record synopsys_synthesis "${SYNTH_BIN:-dc_shell}" -f \
  "${FLOW_ROOT}/flows/synthesis/run.tcl"
