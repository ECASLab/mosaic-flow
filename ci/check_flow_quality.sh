#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${flow_root}"

mapfile -d '' shell_files < <(
  find ci flows tests -path 'tests/fixture-module/work' -prune -o \
    -type f -name '*.sh' -print0 | sort -z
)
mapfile -d '' workflow_files < <(find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 | sort -z)

for shell_file in "${shell_files[@]}"; do
  bash -n "${shell_file}"
done

shellcheck --external-sources "${shell_files[@]}"
actionlint "${workflow_files[@]}"

if ! grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' VERSION; then
  echo "VERSION must contain a semantic version such as 1.2.3" >&2
  exit 1
fi

required_version_keys=(
  OSS_CAD_SUITE_VERSION
  OSS_CAD_SUITE_SHA256
  VERIBLE_VERSION
  SLANG_VERSION
  SHELLCHECK_VERSION
  SHELLCHECK_SHA256
  ACTIONLINT_VERSION
  ACTIONLINT_SHA256
)
source config/tool-versions.env
for version_key in "${required_version_keys[@]}"; do
  if [[ -z "${!version_key:-}" ]]; then
    echo "Missing tool version field: ${version_key}" >&2
    exit 1
  fi
done

if rg -n 'mosaic_module|\bclk_i\b|\brst_ni\b' ci config flows mk -g '!check_flow_quality.sh'; then
  echo "Shared flow files contain module-specific identifiers" >&2
  exit 1
fi

while IFS= read -r -d '' data_file; do
  if [[ -x "${data_file}" ]]; then
    echo "Non-executable methodology file has its executable bit set: ${data_file}" >&2
    exit 1
  fi
done < <(find . -path './.git' -prune -o -type f \( -name '*.tcl' -o -name '*.mk' -o -name '*.env' \) -print0)

tests/test_quality_gate.sh
echo "mosaic-flow static quality checks passed"
