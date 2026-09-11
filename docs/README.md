# mosaic-flow documentation

This directory documents the shared MOSAIC RTL methodology. It is intended for
module owners, verification engineers, implementation engineers, CI
maintainers, and contributors to the methodology itself.

[Return to the repository overview](../README.md).

## Recommended reading order

1. [Getting started](getting-started.md) explains how to connect a module
   repository to `mosaic-flow` and run the first checks.
2. [Architecture](architecture.md) explains the repository hierarchy, ownership
   boundary, and execution model.
3. [Multi-module projects](multi-module-projects.md) defines manifests, module
   selection, concurrent execution, isolated evidence, and CI matrices.
4. [Parameter profiles](parameter-profiles.md) defines representative
   elaborations, backend overrides, evidence isolation, and profile matrices.
5. [Configuration](configuration.md) is the reference for module variables,
   flow states, dependencies, tools, and overrides.
6. [Flow catalog](flows.md) describes every open-source and commercial flow,
   including inputs, outputs, and upstream documentation.
7. [Coverage qualification](coverage-qualification.md) defines HDL thresholds,
   named coverpoints, reviewed exclusions, and formal reachability.
8. [Negative-test and four-state qualification](qualification-campaigns.md)
   defines declarative fault campaigns, controls, diagnostics, and evidence.
9. [Containerized OpenROAD](openroad.md) defines local and pinned-container
   execution, physical evidence policy, isolation, and the signoff boundary.
10. [Results and quality gates](results-and-quality-gates.md) defines statuses,
   waivers, generated artifacts, and CI behavior.
11. [Portable SDC and UPF intent](static-intent.md) defines the declarative
    constraint and power-intent gate and its signoff boundary.
12. [Release evidence](release-evidence.md) defines the manifest schema,
   acceptance policy, extension points, and release integration.
13. [Methodology development](development.md) explains how to change, test,
   qualify, version, and release this repository.

## Quick reference

| Goal | Command or location |
| --- | --- |
| List public targets | `make help` in a module repository |
| Validate resolved flow policy | `make flow-config-check` |
| Prepare pinned open-source tools | `make setup-open-source` |
| Run the portable quality gate | `make open-source` |
| Validate a module registry | `make module-manifest-check` |
| Generate a CI module matrix | `make module-matrix` |
| Run every registered module | `make all-modules TARGET=open-source` |
| Validate parameter profiles | `make profile-manifest-check` |
| Run every parameter profile | `make all-profiles PROFILE_TARGET=open-source` |
| Generate a module/profile matrix | `make module-profile-matrix` |
| Generate release evidence | `make release-manifest release-manifest-validate` |
| Run one check | See the [flow catalog](flows.md) |
| Run all licensed local checks | `make synopsys-all` |
| Select or disable flows | Module `config/flows.mk` |
| Set design paths and names | Module `config/design.mk` |
| Understand PyUVM and SVA reuse | [PyUVM, SVA, and coverage](getting-started.md#understand-pyuvm-sva-and-coverage) |
| Qualify HDL and formal coverage | [Coverage qualification](coverage-qualification.md) |
| Qualify known faults and X/Z controls | [Qualification campaigns](qualification-campaigns.md) |
| Validate portable SDC and UPF intent | `make open-static-intent` |
| Run pinned containerized OpenROAD | `make OPENROAD_EXECUTION_MODE=container open-physical` |
| Inspect machine-readable status | Module `reports/<flow-id>/status.txt` |
| Add a methodology flow | [Methodology development](development.md#adding-a-flow) |

## Source of truth

The implementation is authoritative when documentation and code disagree. The
most important implementation entry points are:

- `config/flows.mk` for canonical flow IDs, default states, and dependencies
- `config/tools.mk` for executable defaults and the shared tool cache
- `mk/module.mk` for public Make targets and the dependency graph
- `mk/project.mk` for multi-module selection and configuration loading
- `ci/module_manifest.py` for module registry validation and matrix generation
- `ci/parameter_profiles.py` for parameter translation and profile evidence
- `ci/release_manifest.py` for release evidence generation and validation
- `ci/static_intent.py` for non-executing SDC and UPF command capture
- `ci/openroad_evidence.py` for physical artifact and metric qualification
- `ci/run_flow.sh` for execution eligibility and status recording
- `ci/*_quality_gate.sh` for acceptance policy
- `flows/<flow-name>/` for tool adapters
- `tests/fixture-module/` for repository-level integration coverage
- `tests/fixture-multi-module/` for concurrent project orchestration coverage
- `tests/fixture-parameter-profiles/` for parameter-matrix qualification
- `tests/test_release_manifest.sh` for manifest acceptance-policy coverage

Please update the relevant document in the same change whenever one of these
contracts changes.
