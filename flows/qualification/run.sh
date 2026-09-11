#!/usr/bin/env bash
source "$(dirname "$0")/../common/env.sh"

campaign="${1:?Usage: run.sh <negative|four_state>}"
case "${campaign}" in
    negative)
        flow_id=negative_qualification
        ;;
    four_state)
        flow_id=four_state_qualification
        ;;
    *)
        echo "Unknown qualification campaign: ${campaign}" >&2
        exit 2
        ;;
esac

"${QUALIFICATION_CAMPAIGN_TOOL}" \
    --campaign "${campaign}" \
    --manifest "${QUALIFICATION_CAMPAIGN_MANIFEST}" \
    --module-root "${MODULE_ROOT}" \
    --flow-root "${FLOW_ROOT}" \
    --report-dir "${REPORT_DIR}/${flow_id}" \
    --work-dir "${WORK_DIR}/${flow_id}"
