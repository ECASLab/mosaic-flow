#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf "${fixture_root}"' EXIT
mkdir -p "${fixture_root}/rtl" "${fixture_root}/evidence" "${fixture_root}/reports"
printf 'module dut; endmodule\n' > "${fixture_root}/rtl/dut.sv"

python3 - "${fixture_root}" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
tag = "\x01"
separator = "\x02"


def native_record(metric, line, name, hits):
    fields = {"f": "rtl/dut.sv", "l": str(line), "t": metric, "o": name}
    tagged = "".join(f"{tag}{key}{separator}{value}" for key, value in fields.items())
    return f"C '{tagged}' {hits}\n"


native = "# SystemC::Coverage-3\n"
native += native_record("line", 1, "block", 2)
native += native_record("line", 2, "block", 1)
native += native_record("branch", 3, "if", 1)
native += native_record("branch", 3, "else", 1)
native += native_record("toggle", 4, "ready:0->1", 1)
native += native_record("toggle", 4, "ready:1->0", 0)
native += native_record("user", 5, "transaction_seen", 3)
(root / "evidence" / "coverage.dat").write_text(native, encoding="latin-1")
deficient = "# SystemC::Coverage-3\n"
deficient += native_record("line", 1, "block", 1)
deficient += native_record("line", 2, "block", 0)
deficient += native_record("branch", 3, "if", 1)
deficient += native_record("branch", 3, "else", 0)
deficient += native_record("toggle", 4, "ready:0->1", 1)
deficient += native_record("toggle", 4, "ready:1->0", 0)
deficient += native_record("user", 5, "transaction_seen", 0)
(root / "evidence" / "deficient.dat").write_text(deficient, encoding="latin-1")
(root / "evidence" / "coverage.info").write_text(
    "TN:test\nSF:rtl/dut.sv\nDA:1,2\nDA:2,1\n"
    "BRDA:3,0,if,1\nBRDA:3,0,else,1\n"
    "BRDA:4,0,ready:0->1,1\nBRDA:4,0,ready:1->0,0\nend_of_record\n",
    encoding="utf-8",
)

base = {
    "schema": "mosaic-coverage-policy-v1",
    "scope": {"include": ["rtl/*.sv"]},
    "thresholds": {"line": 100, "branch": 100, "toggle": 50, "user": 100},
    "coverpoints": [{"name": "transaction_seen", "minimum_hits": 2}],
    "exclusions": [],
    "formal": {"required": False},
}
(root / "policy.json").write_text(json.dumps(base), encoding="utf-8")

complete = json.loads(json.dumps(base))
complete["thresholds"]["toggle"] = 100
complete["exclusions"] = [{
    "source": "rtl/dut.sv",
    "metric": "toggle",
    "reason": "The protocol never drives a falling edge in this mode.",
    "owner": "verification",
    "scope": {"line_start": 4, "name": "ready:1->0"},
}]
(root / "complete.json").write_text(json.dumps(complete), encoding="utf-8")

missing = json.loads(json.dumps(base))
missing["coverpoints"][0]["name"] = "missing_point"
(root / "missing.json").write_text(json.dumps(missing), encoding="utf-8")

threshold = json.loads(json.dumps(base))
threshold["thresholds"]["toggle"] = 100
(root / "threshold.json").write_text(json.dumps(threshold), encoding="utf-8")

stale = json.loads(json.dumps(base))
stale["exclusions"] = [{
    "source": "rtl/dut.sv",
    "metric": "toggle",
    "reason": "Deliberately stale test waiver.",
    "owner": "verification",
    "scope": {"line_start": 99},
}]
(root / "stale.json").write_text(json.dumps(stale), encoding="utf-8")

malformed = json.loads(json.dumps(base))
malformed["coverpoints"][0]["minimum_hits"] = 0
(root / "malformed.json").write_text(json.dumps(malformed), encoding="utf-8")

formal = json.loads(json.dumps(base))
formal["formal"]["required"] = True
(root / "formal.json").write_text(json.dumps(formal), encoding="utf-8")

lcov_only = json.loads(json.dumps(base))
lcov_only["thresholds"] = {"line": 100, "branch": 100, "toggle": 50}
lcov_only["coverpoints"] = []
(root / "lcov-only.json").write_text(json.dumps(lcov_only), encoding="utf-8")

