export CDC_TOOL ?= vc
export FORCE_FLOW ?= 0

include $(FLOW_ROOT)/config/flows.mk
MODULE_DESIGN_CONFIG ?= $(MODULE_ROOT)/config/design.mk
MODULE_FLOW_CONFIG ?= $(MODULE_ROOT)/config/flows.mk
-include $(MODULE_FLOW_CONFIG)

PARAMETER_PROFILE_TOOL ?= $(FLOW_ROOT)/ci/parameter_profiles.py
PARAMETER_PROFILE_MANIFEST ?= $(if $(MODULE),$(MODULE_ROOT)/config/parameter-profiles/$(MODULE).json,$(MODULE_ROOT)/config/parameter-profiles.json)
export PARAMETER_PROFILE_TOOL
MOSAIC_PARAMETER_PROFILES := $(if $(wildcard $(PARAMETER_PROFILE_MANIFEST)),enabled,disabled)
PROFILE_JOBS ?= $(if $(JOBS),$(JOBS),0)
PROFILE_TARGET ?= open-source
export PROFILE_PARAMETERS_JSON := {}
export PROFILE_APPLICABLE_FLOWS :=
export MOSAIC_PROFILE_ACTIVE := disabled

ifeq ($(MOSAIC_PARAMETER_PROFILES),enabled)
ifneq ($(strip $(PROFILE)),)
MOSAIC_PROFILE_VALIDATION_ERROR := $(shell python3 "$(PARAMETER_PROFILE_TOOL)" validate --quiet --manifest "$(PARAMETER_PROFILE_MANIFEST)" 2>&1 && python3 "$(PARAMETER_PROFILE_TOOL)" get --manifest "$(PARAMETER_PROFILE_MANIFEST)" --selected "$(PROFILE)" --field flows >/dev/null 2>&1 || echo "Invalid or unknown PROFILE '$(PROFILE)'; run make profile-manifest-check")
ifneq ($(strip $(MOSAIC_PROFILE_VALIDATION_ERROR)),)
$(error $(MOSAIC_PROFILE_VALIDATION_ERROR))
endif

export PROFILE_PARAMETERS_JSON := $(shell python3 "$(PARAMETER_PROFILE_TOOL)" get --manifest "$(PARAMETER_PROFILE_MANIFEST)" --selected "$(PROFILE)" --field parameters)
export PROFILE_APPLICABLE_FLOWS := $(shell python3 "$(PARAMETER_PROFILE_TOOL)" get --manifest "$(PARAMETER_PROFILE_MANIFEST)" --selected "$(PROFILE)" --field flows)
MOSAIC_PROFILE_DESIGN_TOP := $(shell python3 "$(PARAMETER_PROFILE_TOOL)" get --manifest "$(PARAMETER_PROFILE_MANIFEST)" --selected "$(PROFILE)" --field design)
MOSAIC_PROFILE_TESTBENCH_TOP := $(shell python3 "$(PARAMETER_PROFILE_TOOL)" get --manifest "$(PARAMETER_PROFILE_MANIFEST)" --selected "$(PROFILE)" --field testbench)
MOSAIC_PROFILE_FORMAL_TOP := $(shell python3 "$(PARAMETER_PROFILE_TOOL)" get --manifest "$(PARAMETER_PROFILE_MANIFEST)" --selected "$(PROFILE)" --field formal)
MOSAIC_PROFILE_PYUVM_TOP := $(shell python3 "$(PARAMETER_PROFILE_TOOL)" get --manifest "$(PARAMETER_PROFILE_MANIFEST)" --selected "$(PROFILE)" --field pyuvm)

ifneq ($(strip $(MOSAIC_PROFILE_DESIGN_TOP)),)
override DESIGN_TOP := $(MOSAIC_PROFILE_DESIGN_TOP)
endif
ifneq ($(strip $(MOSAIC_PROFILE_TESTBENCH_TOP)),)
override TB_TOP := $(MOSAIC_PROFILE_TESTBENCH_TOP)
endif
ifneq ($(strip $(MOSAIC_PROFILE_FORMAL_TOP)),)
override FORMAL_TOP := $(MOSAIC_PROFILE_FORMAL_TOP)
endif
ifneq ($(strip $(MOSAIC_PROFILE_PYUVM_TOP)),)
override PYUVM_TOP := $(MOSAIC_PROFILE_PYUVM_TOP)
endif
export DESIGN_TOP TB_TOP FORMAL_TOP PYUVM_TOP

