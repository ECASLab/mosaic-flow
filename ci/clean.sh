#!/usr/bin/env bash
set -euo pipefail

work_root="${WORK_DIR:-${MODULE_ROOT}/work}"
report_root="${REPORT_DIR:-${MODULE_ROOT}/reports}"

rm -rf -- "${work_root}"
if [[ -d "${report_root}" ]]; then
  find "${report_root}" -mindepth 1 ! -name .gitkeep -delete
fi
