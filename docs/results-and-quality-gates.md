# Results and quality gates

## Generated directory contract

Flows execute from `MODULE_ROOT` and separate reviewable evidence from
disposable databases:

```text
reports/<canonical-flow-id>/
work/<canonical-flow-id>/
```

`REPORT_DIR` and `WORK_DIR` may relocate these roots. Reports contain status,
logs, and compact summaries. Work directories contain generated executables,
netlists, proof databases, and tool state.

Named parameter profiles add a namespace before the flow ID:

```text
reports/<profile>/<flow-id>/
work/<profile>/<flow-id>/
```

Multi-module repositories use `<module>/<profile>/<flow-id>`. Every selected
profile records `parameter-profile.json`, while `all-profiles` records the
cross-profile `parameter-profile-summary.json` at the unqualified report root.
See [Parameter-profile qualification](parameter-profiles.md).

`make clean` removes the complete work tree and every item below `reports/`
except `.gitkeep`. It is idempotent and succeeds when either generated root does
not exist, including on a fresh module checkout.

## Status contract

Every flow that reaches normal adapter execution records one of these values in
`status.txt`:

| Status | Meaning | Accepted by a gate |
| --- | --- | --- |
| `PASS` | An enabled tool completed and met adapter policy | Yes for enabled flow |
| `FAIL` | The tool was attempted and failed | No |
| `SKIP` | The flow is explicitly disabled by resolved policy | Yes only for disabled flow |
| `BLOCKED` | At least one declared dependency was not `PASS` | No |
| Missing | No usable execution evidence exists | No |

The expected status is exact. A stale `PASS` for a now-disabled flow fails the
gate because the current policy requires explicit `SKIP`. An unapproved `SKIP`
for an enabled flow also fails.

Early setup errors, such as a missing OpenROAD checkout or PrimePower activity
file, can occur before the adapter creates a final status. The resulting missing
status is still a hard gate failure and the terminal diagnostic identifies the
missing input.

Disabled execution writes `skip_reason.txt`. Dependency blocking writes
`block_reason.txt`. A later eligible run removes stale skip and block reasons
before launching the adapter.

## Why both Make and report dependencies exist

GNU Make encodes dependency edges so prerequisites run before a requested flow,
including parallel builds. The runner independently reads dependency status
files and permits execution only after every prerequisite records `PASS`.

This double check prevents a dependent stage from consuming missing or failed
artifacts when a script is called directly, a previous run was interrupted, or
the dependency graph and filesystem are temporarily inconsistent.

## Open-source quality gate

`make open-quality-gate` validates these canonical IDs:

- `verible_lint`
- `verible_format`
- `slang_elaboration`
- `verilator_lint`
- `yosys_synthesis`
- `symbiyosys_formal`
- `eqy_equivalence`
- `verilator_sim`
- `pyuvm_open_source`

`make open-source` runs these targets and then the gate. PyUVM is disabled by
default and therefore records `SKIP` unless the module enables it. Once enabled,
its open-source result must be `PASS`. `openroad` is optional and intentionally
outside this portable gate.

## Commercial quality gate

`make synopsys-quality-gate` validates:

- `vcs_sim`
- `vc_lint`
- The CDC ID selected by `CDC_TOOL`
- `sg_dft`
- `vc_lp`
- `synopsys_synthesis`
- `synopsys_primetime`
- `synopsys_primepower`

`make synopsys-all` builds this result set and then applies the gate. Commercial
tool availability is checked for enabled flows only.

## Waiver policy

A waiver changes acceptance policy and must be treated as reviewed source, not
generated output.

Every module waiver should identify:

- Tool and rule or message ID
- Narrow source, instance, or object scope
- Technical justification
- Owner
- Approval reference
- Expiration condition or review date

Use `make open-waiver-draft` only to discover candidate Verilator control-file
entries. Review and narrow every entry before adding it to the module-owned
waiver file. The generated draft is not accepted automatically.

Shared methodology should not contain module-specific waivers. A method-level
exception is appropriate only when it applies to every consumer and has been
qualified by the fixture and representative modules.

## GitHub Actions behavior

The repository workflow at `.github/workflows/flow-quality.yml` qualifies the
methodology itself on pushes, pull requests, and manual dispatches.

The static methodology job runs:

- Bash syntax validation
- ShellCheck on shell sources
- actionlint on GitHub workflow files
- Semantic `VERSION` validation
- Required pinned-version field validation
- A check for module-specific identifiers in shared flow code
- Permission checks for non-executable data files
- Configuration, dependency, and quality-gate failure tests

The fixture integration job runs:

```sh
make -C tests/fixture-module FLOW_ROOT="$GITHUB_WORKSPACE" clean open-source
make -C tests/fixture-multi-module FLOW_ROOT="$GITHUB_WORKSPACE" clean all-modules MODULE_JOBS=2
make -C tests/fixture-parameter-profiles FLOW_ROOT="$GITHUB_WORKSPACE" clean all-profiles PROFILE_JOBS=4
```

It caches pinned tools and uploads fixture reports even when the flow fails. The
fixture is deliberately independent of `mosaic-module-template`, so the
methodology can prove its own consumer contract before release.

The multi-module fixture independently qualifies named and fallback input
resolution, module-specific policy loading, formatter options, isolated work
and reports, aggregate failure propagation, and deterministic CI matrix output.

The parameter-profile fixture qualifies a minimum width, nominal width, feature
toggle, and elaboration-only profile. It checks profile-local synthesis,
formal, simulation, PyUVM, and EQY evidence, plus explicit `SKIP` results for
flows outside the elaboration-only policy. Its negative tests require aggregate
failure for failed, blocked, and missing profile evidence.

The fixture keeps `PROPERTY_FILELIST`, `ASSERTION_FILELIST`, and
`COVERAGE_FILELIST` separate, then uses each list in its normal testbench,
PyUVM environment, and formal tasks. Assertion and coverage wrappers include
the same module-specific property library, which composes a separate sequence
library. The integration test therefore
qualifies each verification source across simulation and formal instead of
maintaining flow-specific copies. The formal cover task must reach all fixture
cover statements. Both simulation paths export native coverage,
while PyUVM also writes separate Python functional coverage. A second negative
run injects a SystemVerilog assertion failure and requires the PyUVM adapter to
retain `FAIL`.

## Release evidence

A module release should retain enough information to reproduce and review the
decision. At minimum, record:

- Module Git revision
- `mosaic-flow` Git revision and semantic version
- Tool names and versions
- Flow configuration and selected CDC engine
- Constraint, UPF, and waiver revisions
- PDK, libraries, operating condition, and analysis corner where applicable
- Status and principal reports for every enabled flow
- Test identity, seed policy, and functional coverage summary
- Formal properties and proof status
- Activity source and annotation coverage for power analysis
- Date and execution environment

Generated databases and full logs should normally be stored as CI or release
artifacts. Small reviewed manifests and source-controlled waiver records belong
in Git. Do not commit licensed libraries, credentials, or large work databases.

## Interpreting failures

1. Read `status.txt`.
2. For `BLOCKED`, read `block_reason.txt` and repair the prerequisite first.
3. For `FAIL`, read the flow-specific log named in the [flow catalog](flows.md).
4. Run `make flow-config-check` when expected policy and recorded status differ.
5. Remove stale generated state with `make clean` when reproducing a release
   gate from scratch.

A quality gate is an evidence validator. It does not determine whether a test
plan is sufficient, a formal property set is complete, a waiver is justified,
or a power workload is representative. Those remain engineering review duties.