PROFILE_REPORT_ROOT := $(REPORT_DIR)
PROFILE_WORK_ROOT := $(WORK_DIR)
override REPORT_DIR := $(PROFILE_REPORT_ROOT)/$(PROFILE)
override WORK_DIR := $(PROFILE_WORK_ROOT)/$(PROFILE)
export REPORT_DIR WORK_DIR
export MOSAIC_PROFILE_ACTIVE := enabled
endif
endif

mosaic_flow_state_is_valid = $(and $(filter 1,$(words $(1))),$(filter $(1),enabled disabled))
MOSAIC_INVALID_FLOW_STATES := $(strip $(foreach flow,$(MOSAIC_FLOW_IDS),$(if $(call mosaic_flow_state_is_valid,$(FLOW_$(flow))),,$(flow)=$(FLOW_$(flow)))))
ifneq ($(MOSAIC_INVALID_FLOW_STATES),)
$(error Flow states must be 'enabled' or 'disabled': $(MOSAIC_INVALID_FLOW_STATES))
endif

MOSAIC_EXPLICIT_DISABLED_FLOWS := $(DISABLED_FLOWS)
MOSAIC_MODULE_DISABLED_FLOWS := $(sort $(filter $(MOSAIC_FLOW_IDS),$(MOSAIC_EXPLICIT_DISABLED_FLOWS)) $(foreach flow,$(MOSAIC_FLOW_IDS),$(if $(filter disabled,$(FLOW_$(flow))),$(flow))))
MOSAIC_PROFILE_POLICY_CONFLICTS := $(filter $(MOSAIC_MODULE_DISABLED_FLOWS),$(PROFILE_APPLICABLE_FLOWS))
ifneq ($(MOSAIC_PROFILE_POLICY_CONFLICTS),)
$(error PROFILE '$(PROFILE)' requires flows disabled by module policy: $(MOSAIC_PROFILE_POLICY_CONFLICTS))
endif
MOSAIC_PROFILE_DISABLED_FLOWS := $(if $(PROFILE_APPLICABLE_FLOWS),$(filter-out $(PROFILE_APPLICABLE_FLOWS),$(MOSAIC_FLOW_IDS)))
override DISABLED_FLOWS := $(sort $(MOSAIC_EXPLICIT_DISABLED_FLOWS) $(MOSAIC_MODULE_DISABLED_FLOWS) $(MOSAIC_PROFILE_DISABLED_FLOWS))
export DISABLED_FLOWS
export MOSAIC_FLOW_IDS
export $(foreach flow,$(MOSAIC_FLOW_IDS),FLOW_$(flow) FLOW_DEPENDENCIES_$(flow))

FLOW_RUNNER := $(FLOW_ROOT)/ci/run_flow.sh

