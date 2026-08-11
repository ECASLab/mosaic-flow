#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${flow_root}/config/tool-versions.env"

version="${VERIBLE_VERSION}"
install_dir="${1:-${HOME}/.local}"
archive="verible-${version}-linux-static-x86_64.tar.gz"
url="https://github.com/chipsalliance/verible/releases/download/${version}/${archive}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
curl --fail --location --retry 3 --output "${tmp_dir}/${archive}" "${url}"
tar -xzf "${tmp_dir}/${archive}" -C "${tmp_dir}"
mkdir -p "${install_dir}/bin"
find "${tmp_dir}" -type f -path '*/bin/verible-*' -exec install -m 0755 {} "${install_dir}/bin/" \;
