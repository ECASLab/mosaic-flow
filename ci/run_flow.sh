#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=flow_selection.sh
source "${flow_root}/ci/flow_selection.sh"

if [[ "$#" -lt 2 ]]; then
  echo "Usage: run_flow.sh <flow-name> <command> [arguments...]" >&2
  exit 2
fi

flow_name="$1"
shift

if [[ ! "${flow_name}" =~ ^[a-z0-9_]+$ ]]; then
  echo "Invalid flow name: ${flow_name}" >&2
  exit 2
fi

if [[ "${FORCE_FLOW:-0}" != "1" ]] && flow_is_disabled "${flow_name}"; then
  flow_report_dir="${REPORT_DIR:-${MODULE_ROOT:-.}/reports}/${flow_name}"
  mkdir -p "${flow_report_dir}"
  printf 'SKIP\n' > "${flow_report_dir}/status.txt"
  printf 'Disabled by DISABLED_FLOWS\n' > "${flow_report_dir}/skip_reason.txt"
  echo "Skipping disabled flow: ${flow_name}"
  exit 0
fi

exec "$@"