# RELEASE_MANIFEST_TOOL: Methodology-owned generator and validator.
RELEASE_MANIFEST_TOOL ?= $(FLOW_ROOT)/ci/release_manifest.py
# RELEASE_MODULE_NAME: Stable module identity written into release evidence.
RELEASE_MODULE_NAME ?= $(if $(MODULE),$(MODULE),$(DESIGN_TOP))
# MODULE_REVISION: Exact 40-digit module commit. Empty permits local Git fallback.
MODULE_REVISION ?=
# METHODOLOGY_REVISION: Exact 40-digit mosaic-flow commit. Empty permits local Git fallback.
METHODOLOGY_REVISION ?=
# RELEASE_EXECUTION_CONTEXT: Output namespace and execution label, such as native or container.
RELEASE_EXECUTION_CONTEXT ?= native
# RELEASE_ALLOW_DIRTY: Permit a dirty module checkout only for local diagnostics.
RELEASE_ALLOW_DIRTY ?= disabled
# RELEASE_MODULE_DIRTY: Explicit true or false for a packaged module without Git metadata.
RELEASE_MODULE_DIRTY ?=
# RELEASE_METHODOLOGY_DIRTY: Explicit true or false for packaged mosaic-flow source.
RELEASE_METHODOLOGY_DIRTY ?=
# RELEASE_TECHNOLOGY: Human-readable technology or technology-independent context.
RELEASE_TECHNOLOGY ?= technology-independent
# RELEASE_TECHNOLOGY_METADATA_JSON: Structured technology, PDK, library, and corner details.
RELEASE_TECHNOLOGY_METADATA_JSON ?= {}
# RELEASE_METADATA_JSON: Arbitrary module-owned deterministic release metadata.
RELEASE_METADATA_JSON ?= {}
# RELEASE_EXECUTION_METADATA_JSON: Arbitrary volatile runner or container metadata.
RELEASE_EXECUTION_METADATA_JSON ?= {}
# RELEASE_ADDITIONAL_TOOLS_JSON: Additional tool commands and associated canonical flows.
RELEASE_ADDITIONAL_TOOLS_JSON ?= []
# RELEASE_COVERAGE_EVIDENCE_JSON: Additional native or functional coverage records.
RELEASE_COVERAGE_EVIDENCE_JSON ?= []
# RELEASE_SUPPLEMENTAL_GATES: Module-owned gate IDs with reports/<id>/status.txt evidence.
RELEASE_SUPPLEMENTAL_GATES ?=
# RELEASE_ADDITIONAL_INPUTS: Required files or directories added to the hashed input set.
RELEASE_ADDITIONAL_INPUTS ?=
# RELEASE_ADDITIONAL_EVIDENCE: Required generated files indexed by path and SHA-256.
RELEASE_ADDITIONAL_EVIDENCE ?=
# RELEASE_MANIFEST_DIR: Context-specific output directory below the selected report root.
RELEASE_MANIFEST_DIR ?= $(REPORT_DIR)/release_manifest/$(RELEASE_EXECUTION_CONTEXT)

RELEASE_STANDARD_INPUTS := \
	$(MODULE_DESIGN_CONFIG) \
	$(MODULE_FLOW_CONFIG) \
	$(if $(wildcard $(MODULE_MANIFEST)),$(MODULE_MANIFEST)) \
	$(if $(wildcard $(PARAMETER_PROFILE_MANIFEST)),$(PARAMETER_PROFILE_MANIFEST)) \
	$(VERILATOR_WAIVER_FILE) \
	$(VERIBLE_WAIVER_FILE) \
	$(VERIBLE_RULES_FILE) \
	$(FORMAL_CONFIG) \
	$(FORMAL_COVER_CONFIG) \
	$(FORMAL_COVERAGE_CONFIG) \
	$(if $(filter enabled,$(FLOW_coverage_qualification)),$(COVERAGE_QUALIFICATION_POLICY)) \
	$(if $(filter enabled,$(FLOW_negative_qualification) $(FLOW_four_state_qualification)),$(QUALIFICATION_CAMPAIGN_MANIFEST)) \
	$(if $(filter enabled,$(FLOW_static_intent)),$(STATIC_INTENT_CONFIG)) \
	$(EQUIVALENCE_CONFIG) \
	$(OPENROAD_CONFIG) \
	$(if $(filter openroad,$(DISABLED_FLOWS)),,$(if $(filter enabled,$(FLOW_openroad)),$(OPENROAD_EVIDENCE_POLICY))) \
	$(SYNTHESIS_CONSTRAINT_FILE) \
	$(ASYNC_SYNTHESIS_CONSTRAINT_FILE) \
	$(OPENROAD_CONSTRAINT_FILE) \
	$(CDC_CONFIG) \
	$(DFT_CONFIG) \
	$(UPF_CONFIG) \
	$(if $(SYNTHESIS_CONSTRAINT_FILE),,$(CONSTRAINT_DIR)) \
	$(if $(PYUVM_TEST_MODULE),$(PYUVM_TEST_PATH))
RELEASE_FILELISTS := $(sort $(strip \
	$(RTL_FILELIST) \
	$(TB_FILELIST) \
	$(FORMAL_FILELIST) \
	$(PROPERTY_FILELIST) \
	$(ASSERTION_FILELIST) \
	$(COVERAGE_FILELIST) \
	$(PYUVM_FILELIST)))
