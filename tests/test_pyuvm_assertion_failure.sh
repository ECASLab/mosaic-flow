#!/usr/bin/env bash
set -euo pipefail

# A deliberately failing SVA must propagate through the simulator, cocotb, and
# flow wrapper while preserving machine-readable FAIL evidence.
flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="${flow_root}/tests/fixture-module"
report_root="${fixture_root}/reports/pyuvm_assertion_failure"
work_root="${fixture_root}/work/pyuvm_assertion_failure"

rm -rf "${report_root}" "${work_root}"

if make --no-print-directory -C "${fixture_root}" FLOW_ROOT="${flow_root}" \
    REPORT_DIR="${report_root}" WORK_DIR="${work_root}" \
    ASSERTION_FILELIST="${fixture_root}/filelists/pyuvm_failure_assertions.f" \
    open-pyuvm > "${fixture_root}/reports/pyuvm-assertion-failure.log" 2>&1; then
  echo "PyUVM accepted an injected SystemVerilog assertion failure" >&2
  exit 1
fi

status_file="${report_root}/pyuvm_open_source/status.txt"
if [[ ! -f "${status_file}" ]] || [[ "$(<"${status_file}")" != "FAIL" ]]; then
  echo "PyUVM did not retain FAIL status for the injected assertion" >&2
  exit 1
fi

if ! grep -Fq "INJECTED_ASSERTION_FAILURE" \
    "${report_root}/pyuvm_open_source/simulation.log"; then
  echo "PyUVM failure evidence does not identify the injected assertion" >&2
  exit 1
fi

echo "PyUVM rejected the injected SystemVerilog assertion failure"
