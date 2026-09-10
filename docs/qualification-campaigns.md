# Negative-test and four-state qualification

The optional qualification campaigns prove that a module's verification
environment can detect known design faults and illegal four-state control
values. `mosaic-flow` owns campaign validation, orchestration, classification,
and evidence. The consuming module owns the mutations, invalid configurations,
stimulus, expected diagnostics, and decision to enable either gate.

The two campaigns are independent canonical flows:

| Campaign | Flow ID | Target | Default |
| --- | --- | --- | --- |
| Negative tests | `negative_qualification` | `make open-negative` | Disabled |
| Four-state controls | `four_state_qualification` | `make open-four-state` | Disabled |

`make open-source` invokes both targets. A disabled campaign records an explicit
`SKIP`. Once enabled, its result must be `PASS` at the open-source quality gate
and in release evidence.

## Module configuration

Store the module-owned manifest at
`config/qualification-campaigns.json`, or override its path:

```make
export QUALIFICATION_CAMPAIGN_MANIFEST := $(CURDIR)/config/qualification-campaigns.json
```

Enable the policies independently in `config/flows.mk`:

```make
FLOW_negative_qualification := enabled
FLOW_four_state_qualification := enabled

FLOW_DEPENDENCIES_negative_qualification :=
FLOW_DEPENDENCIES_four_state_qualification :=
```

The schema is
[`schemas/qualification-campaigns-v1.schema.json`](../schemas/qualification-campaigns-v1.schema.json).
The runtime also applies semantic checks that JSON Schema cannot express, such
as control references and expected-failure rules.

## Manifest model

The root may declare either or both campaigns. A selected campaign must exist.
Each case has a stable `id`, a filesystem-safe `evidence` name, a semantic
`role`, a descriptive `kind`, and one or two ordered `phases` named `compile`
or `run`.

Each campaign may also list module-relative `inputs`. These paths identify its
testbenches, mutations, candidate netlists, and tool configuration. The runner
rejects missing or external paths, and the release generator hashes the inputs
for each enabled campaign.

```json
{
  "schema": "mosaic-qualification-campaigns-v1",
  "campaigns": {
    "negative": {
      "inputs": [
        "verif/mutations/counter_mutant.sv",
        "verif/formal/counter_bad_netlist.eqy"
      ],
      "cases": [
        {
          "id": "nominal_control",
          "evidence": "nominal_control",
          "role": "positive_control",
          "kind": "positive_control",
          "phases": [
            {
              "name": "run",
              "command": ["{case_work_dir}/nominal_sim"],
              "expected": "success",
              "diagnostic": "NOMINAL_TEST_PASS"
            }
          ]
        },
        {
          "id": "incorrect_reset_mutation",
          "evidence": "incorrect_reset_mutation",
          "role": "negative",
          "kind": "simulation_mutation",
          "positive_control": "nominal_control",
          "phases": [
            {
              "name": "run",
              "command": ["{case_work_dir}/mutant_sim"],
              "expected": "failure",
              "diagnostic": "RESET_ASSERTION_FAILED",
              "failure_class": "assertion"
            }
          ]
        }
      ]
    }
  }
}
```

A phase defines exactly one `command` string array or one executable `fixture`.
Commands run directly without an implicit shell. Optional fields are
`environment`, `timeout_seconds`, and `diagnostic`. A phase expecting failure
must also declare a diagnostic regular expression and one of these classes:

- `assertion`
- `elaboration`
- `equivalence`
- `mutation`
- `unknown_control`

Available placeholders are `{module_root}`, `{flow_root}`, `{report_dir}`,
`{work_dir}`, `{case_report_dir}`, `{case_work_dir}`, `{python}`, `{verilator}`,
`{eqy}`, `{iverilog}`, and `{vvp}`. Module source paths remain relative to
`MODULE_ROOT`.

## Negative-test contract

Every negative case references a successful `positive_control`. This prevents
an always-failing checker, broken simulator, or invalid nominal configuration
from qualifying a detected fault. The campaign supports:

