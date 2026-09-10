# Release evidence

## Purpose

`make release-manifest` turns the distributed results below `REPORT_DIR` into
one auditable qualification record. It does not rerun flows and it does not
replace engineering review. It validates the resolved flow policy, rejects
incomplete required evidence, hashes release inputs, records tool versions, and
indexes compact module-owned evidence.

The versioned JSON contract is
[`schemas/release-evidence-v1.schema.json`](../schemas/release-evidence-v1.schema.json).
The generator performs the same structural and semantic checks without adding a
third-party Python dependency.

## Generate a manifest

Run all checks required by the module policy first. Then generate and validate
the evidence:

```sh
make open-source
make synopsys-all
make \
  MODULE_REVISION="$(git rev-parse HEAD)" \
  METHODOLOGY_REVISION="$(git -C mosaic-flow rev-parse HEAD)" \
  release-manifest release-manifest-validate
```

Both revisions must be full 40-digit commit IDs when `CI=true`. They may be
omitted during local development, in which case the generator resolves each
repository's `HEAD`. A dirty module or methodology checkout fails by default. A local
diagnostic may set `RELEASE_ALLOW_DIRTY=enabled`, and the resulting manifest
records the dirty state. Do not publish that manifest as qualified release
evidence.

When a container copies source without its `.git` directory, Git cannot inspect
that tree. An immutable image build may explicitly attest
`RELEASE_MODULE_DIRTY=false` or `RELEASE_METHODOLOGY_DIRTY=false` for the
packaged tree. Set the value to `true` when the packaged source included local
changes. Invalid values and unavailable repositories without an attestation
fail closed. Prefer automatic Git inspection whenever metadata is present.

Outputs are context-specific:

```text
reports/release_manifest/native/
|-- manifest.json
|-- status.txt
`-- summary.txt
```

Selected modules and parameter profiles keep the same directory qualification
already applied to `REPORT_DIR`. Set `RELEASE_EXECUTION_CONTEXT=container` for
a required container run. Native and container evidence then coexist instead
of overwriting each other.

## Acceptance policy

The manifest evaluates every canonical ID from `MOSAIC_FLOW_IDS`:

- An enabled flow must have `status.txt` containing exactly `PASS`.
- A disabled flow is recorded as an approved `SKIP`. Its status file may be
  absent, or it may contain exactly `SKIP`.
- `FAIL`, `BLOCKED`, an unauthorized `SKIP`, a stale `PASS` for disabled policy,
  and missing enabled-flow evidence reject the manifest.

Module-owned checks use the same fail-closed status contract:

```make
export RELEASE_SUPPLEMENTAL_GATES := \
    constraint_check \
    assertion_coverage \
    fault_injection
```

Each registered gate must provide `$(REPORT_DIR)/<gate>/status.txt` containing
`PASS`. This mechanism supports qualification policy without adding
module-specific logic to `mosaic-flow`.

## Inputs and hashes

The Make API automatically declares the selected design and flow
configuration, module and parameter-profile manifests, known filelists,
constraints, waivers, formal and equivalence configuration, OpenROAD setup,
CDC and DFT intent, UPF, and PyUVM sources. Every discovered file is recorded
with a repository-relative path and SHA-256 digest.

Filelists are traversed recursively. The parser accepts source paths,
`+incdir+`, `+define+`, and nested `-f` or `-F` entries. Missing declared files,
empty declared directories, paths outside `MODULE_ROOT`, and unsupported
filelist options fail generation. Generated `__pycache__`, `.pyc`, and `.pyo`
files are excluded from directory inputs.

Add reviewed release inputs such as a checklist or workload definition with:

```make
export RELEASE_ADDITIONAL_INPUTS := \
    docs/dff/release-checklist.md \
    verif/vectors/release
```

Add compact generated evidence, rather than large databases, with:

```make
export RELEASE_ADDITIONAL_EVIDENCE := \
    $(REPORT_DIR)/constraint_check/summary.json \
    $(REPORT_DIR)/fault_injection/summary.json
