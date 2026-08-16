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

"${flow_root}/ci/check_flow_config.sh" --quiet

if ! flow_is_known "${flow_name}"; then
  echo "Unknown flow: ${flow_name}" >&2
  exit 2
fi

flow_report_dir="${REPORT_DIR:-${MODULE_ROOT:-.}/reports}/${flow_name}"
mkdir -p "${flow_report_dir}"

if [[ "${FORCE_FLOW:-0}" != "1" ]] && flow_is_disabled "${flow_name}"; then
  rm -f "${flow_report_dir}/block_reason.txt"
  printf 'SKIP\n' > "${flow_report_dir}/status.txt"
  printf 'Disabled by DISABLED_FLOWS\n' > "${flow_report_dir}/skip_reason.txt"
  echo "Skipping disabled flow: ${flow_name}"
  exit 0
fi

dependencies=()
read -r -a dependencies <<< "$(flow_dependencies "${flow_name}")"
for dependency in "${dependencies[@]}"; do
  dependency_status_file="${REPORT_DIR:-${MODULE_ROOT:-.}/reports}/${dependency}/status.txt"
  dependency_status=MISSING
  if [[ -f "${dependency_status_file}" ]]; then
    dependency_status="$(<"${dependency_status_file}")"
  fi

  if [[ "${dependency_status}" != "PASS" ]]; then
    rm -f "${flow_report_dir}/skip_reason.txt"
    printf 'BLOCKED\n' > "${flow_report_dir}/status.txt"
    printf 'Dependency %s must be PASS, found %s\n' \
      "${dependency}" "${dependency_status}" > "${flow_report_dir}/block_reason.txt"
    echo "Blocking ${flow_name}: dependency ${dependency} is ${dependency_status}" >&2
    exit 1
  fi
done

rm -f "${flow_report_dir}/status.txt" \
  "${flow_report_dir}/skip_reason.txt" \
  "${flow_report_dir}/block_reason.txt"
exec "$@"
