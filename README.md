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
