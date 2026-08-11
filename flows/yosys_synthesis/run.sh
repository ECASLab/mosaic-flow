#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

flow_report_dir="${REPORT_DIR}/yosys_synthesis"
flow_work_dir="${WORK_DIR}/yosys_synthesis"
mkdir -p "${flow_report_dir}" "${flow_work_dir}"
printf 'FAIL\n' > "${flow_report_dir}/status.txt"

read_verilog_args="-sv"
while IFS= read -r filelist_entry || [[ -n "${filelist_entry}" ]]; do
  case "${filelist_entry}" in
    ""|\#*)
      ;;
    +incdir+*)
      read_verilog_args+=" -I${filelist_entry#+incdir+}"
      ;;
    -*|+*)
      echo "Unsupported Yosys file-list entry: ${filelist_entry}" >&2
      exit 2
      ;;
    *)
      read_verilog_args+=" ${filelist_entry}"
      ;;
  esac
done < "${RTL_FILELIST}"

cd "${REPO_ROOT}"
"${YOSYS_CMD:-yosys}" -l "${flow_report_dir}/synthesis.log" -p "
  read_verilog ${read_verilog_args};
  hierarchy -check -top ${DESIGN_TOP};
  proc;
  opt;
  check -assert;
  synth -top ${DESIGN_TOP};
  check -assert;
  tee -o ${flow_report_dir}/statistics.rpt stat -top ${DESIGN_TOP};
  write_json ${flow_work_dir}/${DESIGN_TOP}.json;
  write_verilog -noattr ${flow_work_dir}/${DESIGN_TOP}_netlist.v;
"

test -s "${flow_work_dir}/${DESIGN_TOP}.json"
test -s "${flow_work_dir}/${DESIGN_TOP}_netlist.v"
test -s "${flow_report_dir}/statistics.rpt"
printf 'PASS\n' > "${flow_report_dir}/status.txt"
