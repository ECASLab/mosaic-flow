#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

flow_report_dir="${REPORT_DIR}/verible_format"
mkdir -p "${flow_report_dir}"
printf 'FAIL\n' > "${flow_report_dir}/status.txt"

cd "${REPO_ROOT}" || exit 2
read -r -a format_paths <<< "${VERIBLE_FORMAT_PATHS:-rtl verif}"
read -r -a format_args <<< "${VERIBLE_FORMAT_ARGS:-}"
if [[ "${#format_paths[@]}" -eq 0 ]]; then
  echo "VERIBLE_FORMAT_PATHS must select at least one source path" >&2
  exit 2
fi
for format_path in "${format_paths[@]}"; do
  if [[ ! -e "${format_path}" ]]; then
    echo "Verible format path does not exist: ${format_path}" >&2
    exit 2
  fi
done
mapfile -t sources < <(
  find "${format_paths[@]}" -type f \( -name '*.sv' -o -name '*.svh' \) -print | sort -u
)
if [[ "${#sources[@]}" -eq 0 ]]; then
  echo "VERIBLE_FORMAT_PATHS did not select any SystemVerilog sources" >&2
  exit 2
fi
: >"${flow_report_dir}/format.log"

for source in "${sources[@]}"; do
  if ! diff -u "${source}" <("${VERIBLE_FORMAT_CMD:-verible-verilog-format}" \
      "${format_args[@]}" --verify_convergence --failsafe_success=false "${source}") \
      >>"${flow_report_dir}/format.log"; then
    echo "Formatting differs: ${source}" >&2
    exit 1
  fi
done
printf 'PASS\n' > "${flow_report_dir}/status.txt"
