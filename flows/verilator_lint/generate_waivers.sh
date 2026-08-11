#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

flow_report_dir="${REPORT_DIR}/verilator_lint"
mkdir -p "${flow_report_dir}"
draft_file="${flow_report_dir}/suggested_waivers.vlt"

"${VERILATOR_CMD:-verilator}" --lint-only --sv --Wall -Wno-fatal \
  --waiver-output "${draft_file}" --top-module "${DESIGN_TOP}" \
  -f "${RTL_FILELIST}" 2>&1 | tee "${flow_report_dir}/waiver_generation.log"

echo "Review ${draft_file}. Copy only justified entries to ${VERILATOR_WAIVER_FILE}."
