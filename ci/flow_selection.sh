#!/usr/bin/env bash

flow_is_known() {
  local requested_flow="$1"
  local known_flow

  for known_flow in ${MOSAIC_FLOW_IDS:-}; do
    if [[ "${known_flow}" == "${requested_flow}" ]]; then
      return 0
    fi
  done

  return 1
}

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

flow_state() {
  local requested_flow="$1"
  local state_variable="FLOW_${requested_flow}"

  printf '%s\n' "${!state_variable:-}"
}

flow_dependencies() {
  local requested_flow="$1"
  local dependency_variable="FLOW_DEPENDENCIES_${requested_flow}"

  printf '%s\n' "${!dependency_variable:-}"
}

declare -A _MOSAIC_FLOW_VISIT_STATE=()

_mosaic_visit_flow_dependencies() {
  local flow_name="$1"
  local dependency
  local dependencies=()

  case "${_MOSAIC_FLOW_VISIT_STATE[${flow_name}]:-}" in
    visited) return 0 ;;
    visiting)
      echo "Flow dependency cycle detected at: ${flow_name}" >&2
      return 1
      ;;
  esac

  _MOSAIC_FLOW_VISIT_STATE["${flow_name}"]=visiting
  read -r -a dependencies <<< "$(flow_dependencies "${flow_name}")"
  for dependency in "${dependencies[@]}"; do
    _mosaic_visit_flow_dependencies "${dependency}" || return 1
  done
  _MOSAIC_FLOW_VISIT_STATE["${flow_name}"]=visited
}

validate_flow_configuration() {
  local flow_name
  local dependency
  local disabled_flow
  local state
  local dependencies=()

  if [[ -z "${MOSAIC_FLOW_IDS:-}" ]]; then
    echo "MOSAIC_FLOW_IDS is empty" >&2
    return 1
  fi

  for disabled_flow in ${DISABLED_FLOWS:-}; do
    if [[ "${disabled_flow}" != "cdc" ]] && ! flow_is_known "${disabled_flow}"; then
      echo "Unknown disabled flow: ${disabled_flow}" >&2
      return 1
    fi
  done

  for flow_name in ${MOSAIC_FLOW_IDS}; do
    state="$(flow_state "${flow_name}")"
    if [[ "${state}" != "enabled" && "${state}" != "disabled" ]]; then
      echo "Flow ${flow_name} must be enabled or disabled, found: ${state:-<empty>}" >&2
      return 1
    fi

    dependencies=()
    read -r -a dependencies <<< "$(flow_dependencies "${flow_name}")"
    for dependency in "${dependencies[@]}"; do
      if ! flow_is_known "${dependency}"; then
        echo "Flow ${flow_name} has unknown dependency: ${dependency}" >&2
        return 1
      fi
      if [[ "${dependency}" == "${flow_name}" ]]; then
        echo "Flow ${flow_name} cannot depend on itself" >&2
        return 1
      fi
      if ! flow_is_disabled "${flow_name}" && flow_is_disabled "${dependency}"; then
        echo "Enabled flow ${flow_name} depends on disabled flow ${dependency}" >&2
        return 1
      fi
    done
  done

  _MOSAIC_FLOW_VISIT_STATE=()
  for flow_name in ${MOSAIC_FLOW_IDS}; do
    _mosaic_visit_flow_dependencies "${flow_name}" || return 1
  done
}
