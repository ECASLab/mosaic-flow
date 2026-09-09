#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

flow_report_dir="${REPORT_DIR}/verilator_lint"
flow_work_dir="${WORK_DIR}/verilator_lint"
mkdir -p "${flow_report_dir}" "${flow_work_dir}"
printf 'FAIL\n' > "${flow_report_dir}/status.txt"

parameter_args=()
if [[ "${MOSAIC_PROFILE_ACTIVE:-disabled}" == "enabled" ]]; then
  mapfile -t parameter_args < <(
    python3 "${PARAMETER_PROFILE_TOOL}" arguments \
      --parameters "${PROFILE_PARAMETERS_JSON}" --backend verilator \
      --top "${DESIGN_TOP}"
  )
fi
"${VERILATOR_CMD:-verilator}" --lint-only --sv --Wall \
  --top-module "${DESIGN_TOP}" "${VERILATOR_WAIVER_FILE}" \
  "${parameter_args[@]}" -f "${RTL_FILELIST}" \
  2>&1 | tee "${flow_report_dir}/lint.log"

printf 'PASS\n' > "${flow_report_dir}/status.txt"