```

## Tools and coverage

The manifest queries the exact enabled portable tools configured by the Make
API. It records stable tool names, commands, versions, and associated flows in
the deterministic section. Host-specific executable paths are kept in the
volatile execution section.

When PyUVM is enabled, `versions.log` supplies separate Python, PyUVM, cocotb,
and simulator records. The version log itself is hashed. Native SystemVerilog
coverage databases and reports are indexed separately from
`functional-coverage.json`, so Python functional coverage is never confused
with HDL coverage. When the canonical coverage gate runs, its
`coverage_qualification/summary.json` is indexed as a separate qualification
decision alongside the underlying databases.

Register another tool version command with JSON:

```make
export RELEASE_ADDITIONAL_TOOLS_JSON := \
    [{"name":"custom_analyzer","command":["custom-analyzer","--version"],"flows":[]}]
```

An empty `flows` list means the tool is always required. Otherwise, it is
recorded when at least one listed flow is enabled.

Additional coverage records use `kind`, `producer`, and a module-relative or
absolute in-repository path:

```make
export RELEASE_COVERAGE_EVIDENCE_JSON := \
    [{"kind":"formal_cover_summary","producer":"formal_review","path":"reports/formal_review/coverage.json"}]
```

## Technology and metadata

Describe a technology-independent run or the exact implementation context:

```make
export RELEASE_TECHNOLOGY := gf180mcu
export RELEASE_TECHNOLOGY_METADATA_JSON := \
    {"pdk_revision":"<revision>","library":"gf180mcu_fd_sc_mcu7t5v0","corner":"ss_125c"}
```

`RELEASE_METADATA_JSON` accepts deterministic module-owned data such as the
release checklist revision, workload, or seed policy.
`RELEASE_EXECUTION_METADATA_JSON` accepts volatile runner data such as a CI run
ID, image digest, or host label. All JSON variables must contain an object.

## Deterministic comparison

`manifest.json` has two top-level data sections:

- `deterministic` contains revisions, selected parameters, technology, flow and
  gate decisions, versions, input hashes, evidence hashes, and module metadata.
- `volatile` contains generation time, separate module and methodology dirty
  states, host details, executable
  locations, and execution metadata.

Compare `deterministic` when checking whether two executions qualified the
same inputs and policy. Compare `volatile.execution.context` and uploaded
artifacts when native and container execution are both release requirements.

## CI and release checklists

A release job should run required flows, generate the manifest with explicit
revisions, validate it, and upload the entire context directory even on later
job failure. Reference the archived `manifest.json` artifact and CI run from
the module's release checklist.

```yaml
- name: Generate release evidence
  run: |
    make \
      MODULE_REVISION="${GITHUB_SHA}" \
      METHODOLOGY_REVISION="$(git -C mosaic-flow rev-parse HEAD)" \
      RELEASE_EXECUTION_CONTEXT=container \
      release-manifest release-manifest-validate

- name: Upload release evidence
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: release-evidence-container
    path: reports/release_manifest/container/
```

For a multi-module repository, select `MODULE=<name>`. For a parameterized
module, also select `PROFILE=<name>`. Generate one manifest for every
module/profile/context combination required by the release checklist.

## Migrating module-owned scripts

Replace a custom release-manifest generator with the shared target:

1. Map custom status checks to `RELEASE_SUPPLEMENTAL_GATES`.
2. Map reviewed source artifacts to `RELEASE_ADDITIONAL_INPUTS`.
3. Map compact generated summaries to `RELEASE_ADDITIONAL_EVIDENCE`.
4. Move technology and release annotations into the JSON metadata variables.
5. Generate new evidence only after all required flow statuses exist.
6. Remove the duplicate script after native and container outputs have been
   compared against the previous release record.

The module retains ownership of its policy and evidence. The methodology owns
only validation, indexing, schema versioning, and the public target.
