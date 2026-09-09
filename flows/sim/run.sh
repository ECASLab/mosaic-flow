#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

case "${SIMULATOR:-}" in
  vcs|verilator)
    flow_name="${SIMULATOR}_sim"
    ;;
  *)
    echo "Unsupported or unspecified simulator: ${SIMULATOR:-<empty>}. Use vcs or verilator." >&2
    exit 2
    ;;
esac

flow_report_dir="${REPORT_DIR}/${flow_name}"
flow_work_dir="${WORK_DIR}/${flow_name}"
mkdir -p "${flow_report_dir}" "${flow_work_dir}"
printf 'FAIL\n' > "${flow_report_dir}/status.txt"

# Compile temporal dependencies before the assertion and coverage wrappers that
# include or instantiate them. Empty lists keep each layer optional.
property_args=()
if [[ -n "${PROPERTY_FILELIST:-}" ]]; then
  property_args=(-f "${PROPERTY_FILELIST}")
fi

assertion_args=()
if [[ -n "${ASSERTION_FILELIST:-}" ]]; then
  assertion_args=(-f "${ASSERTION_FILELIST}")
fi

coverage_filelist_args=()
coverage_enabled=0
if [[ -n "${COVERAGE_FILELIST:-}" ]]; then
  coverage_filelist_args=(-f "${COVERAGE_FILELIST}")
  case "${SIM_COVERAGE:-enabled}" in
    enabled)
      coverage_enabled=1
      ;;
    disabled)
      ;;
    *)
      echo "SIM_COVERAGE must be enabled or disabled" >&2
      exit 2
      ;;
  esac
fi

case "${SIMULATOR}" in
  vcs)
    parameter_args=()
    if [[ "${MOSAIC_PROFILE_ACTIVE:-disabled}" == "enabled" ]]; then
      mapfile -t parameter_args < <(
        python3 "${PARAMETER_PROFILE_TOOL}" arguments \
          --parameters "${PROFILE_PARAMETERS_JSON}" --backend vcs \
          --top "${TB_TOP}"
      )
    fi
    vcs_compile_coverage_args=()
    vcs_run_coverage_args=()
    if [[ "${coverage_enabled}" -eq 1 ]]; then
      coverage_database="${flow_work_dir}/coverage.vdb"
      vcs_compile_coverage_args=(
        -cm line+cond+tgl+assert
        -cm_dir "${coverage_database}"
      )
      vcs_run_coverage_args=(
        -cm line+cond+tgl+assert
        -cm_dir "${coverage_database}"
      )
    fi
    "${SIM_BIN:-vcs}" -full64 -sverilog -f "${TB_FILELIST}" \
      "${property_args[@]}" "${assertion_args[@]}" \
      "${coverage_filelist_args[@]}" \
      "${parameter_args[@]}" "${vcs_compile_coverage_args[@]}" \
      -top "${TB_TOP}" \
      -o "${flow_work_dir}/simv" 2>&1 | tee "${flow_report_dir}/compile.log"
    simulation_binary="${flow_work_dir}/simv"
    simulation_args=("${vcs_run_coverage_args[@]}")
    ;;
  verilator)
    parameter_args=()
    if [[ "${MOSAIC_PROFILE_ACTIVE:-disabled}" == "enabled" ]]; then
      mapfile -t parameter_args < <(
        python3 "${PARAMETER_PROFILE_TOOL}" arguments \
          --parameters "${PROFILE_PARAMETERS_JSON}" --backend verilator \
          --top "${TB_TOP}"
      )
    fi
    verilator_coverage_args=()
    simulation_args=()
    if [[ "${coverage_enabled}" -eq 1 ]]; then
      verilator_coverage_args=(--coverage)
      simulation_args=(
        "+verilator+coverage+file+${flow_report_dir}/coverage.dat"
      )
    fi
    "${VERILATOR_CMD:-verilator}" --binary --timing --assert -Wall \
      -Wno-BLKSEQ -Wno-SYNCASYNCNET -f "${TB_FILELIST}" \
      "${property_args[@]}" "${assertion_args[@]}" \
      "${coverage_filelist_args[@]}" \
      "${verilator_coverage_args[@]}" \
      "${parameter_args[@]}" \
      --top-module "${TB_TOP}" --Mdir "${flow_work_dir}/obj_dir" \
      2>&1 | tee "${flow_report_dir}/compile.log"
    simulation_binary="${flow_work_dir}/obj_dir/V${TB_TOP}"
    ;;
esac

"${simulation_binary}" "${simulation_args[@]}" \
  2>&1 | tee "${flow_report_dir}/run.log"

if [[ "${SIMULATOR}" == "verilator" && "${coverage_enabled}" -eq 1 ]]; then
  # Preserve both the native database and a reviewable text representation.
  "${VERILATOR_COVERAGE_CMD:-verilator_coverage}" --write-info \
    "${flow_report_dir}/coverage.info" "${flow_report_dir}/coverage.dat"
fi

printf 'PASS\n' > "${flow_report_dir}/status.txt"
