#!/usr/bin/env bash
set -euo pipefail

flow_report_dir="${REPORT_DIR}/static_intent"
mkdir -p "${flow_report_dir}"
printf 'FAIL\n' >"${flow_report_dir}/status.txt"

exec "${STATIC_INTENT_TOOL}" \
    --config "${STATIC_INTENT_CONFIG}" \
    --module-root "${MODULE_ROOT}" \
    --output-dir "${flow_report_dir}"