RELEASE_INPUT_FILES := $(sort $(strip $(RELEASE_STANDARD_INPUTS) $(RELEASE_ADDITIONAL_INPUTS)))
RELEASE_STANDARD_EVIDENCE := $(if $(filter openroad,$(DISABLED_FLOWS)),,$(if $(filter enabled,$(FLOW_openroad)),$(REPORT_DIR)/openroad/evidence.json))

export RELEASE_MANIFEST_TOOL RELEASE_MODULE_NAME MODULE_REVISION METHODOLOGY_REVISION
export RELEASE_EXECUTION_CONTEXT RELEASE_ALLOW_DIRTY RELEASE_TECHNOLOGY
export RELEASE_MODULE_DIRTY RELEASE_METHODOLOGY_DIRTY
export RELEASE_TECHNOLOGY_METADATA_JSON RELEASE_METADATA_JSON
export RELEASE_EXECUTION_METADATA_JSON RELEASE_ADDITIONAL_TOOLS_JSON
export RELEASE_COVERAGE_EVIDENCE_JSON RELEASE_SUPPLEMENTAL_GATES
export RELEASE_ADDITIONAL_INPUTS RELEASE_ADDITIONAL_EVIDENCE RELEASE_MANIFEST_DIR
export RELEASE_FILELISTS RELEASE_INPUT_FILES RELEASE_STANDARD_EVIDENCE

OPEN_SOURCE_TARGETS := open-source open-style-lint open-format-check open-elaborate open-lint open-waiver-draft open-synth open-formal open-equivalence open-sim open-pyuvm open-coverage open-negative open-four-state open-static-intent open-quality-gate
OPEN_FLOW_TARGETS := open-style-lint open-format-check open-elaborate open-lint open-synth open-formal open-equivalence open-sim open-pyuvm open-coverage open-negative open-four-state open-static-intent

FLOW_TARGET_verible_lint := open-style-lint
FLOW_TARGET_verible_format := open-format-check
FLOW_TARGET_slang_elaboration := open-elaborate
FLOW_TARGET_verilator_lint := open-lint
FLOW_TARGET_yosys_synthesis := open-synth
FLOW_TARGET_symbiyosys_formal := open-formal
FLOW_TARGET_eqy_equivalence := open-equivalence
FLOW_TARGET_verilator_sim := open-sim
FLOW_TARGET_pyuvm_open_source := open-pyuvm
FLOW_TARGET_coverage_qualification := open-coverage
FLOW_TARGET_negative_qualification := open-negative
FLOW_TARGET_four_state_qualification := open-four-state
FLOW_TARGET_static_intent := open-static-intent
FLOW_TARGET_openroad := open-physical
FLOW_TARGET_vcs_sim := synopsys-sim
FLOW_TARGET_pyuvm_commercial := commercial-pyuvm
FLOW_TARGET_vc_lint := synopsys-lint
FLOW_TARGET_vc_cdc := $(if $(filter vc,$(CDC_TOOL)),synopsys-cdc)
FLOW_TARGET_sg_cdc := $(if $(filter sg,$(CDC_TOOL)),synopsys-cdc)
FLOW_TARGET_sg_dft := synopsys-dft
FLOW_TARGET_vc_lp := synopsys-lp
FLOW_TARGET_synopsys_synthesis := synopsys-synth
FLOW_TARGET_synopsys_primetime := synopsys-sta
FLOW_TARGET_synopsys_primepower := synopsys-power

MOSAIC_FLOW_TARGETS := $(sort $(foreach flow,$(MOSAIC_FLOW_IDS),$(FLOW_TARGET_$(flow))))

define mosaic_add_flow_dependencies
$(FLOW_TARGET_$(1)): $(foreach dependency,$(FLOW_DEPENDENCIES_$(1)),$(FLOW_TARGET_$(dependency)))
endef
$(foreach flow,$(MOSAIC_FLOW_IDS),$(eval $(call mosaic_add_flow_dependencies,$(flow))))

.PHONY: help mosaic-module-selection-check mosaic-profile-selection-check profile-manifest-check profile-list profile-matrix profile-evidence flow-config-check setup-open-source release-manifest release-manifest-validate $(OPEN_SOURCE_TARGETS) open-physical commercial-pyuvm synopsys-all synopsys-check-env synopsys-sim synopsys-lint synopsys-cdc synopsys-dft synopsys-lp synopsys-static synopsys-synth synopsys-sta synopsys-power synopsys-quality-gate clean

