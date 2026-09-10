# Portable SDC and UPF intent validation

The optional `static_intent` flow catches structural mistakes in module-owned
SDC and UPF before licensed tools or technology data are available. It captures
a documented Tcl subset without executing the input files, then compares the
captured commands with a module-owned JSON expectation file.

This gate is an early intent check. It is **not static timing analysis, OpenSTA
signoff, PrimeTime signoff, IEEE 1801 conformance, or VC LP signoff**. It has no
timing graph, cell library, voltage model, power-aware netlist, or technology
rules. Commercial and PDK-backed flows remain authoritative for signoff.

## Enable the flow

Add the policy to the module's `config/flows.mk`:

```make
FLOW_static_intent := enabled
```

Select the module-owned expectation file in `config/design.mk` when its path is
not the default `config/static-intent.json`:

```make
export STATIC_INTENT_CONFIG := $(MODULE_ROOT)/config/static-intent.json
```

Run the check alone or as part of the portable gate:

```sh
make open-static-intent
make open-source
```

The adapter writes:

```text
reports/static_intent/sdc-findings.json
reports/static_intent/upf-findings.json
reports/static_intent/summary.json
reports/static_intent/status.txt
```

All three JSON reports and the status are indexed by release evidence when the
flow is enabled. The expectation file and every referenced SDC and UPF file are
hashed as release inputs.

## Expectation file

The complete schema is
[`schemas/static-intent-v1.schema.json`](../schemas/static-intent-v1.schema.json).
A module may select SDC, UPF, or both.

```json
{
  "schema": "mosaic-static-intent-v1",
  "sdc": {
    "profiles": [
      {
        "name": "synthesis",
        "path": "flows/synthesis/timing.sdc",
        "kind": "sequential",
        "expected_ports": {
          "clock": ["i_clk"],
          "input_delay": ["i_data", "i_enable"],
          "output_delay": ["o_data"]
        },
        "clocks": [
          {"name": "i_clk", "period": 10.0, "port": "i_clk"}
        ],
        "intentional_exceptions": [
          {
            "command": "set_false_path",
            "from_ports": ["i_rstb"],
            "to_ports": []
          }
        ]
      },
      {
        "name": "physical",
        "path": "flows/openroad/timing.sdc",
        "kind": "sequential"
      }
    ],
    "consistency": [
      {
        "profiles": ["synthesis", "physical"],
        "commands": [
          "create_clock",
          "set_clock_uncertainty",
          "set_input_delay",
          "set_output_delay"
        ]
      }
    ]
  },
  "upf": {
    "path": "flows/vc_lp/power.upf",
    "top": "example",
    "mode": "always_on",
    "required": {
      "power_domains": ["PD_EXAMPLE"],
      "supply_ports": ["VDD", "VSS"],
      "supply_nets": ["VDD", "VSS"],
      "supply_connections": ["VDD", "VSS"],
      "domain_supplies": ["PD_EXAMPLE"]
    },
    "forbidden_strategies": []
  }
}
```

`kind` applies minimum and forbidden-command policy:

| Kind | Required intent | Default forbidden intent |
| --- | --- | --- |
| `sequential` | Clock, uncertainty, input delay, output delay | None beyond undeclared broad exceptions |
| `combinational` | Maximum input-to-output delay | Clocks, generated clocks, false paths, clock groups |
| `clock_gating` | Source clock, generated clock, uncertainty, input delay | False paths, clock groups, output delay on the clock output |
| `reset_synchronizer` | Destination clock, uncertainty, synchronized output delay | Clock groups |

`expected_ports` proves that each named interface port is selected by the
appropriate command. Direct `get_ports`, `all_inputs`, `all_outputs`, and
`remove_from_collection` selectors are understood. Every `set_false_path` must
use concrete ports and match an `intentional_exceptions` entry. Broad or
undeclared exceptions fail.

Consistency rules compare normalized command captures, so harmless whitespace
and numeric formatting differences do not affect port coverage. Command
differences between selected synthesis, asynchronous, and physical profiles are
reported as `profile_mismatch` findings.

## UPF policy

`mode: always_on` rejects isolation, level-shifting, retention, and power-switch
strategies. `mode: boundary` allows strategies selected by `required` and still
rejects every strategy listed in `forbidden_strategies`.

The `required` section can name:

- `power_domains`
- `supply_ports`
- `supply_nets`
- `supply_connections`
- `domain_supplies`
- `port_states` as `<supply>.<state>`
- `power_state_tables`
- `power_states` as `<table-or-object>.<state>`
- `port_attribute_ports`
- `isolation`
- `level_shifting`
- `retention`

The validator checks references between domains, supplies, connections, port
states, power-state tables, and strategies. It also checks minimum structural
options for isolation, level shifting, and retention. It does not prove that a
strategy maps to a valid library cell or that a power sequence is electrically
safe.

## Supported Tcl subset

The parser does not execute Tcl. Comments, line continuations, braces, quoted
literals, command substitutions, and the following collection expressions are
captured:

- `get_ports`, `get_clocks`, `get_pins`, `get_cells`
- `all_inputs`, `all_outputs`
- `remove_from_collection`

Supported SDC commands are:

- `create_clock`, `create_generated_clock`
- `set_clock_uncertainty`
- `set_input_delay`, `set_output_delay`, `set_max_delay`
- `set_false_path`, `set_clock_groups`
- `set_input_transition`, `set_load`, `set_case_analysis`

Supported UPF commands are:

- `set_design_top`, `create_power_domain`
- `create_supply_port`, `create_supply_net`, `connect_supply_net`
- `set_domain_supply_net`, `add_port_state`
- `create_pst`, `add_pst_state`, `add_power_state`
- `set_port_attributes`
- `set_isolation`, `set_isolation_control`
- `set_level_shifter`
- `set_retention`, `set_retention_control`
- `create_power_switch`

An unsupported command, query, option, variable substitution, or Tcl control
construct is an explicit error. Extend and qualify the shared command model when
a portable module genuinely needs another construct. Do not add module-specific
parser code.

## Review guidance

Use the JSON finding code as the stable automation interface and the message,
source, and line fields for diagnosis. Resolve missing or conflicting intent in
the module-owned SDC, UPF, or expectation file. Waiving this gate by weakening
the parser would affect every module and therefore requires methodology-level
review.
