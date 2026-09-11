#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

flow_report_dir="${REPORT_DIR}/coverage_qualification"
flow_work_dir="${WORK_DIR}/coverage_qualification"
mkdir -p "${flow_report_dir}" "${flow_work_dir}"
printf 'FAIL\n' > "${flow_report_dir}/status.txt"

record_early_failure() {
  local source="$1"
  local message="$2"
  "${COVERAGE_QUALIFICATION_TOOL}" record-failure \
    --source "${source}" --message "${message}" \
    --output "${flow_report_dir}/summary.json"
  echo "${message}" >&2
  exit 1
}

source_name="${COVERAGE_QUALIFICATION_SOURCE:-verilator_sim}"
case "${source_name}" in
  verilator_sim|pyuvm_open_source)
    source_report_dir="${REPORT_DIR}/${source_name}"
    if [[ ! -f "${source_report_dir}/status.txt" ]] ||
       [[ "$(<"${source_report_dir}/status.txt")" != "PASS" ]]; then
      record_early_failure "${source_name}" "Coverage source ${source_name} must have PASS status"
    fi
    ;;
  dedicated)
    source_name=dedicated
    source_report_dir="${flow_report_dir}/dedicated"
    if ! SIMULATOR=verilator \
         MOSAIC_SIM_REPORT_DIR="${source_report_dir}" \
         MOSAIC_SIM_WORK_DIR="${flow_work_dir}/dedicated" \
         MOSAIC_SIM_FORCE_COVERAGE=enabled \
         "${FLOW_ROOT}/flows/sim/run.sh"; then
      record_early_failure "${source_name}" "Dedicated coverage simulation failed"
    fi
    ;;
  *)
    record_early_failure "${source_name}" \
      "COVERAGE_QUALIFICATION_SOURCE must be verilator_sim, pyuvm_open_source, or dedicated"
    ;;
esac

set +e
formal_required="$(${COVERAGE_QUALIFICATION_TOOL} inspect \
  --policy "${COVERAGE_QUALIFICATION_POLICY}" \
  --module-root "${MODULE_ROOT}" --field formal.required)"
policy_status="$?"
set -e
if [[ "${policy_status}" -ne 0 ]]; then
  "${COVERAGE_QUALIFICATION_TOOL}" qualify \
    --policy "${COVERAGE_QUALIFICATION_POLICY}" --module-root "${MODULE_ROOT}" \
    --native "${source_report_dir}/coverage.dat" --lcov "${source_report_dir}/coverage.info" \
    --source "${source_name}" --formal-result SKIP \
    --output "${flow_report_dir}/summary.json"
fi
formal_result=SKIP
formal_reached=0
if [[ "${formal_required}" == "true" ]]; then
  if [[ -z "${FORMAL_COVER_CONFIG:-}" ]]; then
    record_early_failure "${source_name}" "FORMAL_COVER_CONFIG is required by the coverage policy"
  fi

  coverage_work_dir="${flow_work_dir}/formal"
  formal_cover_config="${FORMAL_COVER_CONFIG}"
  if [[ "${MOSAIC_PROFILE_ACTIVE:-disabled}" == "enabled" ]]; then
    formal_cover_config="${flow_report_dir}/formal-profile.sby"
    python3 "${PARAMETER_PROFILE_TOOL}" render-sby \
      --input "${FORMAL_COVER_CONFIG}" --output "${formal_cover_config}" \
      --parameters "${PROFILE_PARAMETERS_JSON}" --top "${FORMAL_TOP}"
  fi
  set +e
  (
    cd "${REPO_ROOT}" || exit 2
    "${SBY_CMD:-sby}" -f -d "${coverage_work_dir}" "${formal_cover_config}"
  ) 2>&1 | tee "${flow_report_dir}/formal.log"
  formal_exit="${PIPESTATUS[0]}"
  set -e
  formal_reached="$(grep -c 'Reached cover statement' "${flow_report_dir}/formal.log" || true)"
  if [[ "${formal_exit}" -eq 0 && -f "${coverage_work_dir}/PASS" ]]; then
    formal_result=PASS
  else
    formal_result=FAIL
  fi
fi

"${COVERAGE_QUALIFICATION_TOOL}" qualify \
  --policy "${COVERAGE_QUALIFICATION_POLICY}" \
  --module-root "${MODULE_ROOT}" \
  --native "${source_report_dir}/coverage.dat" \
  --lcov "${source_report_dir}/coverage.info" \
  --source "${source_name}" --formal-result "${formal_result}" \
  --formal-reached "${formal_reached}" \
  --output "${flow_report_dir}/summary.json"

printf 'PASS\n' > "${flow_report_dir}/status.txt"
