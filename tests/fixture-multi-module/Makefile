SHELL := /usr/bin/env bash

export MODULE_ROOT := $(CURDIR)
export FLOW_ROOT ?= $(abspath $(MODULE_ROOT)/../..)

include $(FLOW_ROOT)/mk/project.mk

.PHONY: fixture-probe

# Cheap orchestration probe used by static tests without invoking EDA tools.
fixture-probe:
	@mkdir -p "$(REPORT_DIR)/probe" "$(WORK_DIR)/probe"
	@printf 'module=%s\ndesign_top=%s\nrtl_filelist=%s\nformal_config=%s\nreport_dir=%s\nwork_dir=%s\nformat_args=%s\n' \
		"$(MODULE)" "$(DESIGN_TOP)" "$(RTL_FILELIST)" "$(FORMAL_CONFIG)" \
		"$(REPORT_DIR)" "$(WORK_DIR)" "$(VERIBLE_FORMAT_ARGS)" \
		>"$(REPORT_DIR)/probe/config.txt"
	@printf 'generated\n' >"$(WORK_DIR)/probe/output.txt"
	@if [[ "$(FAIL_MODULE)" == "$(MODULE)" ]]; then \
		printf 'FAIL\n' >"$(REPORT_DIR)/probe/status.txt"; \
		echo "Requested fixture failure for $(MODULE)" >&2; \
		exit 1; \
	fi
	@printf 'PASS\n' >"$(REPORT_DIR)/probe/status.txt"