for metric in ("line", "branch", "toggle", "user"):
    metric_policy = json.loads(json.dumps(base))
    metric_policy["thresholds"] = {metric: 100}
    metric_policy["coverpoints"] = []
    (root / f"{metric}-threshold.json").write_text(
        json.dumps(metric_policy), encoding="utf-8"
    )
PY

qualify() {
    local policy="$1"
    local formal_result="${2:-SKIP}"
    local native="${3:-${fixture_root}/evidence/coverage.dat}"
    local lcov="${4:-${fixture_root}/evidence/coverage.info}"
    "${flow_root}/ci/coverage_qualification.py" qualify \
        --policy "${fixture_root}/${policy}.json" --module-root "${fixture_root}" \
        --native "${native}" --lcov "${lcov}" --source verilator_sim \
        --formal-result "${formal_result}" --output "${fixture_root}/reports/${policy}.json"
}

expect_failure() {
    local expected="$1"
    shift
    if "$@" >"${fixture_root}/failure.log" 2>&1; then
        echo "Expected coverage qualification failure containing: ${expected}" >&2
        exit 1
    fi
    grep -Fq "${expected}" "${fixture_root}/failure.log"
}

qualify policy
qualify complete
qualify lcov-only SKIP "${fixture_root}/evidence/missing.dat"
expect_failure "required coverpoint missing_point is absent" qualify missing
expect_failure "toggle coverage 50.00% is below threshold 100%" qualify threshold
for metric in line branch toggle user; do
    expect_failure "${metric} coverage" qualify "${metric}-threshold" SKIP \
        "${fixture_root}/evidence/deficient.dat"
done
expect_failure "is stale or unmatched" qualify stale
expect_failure "minimum_hits must be a positive integer" qualify malformed
expect_failure "formal cover reachability is FAIL" qualify formal FAIL
expect_failure "formal cover configuration reached no cover statements" qualify formal PASS

adapter_environment=(
    "MODULE_ROOT=${fixture_root}"
    "FLOW_ROOT=${flow_root}"
    "DESIGN_TOP=dut"
    "TB_TOP=dut_tb"
    "FORMAL_TOP=dut_formal"
    "DUT_INSTANCE=dut_tb/dut"
    "RTL_FILELIST=${fixture_root}/rtl.f"
    "TB_FILELIST=${fixture_root}/tb.f"
    "CONSTRAINT_DIR=${fixture_root}"
    "REPORT_DIR=${fixture_root}/adapter-reports"
    "WORK_DIR=${fixture_root}/adapter-work"
    "COVERAGE_QUALIFICATION_POLICY=${fixture_root}/policy.json"
    "COVERAGE_QUALIFICATION_TOOL=${flow_root}/ci/coverage_qualification.py"
)
expect_failure "Coverage source verilator_sim must have PASS status" \
    env "${adapter_environment[@]}" "${flow_root}/flows/coverage/run.sh"
test "$(<"${fixture_root}/adapter-reports/coverage_qualification/status.txt")" = FAIL

env \
    MOSAIC_FLOW_IDS=coverage_qualification \
    FLOW_coverage_qualification=disabled \
    FLOW_DEPENDENCIES_coverage_qualification= \
    DISABLED_FLOWS=coverage_qualification \
    REPORT_DIR="${fixture_root}/skip-reports" MODULE_ROOT="${fixture_root}" \
    "${flow_root}/ci/run_flow.sh" coverage_qualification false >/dev/null
test "$(<"${fixture_root}/skip-reports/coverage_qualification/status.txt")" = SKIP

python3 - "${fixture_root}/reports/complete.json" <<'PY'
import json
import pathlib
import sys

summary = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert summary["status"] == "PASS"
assert summary["metrics"]["toggle"] == {
    "excluded": 1,
    "hit": 1,
    "passed": True,
    "percent": 100.0,
    "threshold": 100,
    "total": 1,
}
assert summary["coverpoints"][0]["hits"] == 3
assert summary["exclusions"][0]["matched_records"] == 1
assert summary["formal"] == {
    "reached_statements": 0,
    "required": False,
    "status": "SKIP",
}

failure = json.loads(
    pathlib.Path(sys.argv[1]).with_name("threshold.json").read_text(encoding="utf-8")
)
assert failure["status"] == "FAIL"
assert failure["failures"] == [
    "toggle coverage 50.00% is below threshold 100%"
]
PY

echo "Coverage qualification policy tests passed"
