# Parameter-profile qualification

## Purpose

A parameter profile names one representative RTL elaboration and the evidence
required to qualify it. Profiles let a module cover boundary widths, optional
features, reset modes, polarity choices, and implementation branches without
mixing their generated artifacts.

Profiles are module-owned. `mosaic-flow` validates and dispatches the declared
set, translates parameters for each backend, isolates results, and reports an
aggregate status. It does not discover legal combinations automatically.

Repositories without a profile manifest keep their existing unqualified
behavior. `make profile-list` reports `default` in that case.

## Declare profiles

The default manifest path for a single-module repository is:

```text
config/parameter-profiles.json
```

For a module named `counter` in a multi-module repository, it is:

```text
config/parameter-profiles/counter.json
```

Override `PARAMETER_PROFILE_MANIFEST` in module configuration only when another
location is necessary.

The `mosaic-parameter-profiles-v1` schema contains an ordered, nonempty
`include` array:

```json
{
  "schema": "mosaic-parameter-profiles-v1",
  "include": [
    {
      "name": "width_min",
      "parameters": {
        "SATURATE": false,
        "WIDTH": 1
      },
      "flows": [
        "slang_elaboration",
        "verilator_lint",
        "yosys_synthesis",
        "symbiyosys_formal",
        "eqy_equivalence",
        "verilator_sim"
      ]
    },
    {
      "name": "saturating",
      "parameters": {
        "SATURATE": true,
        "WIDTH": 8
      },
      "flows": [
        "slang_elaboration",
        "verilator_lint",
        "yosys_synthesis",
        "symbiyosys_formal",
        "eqy_equivalence",
        "verilator_sim"
      ],
      "tops": {
        "design": "counter",
        "formal": "counter_formal",
        "pyuvm": "counter",
        "testbench": "counter_tb"
      }
    }
  ]
}
```

Each profile has these fields:

| Field | Required | Meaning |
| --- | --- | --- |
| `name` | Yes | Lowercase identifier unique within the manifest |
| `parameters` | Yes | Map of HDL parameter identifiers to scalar values |
| `flows` | Yes | Nonempty list of evidence required for this elaboration |
| `tops` | No | Per-profile overrides for `design`, `testbench`, `formal`, or `pyuvm` |

Parameter values may be JSON integers, booleans, or whitespace-free HDL
constant expressions. Booleans become `1` and `0` at tool boundaries.
Whitespace, double quotes, semicolons, and dollar signs are rejected. Use an
ordinary HDL identifier for every parameter and top name.

The supported profile flows are:

```text
verible_lint              verible_format
slang_elaboration         verilator_lint
yosys_synthesis           symbiyosys_formal
eqy_equivalence           verilator_sim
pyuvm_open_source         negative_qualification
four_state_qualification  vcs_sim
pyuvm_commercial          synopsys_synthesis
synopsys_primetime        synopsys_primepower
```

`eqy_equivalence` requires `yosys_synthesis` in the same profile.
`synopsys_primetime` requires `synopsys_synthesis`.
`synopsys_primepower` requires both `vcs_sim` and `synopsys_synthesis`.
Unsupported flows and incomplete dependency sets fail manifest validation.
The profile list may narrow the module's `FLOW_<id>` policy, but it cannot
enable a flow disabled there. Declaring a disabled module flow as required by a
selected profile is a configuration error.

## Select and run profiles

Validate and inspect the declaration before launching tools:

```sh
make profile-manifest-check
make profile-list
make profile-matrix
```

Run one exact elaboration with any normal target:

```sh
make PROFILE=width_min flow-config-check
make PROFILE=width_min clean open-source
```

When a manifest exists, a flow target without `PROFILE` fails before a tool
starts. Flows omitted from the selected profile are resolved as disabled and
record `SKIP` when an aggregate target invokes them.

Run one target for every declared profile:

```sh
make clean all-profiles
make all-profiles PROFILE_TARGET=open-formal PROFILE_JOBS=4
```

`PROFILE_TARGET` defaults to `open-source`. `PROFILE_JOBS=0` lets GNU `xargs`
use all available processors. A positive value bounds concurrency. Setup is
performed once before parallel portable jobs begin.

The aggregate keeps completed results, writes
`reports/parameter-profile-summary.json`, and returns nonzero when any child
invocation fails. The summary preserves `PASS`, `FAIL`, `SKIP`, `BLOCKED`, and
missing evidence so one profile cannot hide another profile's outcome.

