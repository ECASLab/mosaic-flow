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
3. [Configuration](configuration.md) is the reference for module variables,
   flow states, dependencies, tools, and overrides.
4. [Flow catalog](flows.md) describes every open-source and commercial flow,
   including inputs, outputs, and upstream documentation.
5. [Results and quality gates](results-and-quality-gates.md) defines statuses,
   waivers, generated artifacts, CI behavior, and release evidence.
6. [Methodology development](development.md) explains how to change, test,
   qualify, version, and release this repository.

## Quick reference

| Goal | Command or location |
| --- | --- |
| List public targets | `make help` in a module repository |
| Validate resolved flow policy | `make flow-config-check` |
| Prepare pinned open-source tools | `make setup-open-source` |
| Run the portable quality gate | `make open-source` |
| Run one check | See the [flow catalog](flows.md) |
| Run all licensed local checks | `make synopsys-all` |
| Select or disable flows | Module `config/flows.mk` |
| Set design paths and names | Module `config/design.mk` |
| Inspect machine-readable status | Module `reports/<flow-id>/status.txt` |
| Add a methodology flow | [Methodology development](development.md#adding-a-flow) |

## Source of truth

The implementation is authoritative when documentation and code disagree. The
most important implementation entry points are:

- `config/flows.mk` for canonical flow IDs, default states, and dependencies
- `config/tools.mk` for executable defaults and the shared tool cache
- `mk/module.mk` for public Make targets and the dependency graph
- `ci/run_flow.sh` for execution eligibility and status recording
- `ci/*_quality_gate.sh` for acceptance policy
- `flows/<flow-name>/` for tool adapters
- `tests/fixture-module/` for repository-level integration coverage

Please update the relevant document in the same change whenever one of these
contracts changes.
