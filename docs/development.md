# Methodology development

## Scope of a methodology change

Change `mosaic-flow` when behavior should apply consistently to multiple module
repositories. Keep design names, RTL paths, constraints, UPF, formal properties,
and waivers in the consuming module.

Examples that belong here:

- A new reusable tool adapter
- A corrected quality-gate rule
- A pinned open-source tool update
- A new status or report contract
- Shared dependency validation
- A generic improvement to installation or CI

Examples that belong in a module:

- A new clock declaration
- A waiver for one RTL instance
- A module-specific formal assumption
- A selected OpenROAD die area
- A library or PDK path

## Local repository checks

Before proposing a change, run the same two layers used by GitHub Actions.

Static methodology quality:

```sh
ci/install_ci_tools.sh "$HOME/.local"
PATH="$HOME/.local/bin:$PATH" ci/check_flow_quality.sh
```

Complete portable fixture integration:

```sh
make -C tests/fixture-module FLOW_ROOT="$PWD" clean open-source
tests/test_release_manifest.sh
tests/test_coverage_qualification.sh
```

Review `tests/fixture-module/reports/` when integration fails. Do not use the
separate module template as the only methodology test because it may pin a
different flow revision.

## Adding a flow

1. Choose a lowercase canonical ID containing only letters, digits, and
   underscores.
2. Add it to `MOSAIC_FLOW_IDS` in `config/flows.mk`.
3. Add `FLOW_<id> ?= enabled` or a deliberately reviewed default.
4. Add `FLOW_DEPENDENCIES_<id> ?=` with direct artifact dependencies.
5. Add a public Make target and `FLOW_TARGET_<id>` mapping in `mk/module.mk`.
6. Add a shared adapter below `flows/<flow-name>/`.
7. Place all design-specific inputs in the consumer's mirrored `flows/`
   directory and expose their paths through `config/design.mk`.
8. Ensure the adapter writes logs and one final status below
   `reports/<canonical-id>/`.
9. Decide whether the flow belongs to an aggregate quality gate.
10. Add positive and negative coverage to `tests/test_quality_gate.sh`.
11. Extend `tests/fixture-module/` when the flow can run portably.
12. Document the ID, target, inputs, outputs, dependencies, and upstream tool
   documentation in [Flow catalog](flows.md).

Prefer `ci/run_flow.sh` for execution eligibility and `run_and_record` from
`flows/common/env.sh` for adapters that can use a single command. An adapter
with multiple stages may manage its own `FAIL` and `PASS` transitions, as the
simulation and Yosys adapters do.

## Adapter requirements

Every adapter must:

- Use `set -euo pipefail`, directly or through `flows/common/env.sh`
- Consume exported module variables rather than hard-coded design identifiers
- Execute from a documented working directory
- Preserve the tool's nonzero exit status through logging
- Write an initial or failure status before a long tool run
- Write `PASS` only after required output files and policy checks succeed
- Keep reviewable logs in `REPORT_DIR`
- Keep generated databases and large artifacts in `WORK_DIR`
- Reject unsupported file-list entries or options explicitly
- Avoid embedding licenses, credentials, PDK paths, or module waivers

The static repository check searches shared implementation directories for
fixture-specific identifiers. Add generic environment variables when a new
design input is required.

## Updating dependencies

Add a dependency when a flow consumes an artifact produced by another flow or
when project policy requires a successful prerequisite. Use canonical IDs only.

Update all of these together:

- Shared default in `config/flows.mk`
- Make target mapping in `mk/module.mk` when adding a new ID
- Fixture project configuration
- Dependency validation tests
- Flow catalog and architecture documentation

Verify serial and parallel execution:

```sh
make -C tests/fixture-module FLOW_ROOT="$PWD" clean open-equivalence
make -C tests/fixture-module FLOW_ROOT="$PWD" clean -j4 open-source
```

A dependency must record `PASS`. `SKIP` is not sufficient because a dependent
flow cannot safely consume an artifact that was intentionally not produced.

## Updating open-source tools

Pinned releases live in `config/tool-versions.env`. Installers live under
`ci/`. A version update must:

1. Use an immutable upstream release identifier.
2. Update the archive checksum when the installer downloads an archive.
3. Preserve versioned cache paths so old and new revisions can coexist.
4. Run static repository checks.
5. Run the complete fixture integration from an empty or isolated cache.
6. Qualify representative real modules for language and warning changes.
7. Update documentation when supported platforms or commands change.
8. Increment `VERSION` according to compatibility impact.

Never replace checksum verification with an unverified download. Do not use a
floating `latest` release in the portable gate.

## Qualifying commercial adapters

The Tcl adapters for VC Lint, VC CDC, SpyGlass CDC, SpyGlass DFT, and VC LP
currently fail deliberately. This prevents a placeholder from being mistaken
for signoff.

For each installed release:

1. Obtain the command reference and recommended goals from licensed Synopsys
   documentation.
2. Read RTL through `RTL_FILELIST` and elaborate `DESIGN_TOP`.
3. Load the module-owned constraint path exported by `config/design.mk`.
4. Define the approved goals, severity mapping, and waiver mechanism.
5. Write compact summary and detailed violation reports to the canonical report
   directory.
6. Convert every unwaived release-blocking violation into a nonzero exit.
7. Test a known-clean fixture or representative module.
8. Inject at least one known violation and prove the adapter fails.
9. Record the qualified tool release, site setup, and policy revision.
10. Remove the deliberate Tcl `error` only after those checks pass.