## Evidence isolation

A selected profile adds its name below the module's configured roots:

```text
reports/<profile>/parameter-profile.json
reports/<profile>/<flow-id>/status.txt
work/<profile>/<flow-id>/...
```

In a multi-module repository, the normal module namespace comes first:

```text
reports/<module>/<profile>/<flow-id>/
work/<module>/<profile>/<flow-id>/
```

`parameter-profile.json` records the exact parameter map, applicable flows, and
resolved top names. Generated formal and equivalence configurations are stored
with the profile reports. The EQY gate input is always resolved below the same
profile's `work/<profile>/yosys_synthesis/` tree. PrimeTime and PrimePower also
inherit the profile-qualified Design Compiler artifact paths.

The module-owned EQY configuration must contain exactly one `.v` or `.sv` input
in its `[gate]` section. This input is the placeholder replaced by the selected
profile's netlist. An ambiguous gate input set fails before EQY starts.

`make PROFILE=<name> clean` removes only that profile. Run `make clean` without
a profile to remove every generated profile result.

## Backend mapping

The canonical parameter map reaches supported tools as follows:

| Flow | Applied to | Backend mechanism |
| --- | --- | --- |
| Slang elaboration | `DESIGN_TOP` | `-G NAME=VALUE` |
| Verilator lint | `DESIGN_TOP` | `-GNAME=VALUE` |
| Yosys synthesis | `DESIGN_TOP` | `chparam -set` before `hierarchy` |
| SymbiYosys | `FORMAL_TOP` | Rendered profile `.sby` with `chparam` before `prep` |
| EQY gold | `DESIGN_TOP` | Rendered profile `.eqy` with `chparam` before `prep` |
| EQY gate | Matching netlist | Exact profile-local Yosys netlist path |
| Verilator simulation | `TB_TOP` | `-GNAME=VALUE` |
| VCS simulation | `TB_TOP` | `-pvalue+TOP.NAME=VALUE` |
| PyUVM | `PYUVM_TOP` | cocotb runner `parameters` map |
| Design Compiler | `DESIGN_TOP` | `elaborate -parameters` |
| PrimeTime and PrimePower | DC output | Matching profile-local DDC and SDC |

Simulation testbench tops must declare the profile parameters and propagate
them into the DUT. Formal harness tops must do the same. PyUVM normally uses the
DUT itself as `PYUVM_TOP`, so its overrides apply directly.

Verible performs source syntax, formatting, and style checks without elaborating
parameter values. Its result is still profile-qualified when selected, but it
does not independently prove a parameter branch.

## Choose required evidence

An elaboration-only profile is appropriate when it checks parser legality for a
representative value and cannot activate a structurally distinct generate path.
Such a profile normally selects Verible, Slang, and Verilator lint.

Require simulation or formal when a value changes behavior. Require synthesis
when it changes widths, generated hierarchy, arithmetic implementation, memory
shape, or another structural branch. Require EQY whenever a profile's synthesized
netlist is release evidence. Technology timing and power profiles should include
Design Compiler and their matching downstream commercial flows.

Keep the matrix representative. Include legal minimum and maximum boundaries,
the nominal production configuration, and both sides of each important feature
toggle. Document exclusions and equivalent classes in the module verification
plan.

## GitHub Actions integration

For a single module, emit `make profile-matrix` as compact JSON and run each
entry independently:

```yaml
- name: Generate parameter matrix
  id: profiles
  run: echo "matrix=$(make profile-matrix)" >> "${GITHUB_OUTPUT}"

# In a matrix job:
- run: make PROFILE="${{ matrix.profile }}" clean open-source
```

For a multi-module repository, `make module-profile-matrix` combines every
registered module with its own profiles. Modules without a manifest contribute
one `default` entry.

```yaml
- name: Generate module and profile matrix
  id: qualifications
  run: echo "matrix=$(make module-profile-matrix)" >> "${GITHUB_OUTPUT}"

# In a matrix job:
- run: >-
    make MODULE="${{ matrix.module }}"
    PROFILE="${{ matrix.profile }}" clean open-source
```

Use `${{ matrix.job_name }}` in job or artifact names. It is generated as
`<module>--<profile>` and is validated for collisions. Use the same matrix for
native and pinned-container jobs so both environments qualify identical
elaborations.