help:
	@sed -n 's/^## //p' "$(FLOW_ROOT)/mk/module.mk" "$(FLOW_ROOT)/mk/project.mk"

mosaic-module-selection-check:
	@if [[ "$(MOSAIC_MULTI_MODULE)" == "enabled" && -z "$(MODULE)" ]]; then \
		echo "This is a multi-module project; select MODULE=<name> or use all-modules" >&2; \
		exit 2; \
	fi

profile-manifest-check:
	@if [[ "$(MOSAIC_PARAMETER_PROFILES)" == "enabled" ]]; then \
		python3 "$(PARAMETER_PROFILE_TOOL)" validate \
			--manifest "$(PARAMETER_PROFILE_MANIFEST)"; \
	else \
		echo "No parameter-profile manifest; the unqualified default configuration is active"; \
	fi

profile-list:
	@if [[ "$(MOSAIC_PARAMETER_PROFILES)" == "enabled" ]]; then \
		python3 "$(PARAMETER_PROFILE_TOOL)" list \
			--manifest "$(PARAMETER_PROFILE_MANIFEST)"; \
	else \
		printf 'default\n'; \
	fi

profile-matrix:
	@if [[ "$(MOSAIC_PARAMETER_PROFILES)" == "enabled" ]]; then \
		python3 "$(PARAMETER_PROFILE_TOOL)" matrix \
			--manifest "$(PARAMETER_PROFILE_MANIFEST)" \
			--module "$(if $(MODULE),$(MODULE),$(DESIGN_TOP))"; \
	else \
		printf '{"include":[{"job_name":"%s--default","module":"%s","parameters":{},"profile":"default"}]}\n' \
			"$(if $(MODULE),$(MODULE),$(DESIGN_TOP))" \
			"$(if $(MODULE),$(MODULE),$(DESIGN_TOP))"; \
	fi

mosaic-profile-selection-check:
	@if [[ "$(MOSAIC_PARAMETER_PROFILES)" == "enabled" && -z "$(PROFILE)" ]]; then \
		echo "This module declares parameter profiles; select PROFILE=<name> or use all-profiles" >&2; \
		exit 2; \
	fi; \
	if [[ "$(MOSAIC_PARAMETER_PROFILES)" == "disabled" && -n "$(PROFILE)" && "$(PROFILE)" != "default" ]]; then \
		echo "PROFILE=$(PROFILE) requires a parameter-profile manifest" >&2; \
		exit 2; \
	fi

profile-evidence: mosaic-profile-selection-check
	@if [[ "$(MOSAIC_PROFILE_ACTIVE)" == "enabled" ]]; then \
		python3 "$(PARAMETER_PROFILE_TOOL)" evidence \
			--manifest "$(PARAMETER_PROFILE_MANIFEST)" --selected "$(PROFILE)" \
			--output "$(REPORT_DIR)/parameter-profile.json" \
			--design-top "$(DESIGN_TOP)" --testbench-top "$(TB_TOP)" \
			--formal-top "$(FORMAL_TOP)" --pyuvm-top "$(PYUVM_TOP)"; \
	fi

## release-manifest Generate and validate context-specific release evidence
release-manifest: flow-config-check
	@python3 "$(RELEASE_MANIFEST_TOOL)" generate \
		--module-root "$(MODULE_ROOT)" \
		--flow-root "$(FLOW_ROOT)" \
		--report-dir "$(REPORT_DIR)" \
		--output-dir "$(RELEASE_MANIFEST_DIR)"

## release-manifest-validate Validate an existing context-specific manifest
release-manifest-validate: mosaic-module-selection-check
	@python3 "$(RELEASE_MANIFEST_TOOL)" validate \
		--manifest "$(RELEASE_MANIFEST_DIR)/manifest.json"

ifeq ($(MOSAIC_PARAMETER_PROFILES),enabled)
.PHONY: all-profiles

