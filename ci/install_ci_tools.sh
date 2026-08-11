#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${flow_root}/config/tool-versions.env"

install_dir="${1:-${HOME}/.local}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

shellcheck_archive="shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz"
actionlint_archive="actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"

curl --fail --location --retry 3 \
  --output "${tmp_dir}/${shellcheck_archive}" \
  "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/${shellcheck_archive}"
curl --fail --location --retry 3 \
  --output "${tmp_dir}/${actionlint_archive}" \
  "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/${actionlint_archive}"

printf '%s  %s\n' "${SHELLCHECK_SHA256}" "${tmp_dir}/${shellcheck_archive}" | sha256sum --check
printf '%s  %s\n' "${ACTIONLINT_SHA256}" "${tmp_dir}/${actionlint_archive}" | sha256sum --check

tar -xJf "${tmp_dir}/${shellcheck_archive}" -C "${tmp_dir}"
tar -xzf "${tmp_dir}/${actionlint_archive}" -C "${tmp_dir}" actionlint
mkdir -p "${install_dir}/bin"
install -m 0755 "${tmp_dir}/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" "${install_dir}/bin/shellcheck"
install -m 0755 "${tmp_dir}/actionlint" "${install_dir}/bin/actionlint"
