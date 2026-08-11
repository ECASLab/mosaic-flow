#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

flow_report_dir="${REPORT_DIR}/slang_elaboration"
flow_work_dir="${WORK_DIR}/slang_elaboration"
mkdir -p "${flow_report_dir}" "${flow_work_dir}"
printf 'FAIL\n' > "${flow_report_dir}/status.txt"

cd "${REPO_ROOT}"
"${SLANG_CMD:-slang}" -f "${RTL_FILELIST}" --top "${DESIGN_TOP}" --single-unit \
  2>&1 | tee "${flow_report_dir}/elaboration.log"
printf 'PASS\n' > "${flow_report_dir}/status.txt"
