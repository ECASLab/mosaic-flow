SHELL := /usr/bin/env bash

export MODULE_ROOT := $(CURDIR)
export FLOW_ROOT ?= $(abspath $(MODULE_ROOT)/../..)

include config/design.mk
include $(FLOW_ROOT)/config/tools.mk
include $(FLOW_ROOT)/mk/module.mk

.PHONY: profile-probe

profile-probe: profile-evidence
	@mkdir -p "$(REPORT_DIR)/probe" "$(WORK_DIR)/probe"
	@if [[ "$(FAIL_PROFILE)" == "$(PROFILE)" ]]; then \
		printf 'FAIL\n' >"$(REPORT_DIR)/probe/status.txt"; \
		exit 1; \
	fi
	@printf 'PASS\n' >"$(REPORT_DIR)/probe/status.txt"