- Simulation mutations detected by a test or assertion
- Deliberate assertion failures
- Invalid-parameter elaboration failures
- Deliberately inequivalent candidate netlists

The expected nonzero exit alone is insufficient. The declared diagnostic must
also appear. If a command succeeds, the case is classified as `escaped_fault`.
If it fails without the expected design-check diagnostic, the result is
`unexpected_failure` or `infrastructure_failure`, never a false qualification.

Additional infrastructure signatures may be declared at campaign level:

```json
"infrastructure_diagnostics": ["LICENSE_SERVER_UNAVAILABLE"]
```

Built-in signatures cover missing executables, missing files, license checkout
failures, internal tool failures, and the fixture marker
`INFRASTRUCTURE_FAILURE`.

## Keeping mutations separate

Do not edit production RTL in place and do not copy the shared campaign runner
into a module. Keep module-owned mutation material under a verification path,
for example:

```text
verif/
|-- mutations/
|   |-- counter_mutant.sv
|   `-- bad_candidate_netlist.v
|-- formal/fault_injection/
|   `-- counter_bad_netlist.eqy
`-- tb/fault_injection/
    `-- counter_fault_tb.sv
```

Prefer a compile-time mutation macro, a bind-time fault shim, or a small
candidate netlist over a second full RTL implementation. Compile each mutation
only in its declared case. The positive control must compile and run the
unmodified design with the same checker whenever the tool and test permit it.

## Four-state contract

The four-state campaign is pinned to `"simulator": "iverilog"`. It is separate
from the normal two-state Verilator gate. Every `unknown_detection` case:

- Declares the control ports and injected `X`, `Z`, or both values in
  `injections`
- References one `disabled_monitor_control`
- Expects a nonzero result and a module-specific monitor diagnostic

The disabled-monitor control must drive the same illegal stimulus while the
unknown-value monitor is disabled. It expects success and requires a marker
such as `UNKNOWN_CONTROL_STIMULUS_REACHED`. This proves the stimulus reached the
DUT and catches monitors that fail unconditionally.

Both cases declare identical `injections`, provide `compile` and `run` phases,
and invoke `{iverilog}` and `{vvp}` directly. The runner enforces these details
so simulator metadata cannot claim Icarus while executing a two-state backend.

The `injections` field is auditable metadata. The module-owned four-state
testbench remains responsible for driving the declared values. Reviewers should
compare the testbench with this declaration.

## Results and classification

Each gate writes:

```text
reports/<flow-id>/
|-- status.txt
|-- summary.json
`-- [<simulator>/]<evidence-name>/
    |-- status.txt
    |-- summary.json
    |-- compile-command.json
    |-- compile-result.json
    |-- compile.log
    |-- run-command.json
    |-- run-result.json
    `-- run.log
```

Only declared phases are present. Corresponding disposable outputs use
`work/<flow-id>/[<simulator>/]<evidence-name>/`. Four-state cases use the
explicit `iverilog/` namespace. Multi-module and parameter-profile roots
continue to isolate these paths before the flow ID.

Case summaries distinguish expected assertion, elaboration, equivalence,
mutation, and unknown-control failures from escaped faults, missing diagnostics,
unexpected failures, infrastructure failures, and failed controls. Any failed
or blocked case fails the aggregate campaign.

The release manifest hashes the module-owned campaign manifest when either
flow is enabled. It records each flow's required or approved-skip policy,
captures Icarus and VVP versions when four-state qualification is enabled, and
indexes each generated campaign `summary.json` as additional evidence.

## Migration from module scripts

To replace an existing `run_fault_injection.sh` or `run_four_state.sh`:

1. Inventory each compile and run command, expected exit, and diagnostic.
2. Add a positive or disabled-monitor control before its dependent cases.
3. Move orchestration into the manifest while retaining design-specific RTL,
   testbenches, EQY files, and expected messages in the module.
4. Run each target independently and inspect escaped-fault and broken-monitor
   behavior deliberately.
5. Enable the flow only after its positive and negative controls qualify.

Automatic mutation generation, replacement of normal regression or formal
proof, and mandatory four-state testing for modules without relevant controls
are outside this feature.
