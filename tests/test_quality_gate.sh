#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
report_root="$(mktemp -d)"
trap 'rm -rf "${report_root}"' EXIT

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
