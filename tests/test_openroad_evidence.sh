#!/usr/bin/env bash
set -euo pipefail

flow_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf "${fixture_root}"' EXIT

module_root="${fixture_root}/module"
orfs_root="${fixture_root}/orfs"
mkdir -p \
  "${module_root}/config" \
  "${module_root}/constraints" \
  "${module_root}/filelists" \
  "${module_root}/rtl" \
  "${module_root}/tools" \
  "${orfs_root}/flow"
printf 'module dut(input logic clk_i); endmodule\n' >"${module_root}/rtl/dut.sv"
printf '%s\n' "${module_root}/rtl/dut.sv" >"${module_root}/filelists/rtl.f"
cp "${module_root}/filelists/rtl.f" "${module_root}/filelists/tb.f"
printf 'create_clock -period 10 [get_ports clk_i]\n' >"${module_root}/constraints/timing.sdc"
cat >"${module_root}/config/openroad.mk" <<'EOF'
export DESIGN_NAME = dut
export PLATFORM = $(OPENROAD_PLATFORM)
export VERILOG_FILES = $(REPO_ROOT)/rtl/dut.sv
export SDC_FILE = $(REPO_ROOT)/constraints/timing.sdc
EOF
cat >"${module_root}/config/openroad-evidence.json" <<'EOF'
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
    {"name": "setup_violations", "directory": "reports", "path": "6_finish.rpt", "pattern": "setup violation count +(?P<value>[0-9]+)", "maximum": 0},
    {"name": "hold_violations", "directory": "reports", "path": "6_finish.rpt", "pattern": "hold violation count +(?P<value>[0-9]+)", "maximum": 0},
    {"name": "slew_violations", "directory": "reports", "path": "6_finish.rpt", "pattern": "slew violation count +(?P<value>[0-9]+)", "maximum": 0},
    {"name": "fanout_violations", "directory": "reports", "path": "6_finish.rpt", "pattern": "fanout violation count +(?P<value>[0-9]+)", "maximum": 0},
    {"name": "capacitance_violations", "directory": "reports", "path": "6_finish.rpt", "pattern": "capacitance violation count +(?P<value>[0-9]+)", "maximum": 0},
    {"name": "routing_violations", "directory": "logs", "path": "5_2_route.log", "pattern": "Number of violations = (?P<value>[0-9]+)", "maximum": 0}
  ]
}
EOF

cat >"${orfs_root}/flow/Makefile" <<'EOF'
.RECIPEPREFIX := >
.PHONY: all
all:
>mkdir -p "$(WORK_HOME)/results/$(PLATFORM)/$(DESIGN_NICKNAME)/$(FLOW_VARIANT)"
>mkdir -p "$(WORK_HOME)/reports/$(PLATFORM)/$(DESIGN_NICKNAME)/$(FLOW_VARIANT)"
>mkdir -p "$(WORK_HOME)/logs/$(PLATFORM)/$(DESIGN_NICKNAME)/$(FLOW_VARIANT)"
>mkdir -p "$(WORK_HOME)/objects/$(PLATFORM)/$(DESIGN_NICKNAME)/$(FLOW_VARIANT)"
>for artifact in 6_final.def 6_final.gds 6_final.odb 6_final.sdc 6_final.v; do printf 'fixture\n' >"$(WORK_HOME)/results/$(PLATFORM)/$(DESIGN_NICKNAME)/$(FLOW_VARIANT)/$${artifact}"; done
>printf 'setup violation count 0\nhold violation count 0\nslew violation count 0\nfanout violation count 0\ncapacitance violation count 0\n' >"$(WORK_HOME)/reports/$(PLATFORM)/$(DESIGN_NICKNAME)/$(FLOW_VARIANT)/6_finish.rpt"
>printf 'Number of violations = 0\n' >"$(WORK_HOME)/logs/$(PLATFORM)/$(DESIGN_NICKNAME)/$(FLOW_VARIANT)/5_2_route.log"
EOF

common_environment=(
  "MODULE_ROOT=${module_root}"
  "FLOW_ROOT=${flow_root}"
  "DESIGN_TOP=dut"
  "TB_TOP=dut_tb"
  "FORMAL_TOP=dut_formal"
  "DUT_INSTANCE=dut_tb/dut"
  "RTL_FILELIST=${module_root}/filelists/rtl.f"
  "TB_FILELIST=${module_root}/filelists/tb.f"
  "CONSTRAINT_DIR=${module_root}/constraints"
  "OPENROAD_CONFIG=${module_root}/config/openroad.mk"
  "OPENROAD_CONSTRAINT_FILE=${module_root}/constraints/timing.sdc"
  "OPENROAD_EVIDENCE_POLICY=${module_root}/config/openroad-evidence.json"
  "OPENROAD_EVIDENCE_TOOL=${flow_root}/ci/openroad_evidence.py"
  "OPENROAD_EXECUTION_MODE=local"
  "OPENROAD_FLOW_ROOT=${orfs_root}"
  "OPENROAD_PLATFORM=nangate45"
)

