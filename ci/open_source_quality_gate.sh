#!/usr/bin/env bash
set -euo pipefail

required_flows=(verible_lint verible_format slang_elaboration verilator_lint yosys_synthesis symbiyosys_formal eqy_equivalence verilator_sim)
failed=0

for flow_name in "${required_flows[@]}"; do
  status_file="${REPORT_DIR:-reports}/${flow_name}/status.txt"
  if [[ ! -f "${status_file}" ]] || [[ "$(<"${status_file}")" != "PASS" ]]; then
    echo "Missing or failing open-source result: ${flow_name}" >&2
    failed=1
  fi
done

if [[ "${failed}" -ne 0 ]]; then
  exit 1
fi

echo "All required open-source checks passed"
