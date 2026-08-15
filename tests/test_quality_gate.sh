#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
report_root="$(mktemp -d)"
trap 'rm -rf "${report_root}"' EXIT

fixture_root="${flow_root}/tests/fixture-module"
flow_config_output="$(make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" \
  FLOW_symbiyosys_formal=disabled flow-config-check)"
if ! grep -q 'Disabled flows: symbiyosys_formal' <<< "${flow_config_output}"; then
  echo "Module flow configuration did not override the shared default" >&2
  exit 1
fi

if make -s -C "${fixture_root}" FLOW_ROOT="${flow_root}" \
   FLOW_symbiyosys_formal=invalid flow-config-check >/dev/null 2>&1; then
  echo "Flow configuration accepted an invalid state" >&2
  exit 1
fi

required_flows=(verible_lint verible_format slang_elaboration verilator_lint yosys_synthesis symbiyosys_formal eqy_equivalence verilator_sim)
for flow_name in "${required_flows[@]}"; do
  mkdir -p "${report_root}/${flow_name}"
  printf 'PASS\n' > "${report_root}/${flow_name}/status.txt"
done

REPORT_DIR="${report_root}" "${flow_root}/ci/open_source_quality_gate.sh" >/dev/null

printf 'FAIL\n' > "${report_root}/verilator_lint/status.txt"
if REPORT_DIR="${report_root}" "${flow_root}/ci/open_source_quality_gate.sh" >/dev/null 2>&1; then
  echo "Quality gate accepted a failing flow" >&2
  exit 1
fi

printf 'PASS\n' > "${report_root}/verilator_lint/status.txt"
printf 'SKIP\n' > "${report_root}/symbiyosys_formal/status.txt"
DISABLED_FLOWS=symbiyosys_formal REPORT_DIR="${report_root}" \
  "${flow_root}/ci/open_source_quality_gate.sh" >/dev/null

if REPORT_DIR="${report_root}" "${flow_root}/ci/open_source_quality_gate.sh" >/dev/null 2>&1; then
  echo "Quality gate accepted an unauthorized skipped flow" >&2
  exit 1
fi

printf 'PASS\n' > "${report_root}/symbiyosys_formal/status.txt"
if DISABLED_FLOWS=symbiyosys_formal REPORT_DIR="${report_root}" \
   "${flow_root}/ci/open_source_quality_gate.sh" >/dev/null 2>&1; then
  echo "Quality gate accepted PASS instead of explicit SKIP for a disabled flow" >&2
  exit 1
fi

rm -rf "${report_root}/symbiyosys_formal"
DISABLED_FLOWS=symbiyosys_formal REPORT_DIR="${report_root}" MODULE_ROOT="${report_root}" \
  "${flow_root}/ci/run_flow.sh" symbiyosys_formal false >/dev/null
if [[ "$(<"${report_root}/symbiyosys_formal/status.txt")" != "SKIP" ]]; then
  echo "Disabled flow runner did not record SKIP" >&2
  exit 1
fi

commercial_flows=(vcs_sim vc_lint vc_cdc sg_dft vc_lp synopsys_synthesis synopsys_primetime synopsys_primepower)
for flow_name in "${commercial_flows[@]}"; do
  mkdir -p "${report_root}/${flow_name}"
  printf 'PASS\n' > "${report_root}/${flow_name}/status.txt"
done

CDC_TOOL=vc REPORT_DIR="${report_root}" "${flow_root}/ci/synopsys_quality_gate.sh" >/dev/null

printf 'SKIP\n' > "${report_root}/vc_cdc/status.txt"
DISABLED_FLOWS=cdc CDC_TOOL=vc REPORT_DIR="${report_root}" \
  "${flow_root}/ci/synopsys_quality_gate.sh" >/dev/null

all_commercial_flows="vcs_sim vc_lint cdc sg_dft vc_lp synopsys_synthesis synopsys_primetime synopsys_primepower"
DISABLED_FLOWS="${all_commercial_flows}" CDC_TOOL=vc \
SIM_BIN=missing-vcs VC_LINT_BIN=missing-lint VC_CDC_BIN=missing-cdc \
SG_DFT_BIN=missing-dft VC_LP_BIN=missing-lp SYNTH_BIN=missing-synth \
PRIMETIME_BIN=missing-sta PRIMEPOWER_BIN=missing-power \
  "${flow_root}/ci/check_synopsys_environment.sh" >/dev/null
