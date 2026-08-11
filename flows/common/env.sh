#!/usr/bin/env bash
set -euo pipefail

export REPO_ROOT="${MODULE_ROOT}"

required_vars=(MODULE_ROOT FLOW_ROOT DESIGN_TOP TB_TOP FORMAL_TOP DUT_INSTANCE RTL_FILELIST TB_FILELIST CONSTRAINT_DIR REPORT_DIR WORK_DIR)
for variable_name in "${required_vars[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "Missing environment variable: ${variable_name}" >&2
    exit 2
  fi
done

mkdir -p "${REPORT_DIR}" "${WORK_DIR}"

run_and_record() {
  local flow_name="$1"
  shift
  local flow_report_dir="${REPORT_DIR}/${flow_name}"
  local flow_work_dir="${WORK_DIR}/${flow_name}"
  mkdir -p "${flow_report_dir}" "${flow_work_dir}"

  if "$@" 2>&1 | tee "${flow_report_dir}/run.log"; then
    printf 'PASS\n' > "${flow_report_dir}/status.txt"
  else
    printf 'FAIL\n' > "${flow_report_dir}/status.txt"
    return 1
  fi
}
