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

`make open-source` runs these targets and then the gate. `openroad` is optional
and intentionally outside this portable gate.

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
```

It caches pinned tools and uploads fixture reports even when the flow fails. The
fixture is deliberately independent of `mosaic-module-template`, so the
methodology can prove its own consumer contract before release.

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
