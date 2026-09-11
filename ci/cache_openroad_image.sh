#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/tool-versions.env
source "${flow_root}/config/tool-versions.env"

runtime="${OPENROAD_CONTAINER_RUNTIME:-docker}"
image="${OPENROAD_ORFS_IMAGE:-${ORFS_IMAGE_REPOSITORY}@${ORFS_IMAGE_DIGEST}}"
cache_root="${OPENROAD_IMAGE_CACHE_ROOT:-${HOME}/.cache/mosaic/openroad-images}"
archive="${cache_root}/${ORFS_IMAGE_DIGEST#sha256:}.tar"

if ! command -v "${runtime}" >/dev/null 2>&1; then
  echo "OpenROAD container runtime is unavailable: ${runtime}" >&2
  exit 2
fi
if [[ ! "${image}" =~ @sha256:[0-9a-f]{64}$ ]]; then
  echo "OpenROAD image cache requires an immutable @sha256 reference: ${image}" >&2
  exit 2
fi

if ! "${runtime}" image inspect "${image}" >/dev/null 2>&1 && [[ -s "${archive}" ]]; then
  echo "Loading pinned OpenROAD image from ${archive}"
  "${runtime}" load --input "${archive}"
fi

if ! "${runtime}" image inspect "${image}" >/dev/null 2>&1; then
  echo "Pulling pinned OpenROAD image: ${image}"
  "${runtime}" pull "${image}"
else
  echo "Pinned OpenROAD image is available: ${image}"
fi

if [[ ! -s "${archive}" ]]; then
  mkdir -p "${cache_root}"
  temporary_archive="${archive}.tmp.$$"
  trap 'rm -f "${temporary_archive:-}"' EXIT
  echo "Saving pinned OpenROAD image layers to ${archive}"
  "${runtime}" save --output "${temporary_archive}" "${image}"
  mv "${temporary_archive}" "${archive}"
  trap - EXIT
fi
