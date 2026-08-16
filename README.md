# mosaic-flow

Shared RTL quality and implementation methodology for MOSAIC repositories. It
provides one versioned interface for open-source CI checks and licensed local
implementation flows.

Modular repositories consume `mosaic-flow` at a pinned Git revision, normally as
an in-tree `mosaic-flow/` submodule. Updating that pointer upgrades the
methodology without copying flow scripts or changing module RTL.

## What belongs here

`mosaic-flow` owns reusable methodology:

- Make targets and flow dependency orchestration
- Open-source and Synopsys tool adapters
- Flow selection, statuses, reports, and quality gates
- Pinned open-source tool installers and versions
- Methodology CI and its independent fixture module

The consuming module owns RTL, verification, file lists, constraints, waivers,
formal properties, power intent, and design-specific flow configuration.

## Documentation

The [documentation index](docs/README.md) is the detailed entry point for new
users and contributors. It provides a recommended reading order, a command
reference, and links to:

- Repository architecture and ownership boundaries
- Consumer setup and configuration overrides
- Every open-source and commercial flow
- Results, quality gates, waivers, and release evidence
- Methodology development, qualification, and release procedures

## Consumer quick start

From a module repository with the submodule already configured:

```sh
git submodule update --init --recursive
make flow-config-check
make open-source
```

The module's thin Makefile imports the shared API:

```make
export MODULE_ROOT := $(CURDIR)
export FLOW_ROOT ?= $(abspath $(MODULE_ROOT)/mosaic-flow)

include config/design.mk
include $(FLOW_ROOT)/config/tools.mk
include $(FLOW_ROOT)/mk/module.mk
```

See [Getting started](docs/getting-started.md) for the complete module contract
and [Configuration](docs/configuration.md) for flow selection, dependencies,
tool overrides, and technology setup.

## Methodology validation

Before releasing a change to this repository, run its static checks and the
complete portable fixture flow:

```sh
ci/install_ci_tools.sh "$HOME/.local"
PATH="$HOME/.local/bin:$PATH" ci/check_flow_quality.sh
make -C tests/fixture-module FLOW_ROOT="$PWD" clean open-source
```

GitHub Actions runs the same validation on pushes and pull requests. Commercial
Synopsys tools are not run on GitHub-hosted runners. Release-specific commercial
adapters must be configured and qualified in the licensed local environment.

See [Methodology development](docs/development.md) for the full contribution and
release checklist.