run_profile() {
  local profile="$1"
  env "${common_environment[@]}" \
    OPENROAD_DESIGN_NAME="dut_${profile}" \
    OPENROAD_FLOW_VARIANT="${profile}" \
    REPORT_DIR="${module_root}/reports/${profile}" \
    WORK_DIR="${module_root}/work/${profile}" \
    "${flow_root}/flows/openroad/run.sh"
}

# Concurrent profile runs must retain independent ORFS and normalized evidence.
run_profile narrow &
narrow_pid=$!
run_profile wide &
wide_pid=$!
wait "${narrow_pid}"
wait "${wide_pid}"
for profile in narrow wide; do
  test "$(<"${module_root}/reports/${profile}/openroad/status.txt")" = PASS
  grep -Fq '"status": "PASS"' \
    "${module_root}/reports/${profile}/openroad/evidence.json"
  test -s "${module_root}/work/${profile}/openroad/results/nangate45/dut_${profile}/${profile}/6_final.gds"
done

expect_failure() {
  local expected="$1"
  shift
  if "$@" >"${fixture_root}/failure.log" 2>&1; then
    echo "Expected OpenROAD failure containing: ${expected}" >&2
    exit 1
  fi
  if ! grep -Fq "${expected}" "${fixture_root}/failure.log"; then
    echo "OpenROAD failure did not contain: ${expected}" >&2
    cat "${fixture_root}/failure.log" >&2
    exit 1
  fi
}

wide_root="${module_root}/work/wide/openroad"

expect_failure "Container image reference digest does not match the recorded digest" \
  "${flow_root}/ci/openroad_evidence.py" \
    --module-root "${module_root}" \
    --policy "${module_root}/config/openroad-evidence.json" \
    --evidence-root "${wide_root}" \
    --design-config "${module_root}/config/openroad.mk" \
    --constraint "${module_root}/constraints/timing.sdc" \
    --output "${module_root}/reports/image-mismatch.json" \
    --execution-mode container --design dut_wide --platform nangate45 --variant wide \
    --image-reference "openroad/orfs@sha256:$(printf '0%.0s' {1..64})" \
    --image-digest "sha256:d995618be9f2bcdfa5538b885123463070dfbf178bea1818716d4652fe0fa380"
grep -Fq '"status": "FAIL"' "${module_root}/reports/image-mismatch.json"

rm "${wide_root}/results/nangate45/dut_wide/wide/6_final.gds"
expect_failure "Missing required artifact final_gds" \
  "${flow_root}/ci/openroad_evidence.py" \
    --module-root "${module_root}" \
    --policy "${module_root}/config/openroad-evidence.json" \
    --evidence-root "${wide_root}" \
    --design-config "${module_root}/config/openroad.mk" \
    --constraint "${module_root}/constraints/timing.sdc" \
    --output "${module_root}/reports/missing-artifact.json" \
    --execution-mode local --design dut_wide --platform nangate45 --variant wide
grep -Fq '"status": "FAIL"' "${module_root}/reports/missing-artifact.json"

: >"${wide_root}/results/nangate45/dut_wide/wide/6_final.gds"
expect_failure "Empty required artifact final_gds" \
  "${flow_root}/ci/openroad_evidence.py" \
    --module-root "${module_root}" \
    --policy "${module_root}/config/openroad-evidence.json" \
    --evidence-root "${wide_root}" \
    --design-config "${module_root}/config/openroad.mk" \
    --constraint "${module_root}/constraints/timing.sdc" \
    --output "${module_root}/reports/empty-artifact.json" \
    --execution-mode local --design dut_wide --platform nangate45 --variant wide
grep -Fq '"status": "FAIL"' "${module_root}/reports/empty-artifact.json"

printf 'fixture\n' >"${wide_root}/results/nangate45/dut_wide/wide/6_final.gds"
printf 'Number of violations = 2\n' \
  >"${wide_root}/logs/nangate45/dut_wide/wide/5_2_route.log"
expect_failure "Metric routing_violations is 2, expected maximum 0" \
  "${flow_root}/ci/openroad_evidence.py" \
    --module-root "${module_root}" \
    --policy "${module_root}/config/openroad-evidence.json" \
    --evidence-root "${wide_root}" \
    --design-config "${module_root}/config/openroad.mk" \
    --constraint "${module_root}/constraints/timing.sdc" \
    --output "${module_root}/reports/routing-violation.json" \
    --execution-mode local --design dut_wide --platform nangate45 --variant wide

printf 'Number of violations = 0\n' \
  >"${wide_root}/logs/nangate45/dut_wide/wide/5_2_route.log"