## all-profiles Run PROFILE_TARGET for every declared parameter profile
all-profiles: profile-manifest-check
	+@if [[ ! "$(PROFILE_JOBS)" =~ ^[0-9]+$$ ]]; then \
		echo "PROFILE_JOBS must be a nonnegative integer" >&2; \
		exit 2; \
	fi; \
	if [[ ! "$(PROFILE_TARGET)" =~ ^[A-Za-z0-9_.-]+$$ || "$(PROFILE_TARGET)" == "all-profiles" ]]; then \
		echo "PROFILE_TARGET must name one non-recursive Make target" >&2; \
		exit 2; \
	fi; \
	set +e; \
	python3 "$(PARAMETER_PROFILE_TOOL)" list --manifest "$(PARAMETER_PROFILE_MANIFEST)" | \
		xargs --no-run-if-empty --max-procs="$(PROFILE_JOBS)" --replace={} \
		$(MAKE) --no-print-directory -f "$(abspath $(firstword $(MAKEFILE_LIST)))" PROFILE={} "$(PROFILE_TARGET)"; \
	aggregate_status=$$?; \
	python3 "$(PARAMETER_PROFILE_TOOL)" summary \
		--manifest "$(PARAMETER_PROFILE_MANIFEST)" --report-root "$(REPORT_DIR)" \
		--output "$(REPORT_DIR)/parameter-profile-summary.json"; \
	summary_status=$$?; \
	if [[ "$${summary_status}" -ne 0 ]]; then exit "$${summary_status}"; fi; \
	exit "$${aggregate_status}"

ifneq ($(filter $(PROFILE_TARGET),$(OPEN_SOURCE_TARGETS)),)
all-profiles: setup-open-source
endif
endif

## flow-config-check Validate and display the project flow selection
flow-config-check: mosaic-module-selection-check profile-evidence
	@"$(FLOW_ROOT)/ci/check_flow_config.sh"

## setup-open-source Install missing pinned open-source tools in the user cache
setup-open-source:
	@"$(FLOW_ROOT)/ci/setup_open_source_tools.sh"

$(MOSAIC_FLOW_TARGETS): | flow-config-check
$(OPEN_FLOW_TARGETS): | setup-open-source
open-waiver-draft: mosaic-module-selection-check | setup-open-source

## open-source  Run every open-source CI check and its quality gate
open-source: open-quality-gate

## open-style-lint Run Verible style lint with reviewed waivers
open-style-lint:
	@"$(FLOW_RUNNER)" verible_lint "$(FLOW_ROOT)/flows/verible/run_lint.sh"

## open-format-check Check SystemVerilog formatting with Verible
open-format-check:
	@"$(FLOW_RUNNER)" verible_format "$(FLOW_ROOT)/flows/verible/run_format.sh"

## open-elaborate Compile and elaborate the RTL independently with Slang
open-elaborate:
	@"$(FLOW_RUNNER)" slang_elaboration "$(FLOW_ROOT)/flows/slang/run.sh"

## open-lint    Run strict open-source lint with Verilator
open-lint:
	@"$(FLOW_RUNNER)" verilator_lint "$(FLOW_ROOT)/flows/verilator_lint/run.sh"

## open-waiver-draft Generate suggested Verilator waivers for review
open-waiver-draft:
	@"$(FLOW_ROOT)/flows/verilator_lint/generate_waivers.sh"

## open-synth   Run technology-independent synthesis with Yosys
open-synth:
	@"$(FLOW_RUNNER)" yosys_synthesis "$(FLOW_ROOT)/flows/yosys_synthesis/run.sh"

## open-formal  Run formal verification with SymbiYosys
open-formal:
	@"$(FLOW_RUNNER)" symbiyosys_formal "$(FLOW_ROOT)/flows/symbiyosys/run.sh"

## open-equivalence Prove RTL-to-synthesized-netlist equivalence with EQY
open-equivalence:
	@"$(FLOW_RUNNER)" eqy_equivalence "$(FLOW_ROOT)/flows/eqy/run.sh"

## open-sim     Compile and simulate with Verilator
open-sim:
	@SIMULATOR=verilator "$(FLOW_RUNNER)" verilator_sim "$(FLOW_ROOT)/flows/sim/run.sh"

## open-pyuvm   Run an enabled PyUVM test with the selected open-source simulator
open-pyuvm:
	@PYUVM_SIMULATOR="$(PYUVM_OPEN_SIMULATOR)" "$(FLOW_RUNNER)" pyuvm_open_source "$(FLOW_ROOT)/flows/pyuvm/run.sh" pyuvm_open_source

