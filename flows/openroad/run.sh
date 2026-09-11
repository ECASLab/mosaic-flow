#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../common/env.sh
source "$(dirname "$0")/../common/env.sh"

flow_report_dir="${REPORT_DIR}/openroad"
orfs_work_home="${WORK_DIR}/openroad"
config_relative=""
constraint_relative=""
module_root_real=""
execution_mode=""

module_relative_path() {
  local candidate="$1"
  local resolved
  resolved="$(realpath -e "${candidate}")"
  if [[ "${resolved}" != "${module_root_real}/"* ]]; then
    echo "OpenROAD input must be owned by MODULE_ROOT: ${candidate}" >&2
    return 2
  fi
  printf '%s\n' "${resolved#"${module_root_real}/"}"
}

execution_runtime=""
runtime_version=""
orfs_revision=""
image_reference=""
image_digest=""
image_id=""

prepare_openroad() {
  local required_openroad_vars=(
    OPENROAD_CONFIG
    OPENROAD_CONSTRAINT_FILE
    OPENROAD_EVIDENCE_POLICY
    OPENROAD_EVIDENCE_TOOL
    OPENROAD_PLATFORM
    OPENROAD_FLOW_VARIANT
    OPENROAD_DESIGN_NAME
  )
  local variable_name

  for variable_name in "${required_openroad_vars[@]}"; do
    if [[ -z "${!variable_name:-}" ]]; then
      echo "Missing OpenROAD environment variable: ${variable_name}" >&2
      return 2
    fi
  done
  execution_mode="${OPENROAD_EXECUTION_MODE:-local}"
  module_root_real="$(realpath -e "${MODULE_ROOT}")" || return $?
  config_relative="$(module_relative_path "${OPENROAD_CONFIG}")" || return $?
  constraint_relative="$(module_relative_path "${OPENROAD_CONSTRAINT_FILE}")" || return $?
  module_relative_path "${OPENROAD_EVIDENCE_POLICY}" >/dev/null || return $?
  mkdir -p "${flow_report_dir}" "${orfs_work_home}"
}

run_orfs_local() {
  if [[ -z "${OPENROAD_FLOW_ROOT:-}" || \
        ! -f "${OPENROAD_FLOW_ROOT}/flow/Makefile" ]]; then
    echo "OPENROAD_FLOW_ROOT must identify an OpenROAD-flow-scripts checkout in local mode." >&2
    return 2
  fi
  orfs_revision="$(git -C "${OPENROAD_FLOW_ROOT}" rev-parse HEAD 2>/dev/null || true)"
  make -C "${OPENROAD_FLOW_ROOT}/flow" \
    DESIGN_CONFIG="${OPENROAD_CONFIG}" \
    DESIGN_NICKNAME="${OPENROAD_DESIGN_NAME}" \
    FLOW_VARIANT="${OPENROAD_FLOW_VARIANT}" \
    OPENROAD_PLATFORM="${OPENROAD_PLATFORM}" \
    PLATFORM="${OPENROAD_PLATFORM}" \
    REPO_ROOT="${module_root_real}" \
    SDC_FILE="${OPENROAD_CONSTRAINT_FILE}" \
    WORK_HOME="${orfs_work_home}" || return $?
}

run_orfs_container() {
  execution_runtime="${OPENROAD_CONTAINER_RUNTIME:-docker}"
  image_reference="${OPENROAD_ORFS_IMAGE:-}"
  if [[ ! "${image_reference}" =~ @(sha256:[0-9a-f]{64})$ ]]; then
    echo "OPENROAD_ORFS_IMAGE must use an immutable @sha256 digest: ${image_reference}" >&2
    return 2
  fi
  image_digest="${BASH_REMATCH[1]}"
  if ! command -v "${execution_runtime}" >/dev/null 2>&1; then
    echo "OpenROAD container runtime is unavailable: ${execution_runtime}" >&2
    return 2
  fi
  runtime_version="$(${execution_runtime} --version | head -n 1)" || return $?
  if ! "${execution_runtime}" image inspect "${image_reference}" >/dev/null 2>&1; then
    "${execution_runtime}" pull "${image_reference}" || return $?
  fi
  image_id="$(
    "${execution_runtime}" image inspect "${image_reference}" --format '{{.Id}}'
  )" || return $?

  # Variables in the final command are intentionally expanded by the container.
  # shellcheck disable=SC2016
  "${execution_runtime}" run --rm \
    --user "$(id -u):$(id -g)" \
    --env HOME=/tmp \
    --env MOSAIC_DESIGN_CONFIG="/workspace/${config_relative}" \
    --env MOSAIC_DESIGN_NAME="${OPENROAD_DESIGN_NAME}" \
    --env MOSAIC_FLOW_VARIANT="${OPENROAD_FLOW_VARIANT}" \
    --env MOSAIC_PLATFORM="${OPENROAD_PLATFORM}" \
    --env MOSAIC_SDC_FILE="/workspace/${constraint_relative}" \
    --mount "type=bind,src=${module_root_real},dst=/workspace,readonly" \
    --mount "type=bind,src=$(realpath -e "${orfs_work_home}"),dst=/orfs-work" \
    --entrypoint bash \
    "${image_reference}" \
    -lc 'source /OpenROAD-flow-scripts/env.sh && make -C /OpenROAD-flow-scripts/flow \
      DESIGN_CONFIG="${MOSAIC_DESIGN_CONFIG}" \
      DESIGN_NICKNAME="${MOSAIC_DESIGN_NAME}" \
      FLOW_VARIANT="${MOSAIC_FLOW_VARIANT}" \
      OPENROAD_PLATFORM="${MOSAIC_PLATFORM}" \
      PLATFORM="${MOSAIC_PLATFORM}" \
      REPO_ROOT=/workspace \
      SDC_FILE="${MOSAIC_SDC_FILE}" \
      WORK_HOME=/orfs-work' || return $?
}

qualify_openroad() {
  prepare_openroad || return $?
  case "${execution_mode}" in
    local)
      run_orfs_local
      ;;
    container)
      run_orfs_container
      ;;
    *)
      echo "OPENROAD_EXECUTION_MODE must be local or container, found: ${execution_mode}" >&2
      return 2
      ;;
  esac

  "${OPENROAD_EVIDENCE_TOOL}" \
    --module-root "${MODULE_ROOT}" \
    --policy "${OPENROAD_EVIDENCE_POLICY}" \
    --evidence-root "${orfs_work_home}" \
    --design-config "${OPENROAD_CONFIG}" \
    --constraint "${OPENROAD_CONSTRAINT_FILE}" \
    --output "${flow_report_dir}/evidence.json" \
    --execution-mode "${execution_mode}" \
    --design "${OPENROAD_DESIGN_NAME}" \
    --platform "${OPENROAD_PLATFORM}" \
    --variant "${OPENROAD_FLOW_VARIANT}" \
    --runtime "${execution_runtime}" \
    --runtime-version "${runtime_version}" \
    --orfs-revision "${orfs_revision}" \
    --image-reference "${image_reference}" \
    --image-digest "${image_digest}" \
    --image-id "${image_id}"
}

run_and_record openroad qualify_openroad
