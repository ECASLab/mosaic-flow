#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="${flow_root}/tests/fixtures/static-intent"
report_root="$(mktemp -d)"
trap 'rm -rf "${report_root}"' EXIT

run_positive() {
    local name="$1"
    python3 "${flow_root}/ci/static_intent.py" \
        --config "${fixture_root}/config/${name}.json" \
        --module-root "${fixture_root}" \
        --output-dir "${report_root}/${name}"
    test "$(<"${report_root}/${name}/status.txt")" = PASS
    grep -Fq '"status": "PASS"' "${report_root}/${name}/summary.json"
}

expect_failure() {
    local name="$1"
    local report="$2"
    local code="$3"
    if python3 "${flow_root}/ci/static_intent.py" \
        --config "${fixture_root}/config/${name}.json" \
        --module-root "${fixture_root}" \
        --output-dir "${report_root}/${name}" \
        >"${report_root}/${name}.log" 2>&1; then
        echo "Static-intent fixture ${name} unexpectedly passed" >&2
        exit 1
    fi
    test "$(<"${report_root}/${name}/status.txt")" = FAIL
    grep -Fq "\"code\": \"${code}\"" \
        "${report_root}/${name}/${report}-findings.json"
}

run_positive always-on
run_positive complete
run_positive isolation
run_positive level-shifter

expect_failure missing-constraint sdc missing_command
expect_failure incomplete-max-delay sdc incomplete_max_delay
expect_failure broad-exception sdc broad_exception
expect_failure duplicate-command sdc duplicate_command
expect_failure conflicting-command sdc conflicting_command
expect_failure unsupported-command sdc invalid_sdc_intent
expect_failure profile-mismatch sdc profile_mismatch
expect_failure incomplete-power-state upf incomplete_power_state
expect_failure forbidden-strategy upf forbidden_strategy

adapter_reports="${report_root}/adapter-reports"
adapter_environment=(
    "MODULE_ROOT=${fixture_root}"
    "FLOW_ROOT=${flow_root}"
    "REPORT_DIR=${adapter_reports}"
    "MOSAIC_FLOW_IDS=static_intent"
    "FLOW_static_intent=enabled"
    "FLOW_DEPENDENCIES_static_intent="
    "STATIC_INTENT_TOOL=${flow_root}/ci/static_intent.py"
    "STATIC_INTENT_CONFIG=${fixture_root}/config/complete.json"
)
env "${adapter_environment[@]}" \
    "${flow_root}/ci/run_flow.sh" static_intent \
    "${flow_root}/flows/static_intent/run.sh" >/dev/null
test "$(<"${adapter_reports}/static_intent/status.txt")" = PASS

if env "${adapter_environment[@]}" \
    "STATIC_INTENT_CONFIG=${fixture_root}/config/missing-constraint.json" \
    "${flow_root}/ci/run_flow.sh" static_intent \
    "${flow_root}/flows/static_intent/run.sh" >/dev/null 2>&1; then
    echo "Static-intent flow adapter accepted failing intent" >&2
    exit 1
fi
test "$(<"${adapter_reports}/static_intent/status.txt")" = FAIL

skip_reports="${report_root}/skip-reports"
env \
    MODULE_ROOT="${fixture_root}" FLOW_ROOT="${flow_root}" \
    REPORT_DIR="${skip_reports}" MOSAIC_FLOW_IDS=static_intent \
    FLOW_static_intent=disabled FLOW_DEPENDENCIES_static_intent= \
    DISABLED_FLOWS=static_intent \
    "${flow_root}/ci/run_flow.sh" static_intent false >/dev/null
test "$(<"${skip_reports}/static_intent/status.txt")" = SKIP

echo "Portable static-intent positive and negative fixtures passed"
