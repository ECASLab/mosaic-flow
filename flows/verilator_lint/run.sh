#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

flow_report_dir="${REPORT_DIR}/verilator_lint"
flow_work_dir="${WORK_DIR}/verilator_lint"
mkdir -p "${flow_report_dir}" "${flow_work_dir}"
printf 'FAIL\n' > "${flow_report_dir}/status.txt"

"${VERILATOR_CMD:-verilator}" --lint-only --sv --Wall \
  --top-module "${DESIGN_TOP}" "${VERILATOR_WAIVER_FILE}" \
  -f "${RTL_FILELIST}" 2>&1 | tee "${flow_report_dir}/lint.log"

printf 'PASS\n' > "${flow_report_dir}/status.txt"
