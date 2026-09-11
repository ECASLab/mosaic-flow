# Coverage qualification

## Purpose

`make open-coverage` converts collected HDL coverage into an explicit release
decision. The module declares goals and reviewed exclusions in
`config/coverage-policy.json`. `mosaic-flow` validates that policy, normalizes
the simulator evidence, applies the requirements, and writes a deterministic
`reports/coverage_qualification/summary.json`.

The flow is optional and disabled by default. Enable it in `config/flows.mk`:

```make
FLOW_coverage_qualification := enabled
FLOW_DEPENDENCIES_coverage_qualification := verilator_sim
```

Point `COVERAGE_QUALIFICATION_POLICY` at a different module-owned path only when
the repository layout requires it. The policy is included in release input
hashes whenever the flow is enabled.

## Coverage layers

The verification layers remain separate because they answer different
questions:

| Layer | Meaning | Qualification behavior |
| --- | --- | --- |
| Assertions | Required temporal behavior checked during execution | Failure remains a simulation or formal failure |
| Named SVA coverpoints | Whether important temporal scenarios occurred | Minimum hits are checked by name |
| Native HDL line, branch, toggle, and user coverage | Structural activity measured by the HDL simulator | Independent percentage thresholds are checked |
| Formal cover | Whether declared cover statements are reachable under assumptions | Required SymbiYosys cover task must return `PASS` |
| PyUVM functional coverage | Python transaction-level model | Preserved as separate evidence and never merged into HDL percentages |

PyUVM does not invoke SVA. The PyUVM adapter compiles the same property,
assertion, and coverage filelists as the normal HDL testbench. The simulator
evaluates those constructs while Python drives the DUT. Either run can therefore
produce compatible native HDL evidence for this gate.

## Policy format

The policy follows `schemas/coverage-policy-v1.schema.json`. The implementation
also performs semantic validation and rejects unknown fields, duplicate named
requirements, invalid ranges, missing exclusion sources, and stale exclusions.

```json
{
    "schema": "mosaic-coverage-policy-v1",
    "scope": {
        "include": ["rtl/*.sv", "verif/coverage/*.sv"],
        "exclude": []
    },
    "thresholds": {
        "line": 95,
        "branch": 90,
        "toggle": 80,
        "user": 100
    },
    "coverpoints": [
        {"name": "accepted_transaction", "minimum_hits": 2}
    ],
    "exclusions": [
        {
            "source": "rtl/example.sv",
            "metric": "toggle",
            "reason": "Static strap is fixed by the supported integration mode.",
            "owner": "module-maintainers",
            "scope": {"line_start": 27, "name": "test_mode_i:0->1"}
        }
    ],
    "formal": {"required": true}
}
```

Each threshold is optional and independent. An omitted metric is reported but
does not gate the result. A declared threshold fails when no counters of that
metric remain in scope. `scope.include` and `scope.exclude` use module-relative
shell globs and should keep structural thresholds focused on the intended RTL.

Named coverpoints use the SystemVerilog statement label emitted as the native
`user` counter name. Every declaration requires at least one matching native
counter and its aggregate hit count must meet `minimum_hits`.

Every exclusion records a real module-relative source, one metric, a technical
reason, an accountable owner, and a narrow scope. `line_start`, optional
`line_end`, and optional exact counter `name` can be combined. An exclusion that
matches no in-scope collected counter is stale and fails qualification. Explicit
named-coverpoint requirements remain enforced even if a user counter is
excluded from the percentage calculation.

## Evidence source

Normal Verilator simulation is the default:

```make
COVERAGE_QUALIFICATION_SOURCE := verilator_sim
FLOW_DEPENDENCIES_coverage_qualification := verilator_sim
```

To qualify the HDL coverage generated while PyUVM drives the DUT:

```make
COVERAGE_QUALIFICATION_SOURCE := pyuvm_open_source
FLOW_DEPENDENCIES_coverage_qualification := pyuvm_open_source
```

The selected source must have `PASS` status and must provide `coverage.dat`,
`coverage.info`, or both. `coverage.dat` supplies typed Verilator counters and
is required for named user coverpoints. LCOV supplies portable line records and
is a fallback for branch and toggle counters when typed native records are not
available. The parser uses record metadata rather than version-specific page
names. LCOV transition names containing `->` are treated as toggles instead of
control-flow branches.

Use a dedicated rerun when qualification needs different compile options:

```make
COVERAGE_QUALIFICATION_SOURCE := dedicated
FLOW_DEPENDENCIES_coverage_qualification :=
```

The adapter runs the existing testbench through the shared Verilator simulation
adapter with coverage forced on and stores source evidence below
`reports/coverage_qualification/dedicated/`.

## Formal reachability

When `formal.required` is true, `FORMAL_COVER_CONFIG` is mandatory. The adapter
runs that configuration in an isolated qualification work directory. SymbiYosys
cover mode returns `PASS` only when its generated cover tasks meet the configured
reachability goal, so any unreachable statement fails the combined result. A
passing run must also report at least one reached cover statement.

The summary records formal status separately from simulation metrics. It does
not merge bounded formal reachability into simulator hit counts. Depth, engines,
assumptions, and completeness remain module-owned review concerns.

## Reports and release evidence

The canonical status is one of `PASS`, `FAIL`, or `SKIP`. Enabled malformed
policies, missing counters, stale exclusions, unmet thresholds, missing named
points, and failed formal reachability produce `FAIL`. Explicitly disabling the
flow through normal flow policy produces `SKIP`.

`summary.json` records effective totals, hits, percentages, thresholds,
exclusion match counts, named coverpoint hits, formal status, and every failure.
The release manifest automatically indexes this summary as
`coverage_qualification_summary`. Because the flow is canonical, an enabled
release also requires its `status.txt` to be `PASS`.

## Simulator limitations

- Verilator native coverage is the qualified open-source source for typed user
  and toggle counters. Other native formats require a future adapter.
- Some Verilator LCOV releases represent toggles as `BRDA` records. The native
  type takes precedence when available.
- LCOV alone does not reliably preserve named SVA user coverpoints. Policies
  declaring `coverpoints` therefore need compatible native evidence.
- An Icarus PyUVM run does not currently produce compatible HDL coverage and
  cannot feed this gate.
- Commercial coverage databases and cross-simulator database merging are out of
  scope. They may be retained as additional release evidence without replacing
  this open-source gate.
