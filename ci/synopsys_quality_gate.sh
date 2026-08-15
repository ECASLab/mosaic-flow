#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=flow_selection.sh
source "${flow_root}/ci/flow_selection.sh"

case "${CDC_TOOL:-vc}" in
  vc | sg) selected_cdc="${CDC_TOOL:-vc}_cdc" ;;
  *)
    echo "CDC_TOOL must be vc or sg" >&2
    exit 2
    ;;
esac

required_flows=(vcs_sim vc_lint "${selected_cdc}" sg_dft vc_lp synopsys_synthesis synopsys_primetime synopsys_primepower)
failed=0

for flow_name in "${required_flows[@]}"; do
  status_file="${REPORT_DIR:-reports}/${flow_name}/status.txt"
  expected_status=PASS
  if flow_is_disabled "${flow_name}"; then
    expected_status=SKIP
  fi

  if [[ ! -f "${status_file}" ]] || [[ "$(<"${status_file}")" != "${expected_status}" ]]; then
    echo "Synopsys result ${flow_name} must be ${expected_status}" >&2
    failed=1
  fi
done

if [[ "${failed}" -ne 0 ]]; then
  exit 1
fi

echo "All enabled Synopsys checks passed"
