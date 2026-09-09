# Bootstrap either the legacy single-module layout or a manifest-based project.
ifndef MODULE_ROOT
$(error MODULE_ROOT must identify the consuming repository root)
endif
ifndef FLOW_ROOT
$(error FLOW_ROOT must identify the mosaic-flow checkout)
endif

export MODULE_MANIFEST ?= $(MODULE_ROOT)/config/modules.json
export MOSAIC_MODULE_MANIFEST_TOOL ?= $(FLOW_ROOT)/ci/module_manifest.py
export MOSAIC_MULTI_MODULE := $(if $(wildcard $(MODULE_MANIFEST)),enabled,disabled)
MOSAIC_PROJECT_MAKEFILE ?= $(abspath $(firstword $(MAKEFILE_LIST)))
MODULE_JOBS ?= $(if $(JOBS),$(JOBS),0)
TARGET ?= open-source

# Module profiles can use these helpers after assigning DESIGN_TOP. A named
# input takes precedence while the repository-wide file remains the fallback.
mosaic_resolve_filelist = $(or $(wildcard $(MODULE_ROOT)/filelists/$(DESIGN_TOP).$(1)),$(MODULE_ROOT)/filelists/$(1))
mosaic_resolve_flow_config = $(or $(wildcard $(MODULE_ROOT)/flows/$(1)/$(DESIGN_TOP).$(2)),$(MODULE_ROOT)/flows/$(1)/$(2))

ifeq ($(MOSAIC_MULTI_MODULE),enabled)
ifneq ($(strip $(MODULE)),)
MOSAIC_MODULE_VALIDATION_ERROR := $(shell python3 "$(MOSAIC_MODULE_MANIFEST_TOOL)" validate --quiet --manifest "$(MODULE_MANIFEST)" --module-root "$(MODULE_ROOT)" --selected "$(MODULE)" 2>&1)
ifneq ($(strip $(MOSAIC_MODULE_VALIDATION_ERROR)),)
$(error $(MOSAIC_MODULE_VALIDATION_ERROR))
endif

export MODULE_DESIGN_CONFIG ?= $(MODULE_ROOT)/config/modules/$(MODULE).mk
export MODULE_FLOW_CONFIG ?= $(MODULE_ROOT)/config/modules/$(MODULE)-flows.mk
include $(MODULE_DESIGN_CONFIG)

# A module may override these paths, but isolation is the safe default.
export REPORT_DIR ?= $(MODULE_ROOT)/reports/$(MODULE)
export WORK_DIR ?= $(MODULE_ROOT)/work/$(MODULE)
else
# Administrative targets can inspect or dispatch the manifest without choosing
# a design. Flow targets reject the missing selection before launching tools,
# and clean.sh uses repository-wide fallbacks without exporting them to child
# module invocations.
endif
else
export MODULE_DESIGN_CONFIG ?= $(MODULE_ROOT)/config/design.mk
export MODULE_FLOW_CONFIG ?= $(MODULE_ROOT)/config/flows.mk
include $(MODULE_DESIGN_CONFIG)
endif

include $(FLOW_ROOT)/config/tools.mk
include $(FLOW_ROOT)/mk/module.mk

ifeq ($(MOSAIC_MULTI_MODULE),enabled)
.PHONY: module-manifest-check module-list module-matrix all-modules

## module-manifest-check Validate a multi-module project registry and layout
module-manifest-check:
	@python3 "$(MOSAIC_MODULE_MANIFEST_TOOL)" validate \
		--manifest "$(MODULE_MANIFEST)" --module-root "$(MODULE_ROOT)"

## module-list Print registered module names, one per line
module-list:
	@python3 "$(MOSAIC_MODULE_MANIFEST_TOOL)" list \
		--manifest "$(MODULE_MANIFEST)" --module-root "$(MODULE_ROOT)"

## module-matrix Emit the registered modules as a GitHub Actions JSON matrix
module-matrix:
	@python3 "$(MOSAIC_MODULE_MANIFEST_TOOL)" matrix \
		--manifest "$(MODULE_MANIFEST)" --module-root "$(MODULE_ROOT)"

## all-modules Run TARGET for every registered module with bounded parallelism
all-modules: module-manifest-check
	+@if [[ ! "$(MODULE_JOBS)" =~ ^[0-9]+$$ ]]; then \
		echo "MODULE_JOBS must be a nonnegative integer" >&2; \
		exit 2; \
	fi; \
	if [[ ! "$(TARGET)" =~ ^[A-Za-z0-9_.-]+$$ || "$(TARGET)" == "all-modules" ]]; then \
		echo "TARGET must name one non-recursive Make target" >&2; \
		exit 2; \
	fi; \
	python3 "$(MOSAIC_MODULE_MANIFEST_TOOL)" list \
		--manifest "$(MODULE_MANIFEST)" --module-root "$(MODULE_ROOT)" | \
		xargs --no-run-if-empty --max-procs="$(MODULE_JOBS)" --replace={} \
		$(MAKE) --no-print-directory -f "$(MOSAIC_PROJECT_MAKEFILE)" MODULE={} "$(TARGET)"

# Populate the shared tool cache once before open-source module jobs run in
# parallel. Child invocations retain their normal setup prerequisite as a
# defensive check.
ifneq ($(filter $(TARGET),$(OPEN_SOURCE_TARGETS)),)
all-modules: setup-open-source
endif
endif
