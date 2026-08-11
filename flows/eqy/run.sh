#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

flow_report_dir="${REPORT_DIR}/eqy_equivalence"
flow_work_dir="${WORK_DIR}/eqy_equivalence"
mkdir -p "${flow_report_dir}" "${flow_work_dir}"
printf 'FAIL\n' > "${flow_report_dir}/status.txt"

cd "${REPO_ROOT}" || exit 2
"${EQY_CMD:-eqy}" -f -d "${flow_work_dir}" \
  "${EQUIVALENCE_CONFIG}" 2>&1 | tee "${flow_report_dir}/equivalence.log"
test -f "${flow_work_dir}/PASS"
printf 'PASS\n' > "${flow_report_dir}/status.txt"
