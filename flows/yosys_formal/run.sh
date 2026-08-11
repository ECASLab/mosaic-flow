#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

flow_report_dir="${REPORT_DIR}/yosys_formal"
flow_work_dir="${WORK_DIR}/yosys_formal"
mkdir -p "${flow_report_dir}" "${flow_work_dir}"
printf 'FAIL\n' > "${flow_report_dir}/status.txt"

formal_filelist="${REPO_ROOT}/filelists/formal.f"
read_verilog_args="-formal -sv"
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
done < "${formal_filelist}"

cd "${REPO_ROOT}"
"${YOSYS_CMD:-yosys}" -l "${flow_report_dir}/formal.log" -p "
  read_verilog ${read_verilog_args};
  prep -top ${FORMAL_TOP} -flatten;
  async2sync;
  dffunmap;
  sat -verify -prove-asserts -seq 8 -set-init-zero -set-at 1 clk_i 0 -set-at 2 clk_i 1 -set-at 3 clk_i 0 -set-at 4 clk_i 1 -set-at 5 clk_i 0 -set-at 6 clk_i 1 -set-at 7 clk_i 0 -set-at 8 clk_i 1 -set-at 1 rst_ni 0 -set-at 2 rst_ni 0 -set-at 3 rst_ni 1 -set-at 4 rst_ni 1 -set-at 5 rst_ni 1 -set-at 6 rst_ni 1 -set-at 7 rst_ni 1 -set-at 8 rst_ni 1 -dump_vcd ${flow_work_dir}/counterexample.vcd;
"

printf 'PASS\n' > "${flow_report_dir}/status.txt"
