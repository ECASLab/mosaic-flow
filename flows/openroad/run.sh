#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

if [[ -z "${OPENROAD_FLOW_ROOT:-}" ]]; then
  echo "OPENROAD_FLOW_ROOT must point to an OpenROAD-flow-scripts checkout." >&2
  echo "Run this optional PDK-backed flow with OPENROAD_FLOW_ROOT and OPENROAD_PLATFORM set." >&2
  exit 2
fi

run_and_record openroad make -C "${OPENROAD_FLOW_ROOT}/flow" \
  DESIGN_CONFIG="${OPENROAD_CONFIG}"
