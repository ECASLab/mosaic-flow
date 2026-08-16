# mosaic-flow

Shared RTL quality and implementation methodology for MOSAIC module
repositories. It is maintained as a sibling of the module repositories and is
intended to become an independently versioned GitHub repository.

## Ownership

`mosaic-flow` owns:

- Open-source and Synopsys tool adapters
- Quality gates and report contracts
- Tool installation scripts and pinned versions
- Shared Make targets
- OpenROAD integration

The consuming module owns its RTL, verification, file lists, constraints,
waivers and design-specific formal, equivalence and OpenROAD configurations.

## Consumer contract

The module Makefile exports `MODULE_ROOT`, sets `FLOW_ROOT`, includes its own
`config/design.mk`, and then includes:

```make
include $(FLOW_ROOT)/config/tools.mk
include $(FLOW_ROOT)/mk/module.mk
```

All flows execute from `MODULE_ROOT`, place generated data in the module's
`work/` and `reports/` directories, and use module-owned configuration paths.
Portable Make targets automatically install missing pinned open-source tools
under `${XDG_CACHE_HOME:-$HOME/.cache}/mosaic`. Set `MOSAIC_TOOLS_ROOT` to use a
different shared cache, or run `make setup-open-source` to prepare it without
starting a check.

## Flow selection

Shared defaults are defined in `mosaic-flow/config/flows.mk`. A consuming module
overrides them in its own `config/flows.mk` using explicit states:

```make
FLOW_symbiyosys_formal := disabled
FLOW_eqy_equivalence := disabled
```

`mosaic-flow/mk/module.mk` loads both files, validates every state, and derives
the internal `DISABLED_FLOWS` list. Every disabled target records `SKIP` and a
reason under its normal report directory. Quality gates accept `SKIP` only for
flows disabled by the project configuration and continue to require `PASS` from
every enabled flow. `DISABLED_FLOWS` remains available as a command-line
override for compatibility and diagnostics.

Flow dependencies use canonical flow IDs in the same files:

```make
FLOW_DEPENDENCIES_eqy_equivalence := yosys_synthesis
FLOW_DEPENDENCIES_synopsys_primepower := vcs_sim synopsys_synthesis
```

The shared defaults describe artifact dependencies and a module may replace any
list. `make flow-config-check` rejects unknown flows, self dependencies, cycles,
and enabled flows that depend on disabled flows. Make builds the resulting graph
before running a target, so prerequisites must finish successfully even with
parallel execution. The flow runner also requires every dependency report to
contain `PASS`. Otherwise, it records `BLOCKED` and does not launch the tool.

Canonical open-source IDs are `verible_lint`, `verible_format`,
`slang_elaboration`, `verilator_lint`, `yosys_synthesis`,
`symbiyosys_formal`, `eqy_equivalence`, `verilator_sim`, and `openroad`.
Canonical commercial IDs are `vcs_sim`, `vc_lint`, `vc_cdc`, `sg_cdc`,
`sg_dft`, `vc_lp`, `synopsys_synthesis`, `synopsys_primetime`, and
`synopsys_primepower`. The `cdc` alias disables either selected CDC engine.

`FORCE_FLOW=1` may execute an individually disabled target for diagnostics. It
does not change the project policy, so the aggregate quality gate still expects
that flow to be recorded as `SKIP`.

## Repository quality

`.github/workflows/flow-quality.yml` validates this methodology on every push
and pull request. Its static job runs Bash syntax checks, ShellCheck, actionlint,
version-manifest validation, permission checks and quality-gate failure tests.
Its integration job runs the complete open-source flow against
`tests/fixture-module` and uploads the resulting reports.

The fixture is intentionally independent of `mosaic-module-template`. Changes
to flow scripts or pinned tool versions are therefore qualified inside this
repository before a module updates its `mosaic-flow` revision.

Synopsys tools are not executed by GitHub-hosted runners. Release-specific
Synopsys adapters that still contain an explicit `error` are placeholders and
must be configured and qualified in the licensed local environment.

## Future repository

After publishing this directory as `mosaic-flow`, pin each workspace checkout to
a release tag or commit SHA. Updating that revision then updates the methodology
and tool-version manifest without modifying module RTL or constraints.