sed -i 's/setup violation count 0/setup violation count 3/' \
  "${wide_root}/reports/nangate45/dut_wide/wide/6_finish.rpt"
expect_failure "Metric setup_violations is 3, expected maximum 0" \
  "${flow_root}/ci/openroad_evidence.py" \
    --module-root "${module_root}" \
    --policy "${module_root}/config/openroad-evidence.json" \
    --evidence-root "${wide_root}" \
    --design-config "${module_root}/config/openroad.mk" \
    --constraint "${module_root}/constraints/timing.sdc" \
    --output "${module_root}/reports/setup-violation.json" \
    --execution-mode local --design dut_wide --platform nangate45 --variant wide

expect_failure "must use an immutable @sha256 digest" env \
  "${common_environment[@]}" \
  OPENROAD_EXECUTION_MODE=container \
  OPENROAD_ORFS_IMAGE=openroad/orfs:latest \
  REPORT_DIR="${module_root}/reports/floating" \
  WORK_DIR="${module_root}/work/floating" \
  OPENROAD_DESIGN_NAME=dut \
  OPENROAD_FLOW_VARIANT=floating \
  "${flow_root}/flows/openroad/run.sh"
test "$(<"${module_root}/reports/floating/openroad/status.txt")" = FAIL

expect_failure "container runtime is unavailable" env \
  "${common_environment[@]}" \
  OPENROAD_EXECUTION_MODE=container \
  OPENROAD_CONTAINER_RUNTIME=mosaic-missing-runtime \
  OPENROAD_ORFS_IMAGE=openroad/orfs@sha256:d995618be9f2bcdfa5538b885123463070dfbf178bea1818716d4652fe0fa380 \
  REPORT_DIR="${module_root}/reports/runtime" \
  WORK_DIR="${module_root}/work/runtime" \
  OPENROAD_DESIGN_NAME=dut \
  OPENROAD_FLOW_VARIANT=runtime \
  "${flow_root}/flows/openroad/run.sh"
test "$(<"${module_root}/reports/runtime/openroad/status.txt")" = FAIL

skip_reports="${module_root}/reports/skip"
env \
  MODULE_ROOT="${module_root}" \
  REPORT_DIR="${skip_reports}" \
  MOSAIC_FLOW_IDS=openroad \
  FLOW_openroad=enabled \
  FLOW_DEPENDENCIES_openroad= \
  DISABLED_FLOWS=openroad \
  "${flow_root}/ci/run_flow.sh" openroad false >/dev/null
test "$(<"${skip_reports}/openroad/status.txt")" = SKIP
grep -Fq 'Disabled by DISABLED_FLOWS' \
  "${skip_reports}/openroad/skip_reason.txt"

cat >"${module_root}/tools/fake-runtime" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  --version)
    echo "fake-runtime 1.0"
    ;;
  image)
    [[ "${2:-}" == inspect && -f "${FAKE_RUNTIME_STATE}" ]]
    ;;
  pull)
    printf 'available\n' >"${FAKE_RUNTIME_STATE}"
    ;;
  save)
    [[ "${2:-}" == --output ]]
    printf 'cached layers\n' >"${3}"
    ;;
  load)
    [[ "${2:-}" == --input && -s "${3}" ]]
    printf 'available\n' >"${FAKE_RUNTIME_STATE}"
    ;;
  *)
    echo "Unexpected fake runtime command: $*" >&2
    exit 2
    ;;
esac
EOF
chmod +x "${module_root}/tools/fake-runtime"
cache_root="${fixture_root}/image-cache"
runtime_state="${fixture_root}/runtime-state"
pinned_image="openroad/orfs@sha256:d995618be9f2bcdfa5538b885123463070dfbf178bea1818716d4652fe0fa380"
env \
  PATH="${module_root}/tools:${PATH}" \
  FAKE_RUNTIME_STATE="${runtime_state}" \
  OPENROAD_CONTAINER_RUNTIME=fake-runtime \
  OPENROAD_ORFS_IMAGE="${pinned_image}" \
  OPENROAD_IMAGE_CACHE_ROOT="${cache_root}" \
  "${flow_root}/ci/cache_openroad_image.sh" >/dev/null
archive="${cache_root}/d995618be9f2bcdfa5538b885123463070dfbf178bea1818716d4652fe0fa380.tar"
test -s "${archive}"
rm "${runtime_state}"
env \
  PATH="${module_root}/tools:${PATH}" \
  FAKE_RUNTIME_STATE="${runtime_state}" \
  OPENROAD_CONTAINER_RUNTIME=fake-runtime \
  OPENROAD_ORFS_IMAGE="${pinned_image}" \
  OPENROAD_IMAGE_CACHE_ROOT="${cache_root}" \
  "${flow_root}/ci/cache_openroad_image.sh" >/dev/null
test -s "${runtime_state}"

echo "OpenROAD execution and physical evidence policy tests passed"
