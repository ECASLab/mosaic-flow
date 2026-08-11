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

case "${SIMULATOR}" in
  vcs)
    "${SIM_BIN:-vcs}" -full64 -sverilog -f "${TB_FILELIST}" -top "${TB_TOP}" \
      -o "${flow_work_dir}/simv" 2>&1 | tee "${flow_report_dir}/compile.log"
    simulation_binary="${flow_work_dir}/simv"
    ;;
  verilator)
    "${VERILATOR_CMD:-verilator}" --binary --timing --assert -Wall \
      -Wno-BLKSEQ -Wno-SYNCASYNCNET -f "${TB_FILELIST}" \
      --top-module "${TB_TOP}" --Mdir "${flow_work_dir}/obj_dir" \
      2>&1 | tee "${flow_report_dir}/compile.log"
    simulation_binary="${flow_work_dir}/obj_dir/V${TB_TOP}"
    ;;
esac

"${simulation_binary}" 2>&1 | tee "${flow_report_dir}/run.log"

printf 'PASS\n' > "${flow_report_dir}/status.txt"
