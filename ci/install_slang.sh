#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${flow_root}/config/tool-versions.env"

version="${SLANG_VERSION}"
install_dir="${1:-${HOME}/.local}"
archive="slang-linux-x86_64.tar.gz"
url="https://github.com/MikePopoloski/slang/releases/download/${version}/${archive}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
curl --fail --location --retry 3 --output "${tmp_dir}/${archive}" "${url}"
tar -xzf "${tmp_dir}/${archive}" -C "${tmp_dir}"
mkdir -p "${install_dir}/bin"
slang_binary="$(find "${tmp_dir}" -type f -name slang -perm -u+x | head -n 1)"
test -n "${slang_binary}"
install -m 0755 "${slang_binary}" "${install_dir}/bin/slang"
