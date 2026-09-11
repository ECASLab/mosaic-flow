#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

flow_report_dir="${REPORT_DIR}/eqy_equivalence"
flow_work_dir="${WORK_DIR}/eqy_equivalence"
mkdir -p "${flow_report_dir}" "${flow_work_dir}"
printf 'FAIL\n' > "${flow_report_dir}/status.txt"

# EQUIVALENCE_CONFIG is part of the module-owned exported environment contract.
# shellcheck disable=SC2153
equivalence_config="${EQUIVALENCE_CONFIG}"
if [[ "${MOSAIC_PROFILE_ACTIVE:-disabled}" == "enabled" ]]; then
  equivalence_config="${flow_report_dir}/profile.eqy"
  python3 "${PARAMETER_PROFILE_TOOL}" render-eqy \
    --input "${EQUIVALENCE_CONFIG}" --output "${equivalence_config}" \
    --parameters "${PROFILE_PARAMETERS_JSON}" --top "${DESIGN_TOP}" \
    --netlist "${WORK_DIR}/yosys_synthesis/${DESIGN_TOP}_netlist.v"
fi

cd "${REPO_ROOT}" || exit 2
"${EQY_CMD:-eqy}" -f -d "${flow_work_dir}" \
  "${equivalence_config}" 2>&1 | tee "${flow_report_dir}/equivalence.log"
test -f "${flow_work_dir}/PASS"
printf 'PASS\n' > "${flow_report_dir}/status.txt"
