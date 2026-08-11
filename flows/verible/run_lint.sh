#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

flow_report_dir="${REPORT_DIR}/verible_lint"
mkdir -p "${flow_report_dir}"
printf 'FAIL\n' > "${flow_report_dir}/status.txt"

rtl_files=()
while IFS= read -r entry || [[ -n "${entry}" ]]; do
  case "${entry}" in
    ""|\#*) ;;
    +incdir+*) ;;
    -*|+*) echo "Unsupported Verible file-list entry: ${entry}" >&2; exit 2 ;;
    *) rtl_files+=("${entry}") ;;
  esac
done < "${RTL_FILELIST}"
rules="$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "${VERIBLE_RULES_FILE}" | paste -sd, -)"
args=(--parse_fatal --lint_fatal --waiver_files "${VERIBLE_WAIVER_FILE}")
if [[ -n "${rules}" ]]; then
  args+=(--rules_config "${rules}")
fi

cd "${REPO_ROOT}"
"${VERIBLE_LINT_CMD:-verible-verilog-lint}" "${args[@]}" "${rtl_files[@]}" \
  2>&1 | tee "${flow_report_dir}/lint.log"
printf 'PASS\n' > "${flow_report_dir}/status.txt"
