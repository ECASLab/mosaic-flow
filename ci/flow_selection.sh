#!/usr/bin/env bash

flow_is_disabled() {
  local requested_flow="$1"
  local disabled_flow

  for disabled_flow in ${DISABLED_FLOWS:-}; do
    if [[ "${disabled_flow}" == "${requested_flow}" ]]; then
      return 0
    fi

    if [[ "${disabled_flow}" == "cdc" ]] &&
       [[ "${requested_flow}" == "vc_cdc" || "${requested_flow}" == "sg_cdc" ]]; then
      return 0
    fi
  done

  return 1
}
