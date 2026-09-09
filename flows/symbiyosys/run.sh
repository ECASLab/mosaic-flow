#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

flow_report_dir="${REPORT_DIR}/symbiyosys_formal"
flow_work_dir="${WORK_DIR}/symbiyosys_formal"
mkdir -p "${flow_report_dir}" "${flow_work_dir}"
printf 'FAIL\n' > "${flow_report_dir}/status.txt"

# FORMAL_CONFIG is part of the module-owned exported environment contract.
# shellcheck disable=SC2153
formal_config="${FORMAL_CONFIG}"
if [[ "${MOSAIC_PROFILE_ACTIVE:-disabled}" == "enabled" ]]; then
  formal_config="${flow_report_dir}/profile.sby"
  python3 "${PARAMETER_PROFILE_TOOL}" render-sby \
    --input "${FORMAL_CONFIG}" --output "${formal_config}" \
    --parameters "${PROFILE_PARAMETERS_JSON}" --top "${FORMAL_TOP}"
fi

cd "${REPO_ROOT}" || exit 2
"${SBY_CMD:-sby}" -f -d "${flow_work_dir}" \
  "${formal_config}" 2>&1 | tee "${flow_report_dir}/formal.log"
test -f "${flow_work_dir}/PASS"

# Proof and cover reachability are separate SymbiYosys tasks because they use
# different modes, wrappers, and acceptance evidence.
if [[ -n "${COVERAGE_FILELIST:-}" ]]; then
  if [[ -z "${FORMAL_COVER_CONFIG:-}" ]]; then
    echo "FORMAL_COVER_CONFIG is required when COVERAGE_FILELIST is set" >&2
    exit 2
  fi

  coverage_work_dir="${WORK_DIR}/symbiyosys_coverage"
  formal_cover_config="${FORMAL_COVER_CONFIG}"
  if [[ "${MOSAIC_PROFILE_ACTIVE:-disabled}" == "enabled" ]]; then
    formal_cover_config="${flow_report_dir}/coverage-profile.sby"
    python3 "${PARAMETER_PROFILE_TOOL}" render-sby \
      --input "${FORMAL_COVER_CONFIG}" --output "${formal_cover_config}" \
      --parameters "${PROFILE_PARAMETERS_JSON}" --top "${FORMAL_TOP}"
  fi
  "${SBY_CMD:-sby}" -f -d "${coverage_work_dir}" \
    "${formal_cover_config}" 2>&1 | tee "${flow_report_dir}/coverage.log"
  test -f "${coverage_work_dir}/PASS"
fi

printf 'PASS\n' > "${flow_report_dir}/status.txt"
