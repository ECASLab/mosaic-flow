#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../common/env.sh"

# Keep open-source and licensed backends in separate policy-controlled flows.
flow_name="${1:?Flow name is required}"
simulator="${PYUVM_SIMULATOR:-}"

case "${simulator}" in
  verilator|icarus)
    if [[ "${flow_name}" != "pyuvm_open_source" ]]; then
      echo "${simulator} is only valid for the open-source PyUVM flow" >&2
      exit 2
    fi
    ;;
  vcs|xcelium)
    if [[ "${flow_name}" != "pyuvm_commercial" ]]; then
      echo "${simulator} is only valid for the commercial PyUVM flow" >&2
      exit 2
    fi
    ;;
  *)
    echo "Unsupported PyUVM simulator: ${simulator:-<empty>}" >&2
    exit 2
    ;;
esac

required_vars=(PYUVM_TEST_MODULE PYUVM_FILELIST PYUVM_TOP)
for variable_name in "${required_vars[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "Missing environment variable: ${variable_name}" >&2
    exit 2
  fi
done

for setting_name in PYUVM_COVERAGE PYUVM_WAVES; do
  setting_value="${!setting_name:-enabled}"
  if [[ "${setting_value}" != "enabled" && "${setting_value}" != "disabled" ]]; then
    echo "${setting_name} must be enabled or disabled, found: ${setting_value}" >&2
    exit 2
  fi
done

flow_report_dir="${REPORT_DIR}/${flow_name}"
flow_work_dir="${WORK_DIR}/${flow_name}/${simulator}"
rm -rf "${flow_report_dir}" "${flow_work_dir}"
mkdir -p "${flow_report_dir}" "${flow_work_dir}"
# Record failure before invoking Python so interrupted and failed runs cannot
# leave stale PASS evidence.
printf 'FAIL\n' > "${flow_report_dir}/status.txt"

export PYUVM_FLOW_NAME="${flow_name}"
export PYUVM_REPORT_DIR="${flow_report_dir}"
export PYUVM_WORK_DIR="${flow_work_dir}"
export PYUVM_FUNCTIONAL_COVERAGE_FILE="${flow_report_dir}/functional-coverage.json"

# run.py owns portable filelist parsing and the cocotb simulator lifecycle.
"${PYUVM_PYTHON:-python3}" "${FLOW_ROOT}/flows/pyuvm/run.py" \
  2>&1 | tee "${flow_report_dir}/run.log"

printf 'PASS\n' > "${flow_report_dir}/status.txt"