Command APIs can vary between releases. Keep release-specific behavior isolated
inside the corresponding Tcl adapter rather than leaking it into module
Makefiles.

Design Compiler, PrimeTime, and PrimePower adapters are implemented, but they
still require site qualification with real libraries, corners, constraints, and
representative activity.

## Testing quality-gate behavior

`tests/test_quality_gate.sh` covers failure semantics without requiring EDA
tools. Extend it whenever configuration or status behavior changes.

The test suite should continue to reject:

- Invalid flow states
- Unknown disabled IDs
- Unknown dependency IDs
- Self dependencies
- Cycles
- Enabled flows with disabled dependencies
- Missing dependency reports
- Failed required flows
- Unauthorized skips
- A stale pass where policy expects a skip

Add a focused regression for each bug fixed in orchestration or gate logic.

## Workflow quality

`.github/workflows/flow-quality.yml` must remain independent from private module
repositories. It uses `tests/fixture-module/` and qualifies both shell-level
policy and the complete portable EDA path.

`tests/fixture-multi-module/` separately qualifies registry validation,
selection, fallback resolution, concurrent execution, and output isolation.
Update `tests/test_multi_module.sh` whenever the manifest or project bootstrap
contract changes.

`tests/fixture-parameter-profiles/` qualifies boundary widths, feature toggles,
backend parameter translation, profile-local formal and equivalence inputs,
concurrent execution, and aggregate evidence. Update
`tests/test_parameter_profiles.sh` whenever the profile schema changes.

`tests/test_release_manifest.sh` builds a temporary consumer repository and
qualifies manifest generation, deterministic comparison, input hashing,
approved skips, supplemental gates, dirty-tree policy, and negative status and
revision handling. The workflow runs it both natively and in the pinned
container job. Extend this fixture whenever the release schema or policy
changes.

`tests/check_fixture_release_manifest.sh` checks the complete portable fixture
after real tool execution. It requires every canonical flow decision, portable
tool identity, representative design input, both coverage classes, and the
human-readable summary to be present in the generated release artifact.

`tests/test_coverage_qualification.sh` exercises complete and deficient HDL
evidence, malformed requirements, valid and stale exclusions, missing named
coverpoints, formal reachability failure, and explicit flow statuses. The
workflow runs this fixture both natively and in the pinned container job.
`tests/test_coverage_unreachable_formal.sh` additionally runs a deliberately
unreachable cover statement through SymbiYosys in the EDA integration job and
requires the canonical flow to record `FAIL` before restoring passing evidence.

`tests/test_qualification_campaigns.sh` exercises detected and escaped
mutations, expected inequivalence, unrelated tool failure, detected unknown
controls, a broken monitor, failed controls, and explicit disabled statuses.
The complete fixture additionally compiles and runs an X/Z campaign with the
pinned Icarus simulator. Both methodology fixtures run in native CI, while the
tool-independent positive and negative cases also run in the pinned container.

`tests/test_static_intent.sh` covers sequential, combinational, generated-clock,
reset-synchronizer, always-on, isolation, level-shifting, and retention intent.
Its negative cases require actionable failures for missing constraints, broad
exceptions, duplicates, conflicts, profile mismatches, incomplete power states,
forbidden strategies, and unsupported commands. The same test runs natively and
inside the pinned container without an EDA license.

When editing workflow YAML or shell scripts, run `ci/check_flow_quality.sh`. It
uses pinned ShellCheck and actionlint versions installed by
`ci/install_ci_tools.sh`.

Commercial tools must not be added to GitHub-hosted jobs. A future self-hosted
commercial qualification workflow must use explicit runner labels, protected
credentials, license controls, and no public artifact containing proprietary
technology data.

## Documentation maintenance

Update documentation in the same change when modifying:

- Public Make targets
- Canonical IDs or aggregate gate membership
- Status semantics
- Default states or dependencies
- Required or optional variables
- Report and work products
- Tool versions or supported platforms
- Commercial adapter readiness

Relative links to source adapters are preferred for repository internals.
External links should point to official project or vendor documentation.

## Versioning and release

`VERSION` contains a semantic version such as `1.2.3`.

- Increment the patch version for compatible fixes and documentation corrections.
- Increment the minor version for backward-compatible flows, targets, or inputs.
- Increment the major version when a consumer must change its Makefile,
  configuration contract, status interpretation, or required policy.

A release candidate is ready only after:

1. The worktree contains only intended changes.
2. Static methodology quality passes.
3. The complete fixture open-source gate passes.
4. Changed commercial adapters are qualified in the licensed environment.
5. Documentation matches implementation.
6. `VERSION` reflects compatibility impact.
7. The release commit and tag are immutable.

After release, a module updates its pinned submodule revision and reruns its own
portable and commercial acceptance flows. Changing the gitlink is a methodology
upgrade and should receive the same review as a tool or constraint change.

## Review checklist

- Is the change generic across module repositories?
- Does it preserve the module and methodology ownership boundary?
- Are failures propagated and recorded?
- Are new variables documented and validated?
- Are dependencies explicit and acyclic?
- Are waivers module-owned and narrowly scoped?
- Are tool versions immutable and verified?
- Do negative tests prove that violations fail?
- Does the fixture remain independent from the module template?
- Can a new engineer find the target, inputs, outputs, and upstream manual?
