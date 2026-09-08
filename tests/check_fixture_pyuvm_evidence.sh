#!/usr/bin/env bash
set -euo pipefail

# Validate the complete release-evidence contract after the positive fixture run.
flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
report_dir="${flow_root}/tests/fixture-module/reports/pyuvm_open_source"

required_files=(
  status.txt
  compile.log
  simulation.log
  results.xml
  functional-coverage.json
  coverage.dat
  coverage.info
  versions.log
)

for required_file in "${required_files[@]}"; do
  if [[ ! -s "${report_dir}/${required_file}" ]]; then
    echo "Missing PyUVM fixture evidence: ${required_file}" >&2
    exit 1
  fi
done

if [[ "$(<"${report_dir}/status.txt")" != "PASS" ]]; then
  echo "PyUVM fixture status is not PASS" >&2
  exit 1
fi
if ! grep -Fq "flow_fixture_sva.sv" "${report_dir}/coverage.info"; then
  echo "PyUVM coverage does not include the bound SystemVerilog assertions" >&2
  exit 1
fi
if ! grep -Fq 'failures="0"' "${report_dir}/results.xml"; then
  echo "PyUVM JUnit evidence does not report a clean test suite" >&2
  exit 1
fi

echo "PyUVM fixture evidence is complete"
