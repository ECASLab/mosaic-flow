# Containerized OpenROAD Flow Scripts

## Purpose and boundary

The `openroad` adapter runs module-owned RTL and constraints through OpenROAD
Flow Scripts (ORFS). It supports a qualified local checkout and a pinned OCI
container while applying the same declarative physical evidence policy.

The public Nangate45 fixture demonstrates reproducible exploratory synthesis,
placement, clock-tree synthesis, routing, and output generation. A `PASS` result
is not foundry signoff. It does not replace proprietary PDK validation,
extraction, signal-integrity analysis, physical verification, or signoff timing
and power tools.

## Module-owned inputs

Declare the physical configuration in the module's `config/design.mk`:

```make
export OPENROAD_CONFIG := $(CURDIR)/config/openroad.mk
export OPENROAD_CONSTRAINT_FILE := $(CURDIR)/constraints/timing.sdc
export OPENROAD_EVIDENCE_POLICY := $(CURDIR)/config/openroad-evidence.json
export OPENROAD_PLATFORM := nangate45
export OPENROAD_FLOW_VARIANT := release
export OPENROAD_DESIGN_NAME := $(DESIGN_TOP)
```

Both `OPENROAD_CONFIG` and `OPENROAD_CONSTRAINT_FILE` must resolve below
`MODULE_ROOT`. The adapter mounts the module read-only in container mode and
passes the selected SDC to ORFS explicitly, so the file hashed in the evidence
is the file used by implementation.

An ORFS configuration remains module-owned. For example:

```make
export DESIGN_NAME = my_module
export PLATFORM = $(OPENROAD_PLATFORM)
export VERILOG_FILES = $(REPO_ROOT)/rtl/my_module.sv
export SDC_FILE = $(REPO_ROOT)/constraints/timing.sdc
export DIE_AREA = 0 0 60 60
export CORE_AREA = 5 5 55 55
```

## Physical evidence policy

The policy uses the versioned
[`mosaic-openroad-evidence-policy-v1`](../schemas/openroad-evidence-policy-v1.schema.json)
contract. Artifact paths are relative to the selected ORFS result, report, log,
or object directory. Every required artifact must exist and be nonempty.

```json
{
  "schema": "mosaic-openroad-evidence-policy-v1",
  "artifacts": [
    {"name": "final_def", "directory": "results", "path": "6_final.def"},
    {"name": "final_gds", "directory": "results", "path": "6_final.gds"},
    {"name": "final_odb", "directory": "results", "path": "6_final.odb"},
    {"name": "final_sdc", "directory": "results", "path": "6_final.sdc"},
    {"name": "final_netlist", "directory": "results", "path": "6_final.v"}
  ],
  "metrics": [
    {
      "name": "setup_violations",
      "directory": "reports",
      "path": "6_finish.rpt",
      "pattern": "setup violation count[ \\t]+(?P<value>[0-9]+)",
      "maximum": 0
    },
    {
      "name": "routing_violations",
      "directory": "logs",
      "path": "5_2_route.log",
      "pattern": "Number of violations = (?P<value>[0-9]+)",
      "match": "last",
      "maximum": 0
    }
  ]
}
```

Each metric regular expression must contain exactly one named integer group
called `value`. `match` defaults to `only` and may select `first` or `last` when
a tool logs an iterative metric multiple times. A metric may declare `minimum`,
`maximum`, or both. Modules normally declare setup, hold, slew, fanout,
capacitance, and routing violation counts, but their report paths and thresholds
remain policy rather than shared script constants.

## Container execution

Container mode defaults to the immutable ORFS image digest in
`config/tool-versions.env`:

```sh
make OPENROAD_EXECUTION_MODE=container open-physical
```

`OPENROAD_CONTAINER_RUNTIME` defaults to `docker` and may select a compatible
runtime. `OPENROAD_ORFS_IMAGE` may override the image only with an
`image@sha256:<digest>` reference. A missing runtime or floating image fails
before implementation.

The container runs with the invoking UID and GID. `MODULE_ROOT` is mounted
read-only at `/workspace`, while the profile-qualified `WORK_DIR/openroad` is
mounted read-write at `/orfs-work`. ORFS places results, reports, logs, and
objects below that root using platform, design, and variant components. Module
selection and parameter-profile selection already qualify `WORK_DIR`, so
concurrent jobs do not share physical databases.

CI can prepare the pinned image and retain its layers with:

```sh
ci/cache_openroad_image.sh
```

The cache archive name is derived from the immutable image digest. Changing the
methodology pin therefore creates a new cache entry instead of silently reusing
a floating ORFS version.

## Local execution

Local mode preserves the checkout-based workflow:

```sh
make \
  OPENROAD_EXECUTION_MODE=local \
  OPENROAD_FLOW_ROOT="$HOME/tools/OpenROAD-flow-scripts" \
  open-physical
```

The checkout must contain `flow/Makefile`. When it is a Git repository, its
resolved revision is recorded in evidence. Local ORFS dependencies and platform
collateral remain the developer or site administrator's responsibility.

## Outputs and release evidence

The adapter writes:

```text
reports/openroad/
|-- evidence.json
|-- run.log
`-- status.txt

work/openroad/
|-- logs/<platform>/<design>/<variant>/
|-- objects/<platform>/<design>/<variant>/
|-- reports/<platform>/<design>/<variant>/
`-- results/<platform>/<design>/<variant>/
```

`evidence.json` records execution mode, platform, design, variant, local ORFS
revision or container identity, runtime version, configuration and SDC hashes,
artifact sizes and hashes, parsed metrics, thresholds, and failures. Container
evidence retains both the configured immutable reference and the resolved local
image ID.

When `openroad` is required, `make release-manifest` automatically hashes the
policy as an input and indexes `reports/openroad/evidence.json`. Missing physical
evidence then fails release-manifest generation.
