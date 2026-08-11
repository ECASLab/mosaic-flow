#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/tool-versions.env
source "${flow_root}/config/tool-versions.env"

cache_root="${MOSAIC_TOOLS_ROOT:-${XDG_CACHE_HOME:-${HOME}/.cache}/mosaic}"
oss_dir="${cache_root}/oss-cad-suite/${OSS_CAD_SUITE_VERSION}"
verible_dir="${cache_root}/verible/${VERIBLE_VERSION}"
slang_dir="${cache_root}/slang/${SLANG_VERSION}"

required_commands=(
  verible-verilog-lint
  verible-verilog-format
  slang
  verilator
  yosys
  sby
  eqy
)

for command_name in "${required_commands[@]}"; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    missing=1
    break
  fi
done

if [[ "${missing:-0}" -eq 0 ]]; then
  exit 0
fi

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  echo "Automatic open-source tool setup currently supports Linux x86-64 only." >&2
  echo "Use the linux/amd64 Docker flow on other platforms." >&2
  exit 2
fi

mkdir -p "${cache_root}/downloads" "$(dirname "${oss_dir}")"

if [[ ! -x "${oss_dir}/bin/yosys" ]]; then
  if [[ -e "${oss_dir}" ]]; then
    echo "Incomplete OSS CAD Suite installation: ${oss_dir}" >&2
    echo "Remove that directory and rerun make open-source." >&2
    exit 2
  fi

  archive_date="$(printf '%s' "${OSS_CAD_SUITE_VERSION}" | tr -d '-')"
  archive="oss-cad-suite-linux-x64-${archive_date}.tgz"
  archive_path="${cache_root}/downloads/${archive}"
  url="https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${OSS_CAD_SUITE_VERSION}/${archive}"

  if [[ ! -f "${archive_path}" ]]; then
    echo "Downloading OSS CAD Suite ${OSS_CAD_SUITE_VERSION}..."
    curl --fail --location --retry 3 --output "${archive_path}.partial" "${url}"
    mv "${archive_path}.partial" "${archive_path}"
  fi

  printf '%s  %s\n' "${OSS_CAD_SUITE_SHA256}" "${archive_path}" | sha256sum --check
  install_root="$(mktemp -d "${cache_root}/oss-cad-suite/.install.XXXXXX")"
  trap 'rm -rf "${install_root}"' EXIT
  tar -xzf "${archive_path}" -C "${install_root}"
  mv "${install_root}/oss-cad-suite" "${oss_dir}"
  trap - EXIT
  rmdir "${install_root}"
fi

if [[ ! -x "${verible_dir}/bin/verible-verilog-lint" ]]; then
  echo "Installing Verible ${VERIBLE_VERSION}..."
  "${flow_root}/ci/install_verible.sh" "${verible_dir}"
fi

if [[ ! -x "${slang_dir}/bin/slang" ]]; then
  echo "Installing Slang ${SLANG_VERSION}..."
  "${flow_root}/ci/install_slang.sh" "${slang_dir}"
fi

echo "Open-source tools are ready under ${cache_root}"
