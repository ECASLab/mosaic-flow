#!/usr/bin/env bash
set -euo pipefail

rm -rf -- "${MODULE_ROOT}/work"
if [[ -d "${MODULE_ROOT}/reports" ]]; then
  find "${MODULE_ROOT}/reports" -mindepth 1 ! -name .gitkeep -delete
fi