## open-coverage Qualify native HDL and optional formal coverage evidence
open-coverage:
	@"$(FLOW_RUNNER)" coverage_qualification "$(FLOW_ROOT)/flows/coverage/run.sh"

## open-negative Prove module-owned faults and invalid configurations are detected
open-negative:
	@"$(FLOW_RUNNER)" negative_qualification "$(FLOW_ROOT)/flows/qualification/run.sh" negative

## open-four-state Detect declared X/Z controls with pinned Icarus simulation
open-four-state:
	@"$(FLOW_RUNNER)" four_state_qualification "$(FLOW_ROOT)/flows/qualification/run.sh" four_state

## open-static-intent Validate portable SDC and UPF intent without EDA licenses
open-static-intent:
	@"$(FLOW_RUNNER)" static_intent "$(FLOW_ROOT)/flows/static_intent/run.sh"

## open-quality-gate Validate all open-source results
open-quality-gate: $(OPEN_FLOW_TARGETS)
	@"$(FLOW_ROOT)/ci/open_source_quality_gate.sh"

## open-physical Run the optional OpenROAD PDK-backed implementation flow
open-physical:
	@"$(FLOW_RUNNER)" openroad "$(FLOW_ROOT)/flows/openroad/run.sh"

## synopsys-check-env Check local Synopsys executable availability
synopsys-check-env:
	@"$(FLOW_ROOT)/ci/check_synopsys_environment.sh"

## synopsys-sim Compile and simulate locally with VCS
synopsys-sim:
	@SIMULATOR=vcs "$(FLOW_RUNNER)" vcs_sim "$(FLOW_ROOT)/flows/sim/run.sh"

## commercial-pyuvm Run an enabled PyUVM test with VCS or Xcelium
commercial-pyuvm: | setup-open-source
	@PYUVM_SIMULATOR="$(PYUVM_COMMERCIAL_SIMULATOR)" "$(FLOW_RUNNER)" pyuvm_commercial "$(FLOW_ROOT)/flows/pyuvm/run.sh" pyuvm_commercial

## synopsys-lint Run VC Lint locally
synopsys-lint:
	@"$(FLOW_RUNNER)" vc_lint "$(FLOW_ROOT)/flows/vc_lint/run.sh"

## synopsys-cdc Run CDC locally with CDC_TOOL=vc or CDC_TOOL=sg
synopsys-cdc:
	@"$(FLOW_RUNNER)" "$(CDC_TOOL)_cdc" "$(FLOW_ROOT)/flows/cdc/run.sh" "$(CDC_TOOL)"

## synopsys-dft Run SpyGlass DFT checks locally
synopsys-dft:
	@"$(FLOW_RUNNER)" sg_dft "$(FLOW_ROOT)/flows/sg_dft/run.sh"

## synopsys-lp  Run VC LP checks locally
synopsys-lp:
	@"$(FLOW_RUNNER)" vc_lp "$(FLOW_ROOT)/flows/vc_lp/run.sh"

## synopsys-static Run all local Synopsys static RTL checks
synopsys-static: synopsys-lint synopsys-cdc synopsys-dft synopsys-lp

## synopsys-synth Run technology-mapped synthesis locally
synopsys-synth:
	@"$(FLOW_RUNNER)" synopsys_synthesis "$(FLOW_ROOT)/flows/synthesis/run.sh"

## synopsys-sta Run PrimeTime static timing analysis locally
synopsys-sta:
	@"$(FLOW_RUNNER)" synopsys_primetime "$(FLOW_ROOT)/flows/primetime/run.sh"

## synopsys-power Run PrimePower locally using annotated activity
synopsys-power:
	@"$(FLOW_RUNNER)" synopsys_primepower "$(FLOW_ROOT)/flows/primepower/run.sh"

## synopsys-quality-gate Validate all commercial-tool results
synopsys-quality-gate: synopsys-sim synopsys-static synopsys-synth synopsys-sta synopsys-power | synopsys-check-env
	@"$(FLOW_ROOT)/ci/synopsys_quality_gate.sh"

## synopsys-all Run the complete licensed local Synopsys flow
synopsys-all: synopsys-quality-gate

## clean        Remove generated work and reports
clean:
	@"$(FLOW_ROOT)/ci/clean.sh"
