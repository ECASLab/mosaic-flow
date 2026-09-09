# Multi-module projects

## Purpose

A multi-module repository can qualify related RTL blocks independently while
sharing one pinned `mosaic-flow` checkout. Each registered module owns its design
configuration and flow policy. The methodology owns registry validation,
selection, concurrent dispatch, and output isolation.

Single-module repositories do not need a manifest and may retain the original
import sequence. Adopt this interface only when one repository contains more
than one independently selectable design top.

## Import the project API

Use the project bootstrap instead of loading `config/design.mk` directly:

```make
SHELL := /usr/bin/env bash

export MODULE_ROOT := $(CURDIR)
export FLOW_ROOT ?= $(abspath $(MODULE_ROOT)/mosaic-flow)

include $(FLOW_ROOT)/mk/project.mk
```

`mk/project.mk` detects `MODULE_MANIFEST`, loads the selected module profile,
then imports the normal tool and target APIs. Its default manifest path is
`config/modules.json`.

## Declare the module registry

The `mosaic-modules-v1` schema uses a nonempty `include` array. Every entry
requires a unique lowercase `name`. Additional JSON fields are preserved in the
generated CI matrix.

```json
{
  "schema": "mosaic-modules-v1",
  "include": [
    {
      "name": "counter",
      "artifact_suffix": "native"
    },
    {
      "name": "clock_gate",
      "artifact_suffix": "native"
    }
  ]
}
```

For each name, the validator requires:

```text
config/modules/<name>.mk
config/modules/<name>-flows.mk
```

Names accept lowercase letters, digits, and underscores, must begin with a
letter, and cannot contain path separators. Duplicate names, malformed JSON,
unknown selections, and missing configuration fail before a tool starts.

## Configure one module

The design profile exports the same variables as a single-module
`config/design.mk`. `REPORT_DIR` and `WORK_DIR` default to isolated paths and do
not need to be repeated.

```make
export DESIGN_TOP := counter
export TB_TOP := $(DESIGN_TOP)_tb
export FORMAL_TOP := $(DESIGN_TOP)_formal
export DUT_INSTANCE := $(TB_TOP)/dut

export RTL_FILELIST := $(call mosaic_resolve_filelist,rtl.f)
export TB_FILELIST := $(call mosaic_resolve_filelist,tb.f)
export FORMAL_CONFIG := $(call mosaic_resolve_flow_config,symbiyosys,formal.sby)
export CONSTRAINT_DIR := $(MODULE_ROOT)/flows/synthesis
```

The resolver functions implement these searches:

```text
filelists/<DESIGN_TOP>.<filename>
filelists/<filename>

flows/<flow>/<DESIGN_TOP>.<filename>
flows/<flow>/<filename>
```

The first existing named input wins. The fallback path is returned when neither
path exists so the consuming adapter reports the missing required input.

The matching `<name>-flows.mk` file declares the complete `FLOW_<id>` policy and
dependency overrides for that module.

## Select and run modules

Validate and query the registry with:

```sh
make module-manifest-check
make module-list
make module-matrix
```

Run one module with any normal target:

```sh
make MODULE=counter flow-config-check
make MODULE=counter clean open-source
```

A flow target without `MODULE` fails in a multi-module project. Administrative
targets do not require a selection.

Run one target for every module with:

```sh
make all-modules
make all-modules TARGET=open-formal MODULE_JOBS=4
```

`TARGET` defaults to `open-source`. `MODULE_JOBS=0` allows GNU `xargs` to use all
available processors. A positive value bounds concurrency. The aggregate waits
for every invocation and returns nonzero if any module fails. Results from
modules that completed successfully remain available.

Each selected module defaults to:

```text
reports/<module>/<flow-id>/
work/<module>/<flow-id>/
```

`make MODULE=<name> clean` removes only that module's generated state. Running
`make clean` without a selection removes the complete project work and report
trees.

## Configure formatting

Profiles can set formatting policy without a wrapper command:

```make
export VERIBLE_FORMAT_ARGS := --indentation_spaces=4
export VERIBLE_FORMAT_PATHS := rtl/counter.sv verif/counter
```

Both variables are whitespace-separated. Paths are relative to `MODULE_ROOT`
and may name files or directories. Narrow `VERIBLE_FORMAT_PATHS` in flat
multi-module repositories so one module job does not recheck unrelated sources.

## GitHub Actions matrix

Generate the matrix from the validated methodology API:

```yaml
jobs:
  module-matrix:
    runs-on: ubuntu-24.04
    outputs:
      matrix: ${{ steps.modules.outputs.matrix }}
      flow_revision: ${{ steps.flow.outputs.revision }}
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - name: Read pinned mosaic-flow revision
        id: flow
        run: |
          revision="$(git ls-files --stage mosaic-flow | awk '$1 == "160000" {print $2}')"
          test "${#revision}" -eq 40
          echo "revision=${revision}" >> "${GITHUB_OUTPUT}"
      - uses: actions/checkout@v4
        with:
          repository: ECASLab/mosaic-flow
          ref: ${{ steps.flow.outputs.revision }}
          path: mosaic-flow
          persist-credentials: false
      - name: Generate matrix
        id: modules
        run: echo "matrix=$(make module-matrix)" >> "${GITHUB_OUTPUT}"

  rtl-checks:
    name: ${{ matrix.name }} / native
    needs: module-matrix
    strategy:
      fail-fast: false
      matrix: ${{ fromJSON(needs.module-matrix.outputs.matrix) }}
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - uses: actions/checkout@v4
        with:
          repository: ECASLab/mosaic-flow
          ref: ${{ needs.module-matrix.outputs.flow_revision }}
          path: mosaic-flow
          persist-credentials: false
      - name: Verify pinned mosaic-flow revision
        run: |
          actual="$(git -C mosaic-flow rev-parse HEAD)"
          test "${actual}" = "${{ needs.module-matrix.outputs.flow_revision }}"
      - uses: actions/cache@v4
        with:
          path: ~/.cache/mosaic
          key: mosaic-${{ runner.os }}-${{ matrix.name }}-${{ needs.module-matrix.outputs.flow_revision }}
      - run: make MODULE="${{ matrix.name }}" clean open-source
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: ${{ matrix.name }}-${{ matrix.artifact_suffix }}-reports
          path: reports/${{ matrix.name }}/
          if-no-files-found: error
```

Container jobs use the same matrix and pass `MODULE=${{ matrix.name }}` to the
container command. Give every job a module-qualified cache scope, image tag,
artifact name, report path, and diagnostic log. In both native and container
jobs, read the expected methodology revision from the parent gitlink and verify
the checked-out or embedded revision before running the flow.

## Migrate an existing repository

For a repository with consumer-owned orchestration such as `mosaic-common`:

1. Move the module list to `config/modules.json` and add the
   `mosaic-modules-v1` schema field.
2. Replace the custom root imports and `all-modules` recipe with
   `include $(FLOW_ROOT)/mk/project.mk`.
3. Keep module profiles under `config/modules/` and remove duplicated profile
   existence checks.
4. Replace local resolver functions with `mosaic_resolve_filelist` and
   `mosaic_resolve_flow_config`.
5. Remove explicit `REPORT_DIR` and `WORK_DIR` assignments when the standard
   isolated paths are sufficient.
6. Replace formatter wrapper scripts with `VERIBLE_FORMAT_ARGS` and
   `VERIBLE_FORMAT_PATHS` where possible.
7. Generate the CI matrix through `make module-matrix` and retain exact gitlink
   verification in every job.

Run `make module-manifest-check` before removing the old orchestration, then
compare one native and one containerized result per module.
