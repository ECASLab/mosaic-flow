#!/usr/bin/env bash
set -euo pipefail

required_flows=(vcs_sim vc_lint sg_dft vc_lp synopsys_synthesis synopsys_primetime synopsys_primepower)
cdc_flows=(vc_cdc sg_cdc)
failed=0

for flow_name in "${required_flows[@]}"; do
  status_file="${REPORT_DIR:-reports}/${flow_name}/status.txt"
  if [[ ! -f "${status_file}" ]] || [[ "$(<"${status_file}")" != "PASS" ]]; then
    echo "Missing or failing Synopsys result: ${flow_name}" >&2
    failed=1
  fi
done

cdc_passed=0
for flow_name in "${cdc_flows[@]}"; do
  status_file="${REPORT_DIR:-reports}/${flow_name}/status.txt"
  if [[ -f "${status_file}" ]] && [[ "$(<"${status_file}")" == "PASS" ]]; then
    cdc_passed=1
  fi
done

if [[ "${cdc_passed}" -ne 1 ]]; then
  echo "Neither VC CDC nor SpyGlass CDC has a passing result" >&2
  failed=1
fi

if [[ "${failed}" -ne 0 ]]; then
  exit 1
fi

echo "All required Synopsys checks passed"
