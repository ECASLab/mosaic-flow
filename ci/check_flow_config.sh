#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=flow_selection.sh
source "${flow_root}/ci/flow_selection.sh"

if [[ "$#" -gt 1 ]] || [[ "$#" -eq 1 && "$1" != "--quiet" ]]; then
  echo "Usage: check_flow_config.sh [--quiet]" >&2
  exit 2
fi

validate_flow_configuration

if [[ "${1:-}" == "--quiet" ]]; then
  exit 0
fi

enabled_flows=()
disabled_flows=()
for flow_name in ${MOSAIC_FLOW_IDS}; do
  if flow_is_disabled "${flow_name}"; then
    disabled_flows+=("${flow_name}")
  else
    enabled_flows+=("${flow_name}")
  fi
done

printf 'Enabled flows: %s\n' "${enabled_flows[*]}"
printf 'Disabled flows: %s\n' "${disabled_flows[*]}"
echo "Flow dependencies:"
for flow_name in ${MOSAIC_FLOW_IDS}; do
  dependencies="$(flow_dependencies "${flow_name}")"
  if [[ -n "${dependencies}" ]]; then
    printf '  %s: %s\n' "${flow_name}" "${dependencies}"
  fi
done
