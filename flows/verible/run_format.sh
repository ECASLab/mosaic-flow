#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

flow_report_dir="${REPORT_DIR}/verible_format"
mkdir -p "${flow_report_dir}"
printf 'FAIL\n' > "${flow_report_dir}/status.txt"

mapfile -t sources < <(find rtl verif -type f \( -name '*.sv' -o -name '*.svh' \) -print | sort)
cd "${REPO_ROOT}" || exit 2
: >"${flow_report_dir}/format.log"

for source in "${sources[@]}"; do
  if ! diff -u "${source}" <("${VERIBLE_FORMAT_CMD:-verible-verilog-format}" \
      --verify_convergence --failsafe_success=false "${source}") \
      >>"${flow_report_dir}/format.log"; then
    echo "Formatting differs: ${source}" >&2
    exit 1
  fi
done
printf 'PASS\n' > "${flow_report_dir}/status.txt"
