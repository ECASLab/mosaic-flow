#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

flow_report_dir="${REPORT_DIR}/symbiyosys_formal"
flow_work_dir="${WORK_DIR}/symbiyosys_formal"
mkdir -p "${flow_report_dir}" "${flow_work_dir}"
printf 'FAIL\n' > "${flow_report_dir}/status.txt"

cd "${REPO_ROOT}" || exit 2
"${SBY_CMD:-sby}" -f -d "${flow_work_dir}" \
  "${FORMAL_CONFIG}" 2>&1 | tee "${flow_report_dir}/formal.log"
test -f "${flow_work_dir}/PASS"
printf 'PASS\n' > "${flow_report_dir}/status.txt"
