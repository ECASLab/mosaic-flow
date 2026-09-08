#!/usr/bin/env bash
set -euo pipefail

# Prove that formal, normal simulation, and PyUVM consume shared verification
# sources instead of silently maintaining flow-specific copies.
flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="${flow_root}/tests/fixture-module"
sim_work="${fixture_root}/work/verilator_sim"
pyuvm_work="${fixture_root}/work/pyuvm_open_source"

check_shared_sources() {
  # Check source selection in configuration and generated tool evidence.
  local filelist="$1"
  local formal_config="$2"
  local formal_log="$3"
  local source_kind="$4"

  local source_name

  while IFS= read -r source_path; do
    if [[ -z "${source_path}" || "${source_path}" == \#* ||
        "${source_path}" == +* || "${source_path}" == -* ]]; then
      continue
    fi

    source_name="$(basename "${source_path}")"
    if ! grep -Fq "${source_path}" "${formal_config}"; then
      echo "Formal configuration omits shared ${source_kind}: ${source_path}" >&2
      exit 1
    fi
    if ! grep -Fq "${source_name}" "${formal_log}"; then
      echo "Formal evidence omits shared ${source_kind}: ${source_name}" >&2
      exit 1
    fi
    if ! grep -RFq "${source_name}" "${sim_work}"; then
      echo "Normal simulation omits shared ${source_kind}: ${source_name}" >&2
      exit 1
    fi
    if ! grep -RFq "${source_name}" "${pyuvm_work}"; then
      echo "PyUVM omits shared ${source_kind}: ${source_name}" >&2
      exit 1
    fi
  done < "${filelist}"
}

property_paths=(
  "verif/properties/flow_fixture_sequences.svh"
  "verif/properties/flow_fixture_properties.svh"
)
property_header="$(basename "${property_paths[1]}")"

for wrapper in \
  "${fixture_root}/verif/assertions/flow_fixture_sva.sv" \
  "${fixture_root}/verif/coverage/flow_fixture_coverage.sv"; do
  if ! grep -Fq "\`include \"${property_header}\"" "${wrapper}"; then
    echo "Verification wrapper omits shared property library: ${wrapper}" >&2
    exit 1
  fi
done

for property_path in "${property_paths[@]}"; do
  property_name="$(basename "${property_path}")"

  for formal_config in \
    "${fixture_root}/config/formal.sby" \
    "${fixture_root}/config/formal_cover.sby"; do
    if ! grep -Fq "${property_path}" "${formal_config}"; then
      echo "Formal configuration omits shared property library: ${formal_config}" >&2
      exit 1
    fi
  done

  for evidence_root in \
    "${sim_work}" \
    "${pyuvm_work}" \
    "${fixture_root}/reports/symbiyosys_formal"; do
    if ! grep -RFq "${property_name}" "${evidence_root}"; then
      echo "Verification evidence omits shared property library: ${evidence_root}" >&2
      exit 1
    fi
  done
done

check_shared_sources \
  "${fixture_root}/filelists/assertions.f" \
  "${fixture_root}/config/formal.sby" \
  "${fixture_root}/reports/symbiyosys_formal/formal.log" \
  "assertion source"

check_shared_sources \
  "${fixture_root}/filelists/coverage.f" \
  "${fixture_root}/config/formal_cover.sby" \
  "${fixture_root}/reports/symbiyosys_formal/coverage.log" \
  "coverage source"

if grep -Eq 'verif/(properties|assertions|coverage)/' \
    "${fixture_root}/filelists/tb.f"; then
  echo "The normal testbench duplicates shared verification sources" >&2
  exit 1
fi

if grep -Eq '(^|[[:space:]])(assert|cover)([[:space:]]|\()' \
    "${fixture_root}/verif/formal/flow_fixture_formal.sv"; then
  echo "The formal harness duplicates shared assertions or coverage" >&2
  exit 1
fi

for coverage_report in \
  "${fixture_root}/reports/verilator_sim/coverage.dat" \
  "${fixture_root}/reports/verilator_sim/coverage.info" \
  "${fixture_root}/reports/pyuvm_open_source/coverage.dat" \
  "${fixture_root}/reports/pyuvm_open_source/coverage.info"; do
  if [[ ! -s "${coverage_report}" ]]; then
    echo "Missing simulator coverage evidence: ${coverage_report}" >&2
    exit 1
  fi
done

reached_covers="$(grep -Fc "Reached cover statement" \
  "${fixture_root}/reports/symbiyosys_formal/coverage.log")"
if [[ "${reached_covers}" -ne 4 ]]; then
  echo "Expected 4 formally reached covers, found ${reached_covers}" >&2
  exit 1
fi

echo "Shared properties, assertions, and coverage are present in formal, normal simulation, and PyUVM"
