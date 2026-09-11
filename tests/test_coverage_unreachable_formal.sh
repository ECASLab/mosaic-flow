#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="${flow_root}/tests/fixture-module"
unreachable_config="${fixture_root}/config/formal_cover_unreachable.sby"
summary="${fixture_root}/reports/coverage_qualification/summary.json"
status="${fixture_root}/reports/coverage_qualification/status.txt"

# Reuse the passing native simulation evidence produced by the fixture job, but
# replace formal cover intent with one deliberately unreachable statement.
if make -C "${fixture_root}" FLOW_ROOT="${flow_root}" \
    FORMAL_COVER_CONFIG="${unreachable_config}" open-coverage \
    >"${fixture_root}/reports/unreachable-formal-test.log" 2>&1; then
    echo "Coverage qualification accepted an unreachable formal cover statement" >&2
    exit 1
fi

test "$(<"${status}")" = FAIL
python3 - "${summary}" <<'PY'
import json
import pathlib
import sys

summary = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert summary["status"] == "FAIL"
assert summary["formal"]["required"] is True
assert summary["formal"]["status"] == "FAIL"
assert summary["formal"]["reached_statements"] == 0
assert summary["failures"] == [
    "formal cover reachability is FAIL, expected PASS for all cover statements"
]
PY

# Leave the fixture in its normal passing state for subsequent release evidence.
make -C "${fixture_root}" FLOW_ROOT="${flow_root}" open-coverage >/dev/null

echo "Unreachable formal cover correctly failed coverage qualification"
