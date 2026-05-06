#!/bin/bash
# =============================================================================
# main.sh — oss-learn Master Validation Orchestrator
#
# Runs each validation suite in order, tracks pass/fail/skip, and prints
# a colour-coded summary table.
#
# SUITES (run in order):
#   docker        — Docker daemon health
#   db            — PostgreSQL + pgvector + AGE with dummy data
#   ai            — ONNX Runtime, Ollama, OpenVINO pip imports + inference
#   observability — Prometheus, Grafana, Blackbox, OTel health
#   opensearch    — OpenSearch cluster health (skip if not started)
#   git           — Gitea API health (skip if not started)
#   plane         — Plane API health (skip if not started)
#   nocobase      — NocoBase API health (skip if not started)
#   k8s           — k3s/minikube cluster health (skip if not started)
#
# FLAGS:
#   --quick         Healthz probes only (skip inference tests)
#   --suite <name>  Run one suite only
#   --no-grafana    Skip writing validation-live.json
#   --dry-run       Print what would run, execute nothing
#
# USAGE:
#   bash validate.sh                        # run all suites
#   bash validate.sh --quick                # fast mode
#   bash validate.sh --suite db             # DB tests only
#   bash validate.sh --suite ai             # AI framework tests only
#
# EXIT CODES:
#   0  — All suites passed or skipped
#   1  — One or more suites failed
# =============================================================================

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

VALIDATE_DIR="${REPO_ROOT}/scripts/validate"

source "$REPO_ROOT/scripts/common.sh"
set_script_log "validate_main"

log_info "════════════════════════════════════════════════"
log_info "oss-learn Validation Orchestrator started"
log_info "  Repository : $REPO_ROOT"
log_info "════════════════════════════════════════════════"

# ── Colors ────────────────────────────────────────────────────────────────────
if [ -t 1 ] && command -v tput &>/dev/null && [ "$(tput colors 2>/dev/null||echo 0)" -ge 8 ]; then
  C_RED=$(tput setaf 1)$(tput bold); C_GRN=$(tput setaf 2)$(tput bold)
  C_YLW=$(tput setaf 3)$(tput bold); C_CYN=$(tput setaf 6)$(tput bold)
  C_BLU=$(tput setaf 4)$(tput bold); C_GRY=$(tput setaf 7); C_RST=$(tput sgr0)
else
  C_RED=""; C_GRN=""; C_YLW=""; C_CYN=""; C_BLU=""; C_GRY=""; C_RST=""
fi

_ts()  { date '+%H:%M:%S'; }
hdr()  { echo ""; echo "${C_BLU}──── [$(_ts)]  $1 ────────────────────────────${C_RST}"; }
ok()   { echo "${C_GRN}  ✓  $1${C_RST}"; }
warn() { echo "${C_YLW}  ⚠  $1${C_RST}"; }
fail() { echo "${C_RED}  ✗  $1${C_RST}"; }
note() { echo "${C_GRY}      $1${C_RST}"; }

# ── Flags ────────────────────────────────────────────────────────────────────
QUICK=0; NO_GRAFANA=0; DRY_RUN=0
ONLY_SUITE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --quick)      QUICK=1 ;;
    --no-grafana) NO_GRAFANA=1 ;;
    --dry-run)    DRY_RUN=1 ;;
    --suite)      shift; ONLY_SUITE="$1" ;;
    --help|-h)    grep '^#   ' "$0" | sed 's/^#   //'; exit 0 ;;
    *) warn "Unknown flag: $1" ;;
  esac
  shift
done

# ── Suite tracking ────────────────────────────────────────────────────────────
declare -A SUITE_STATUS
SUITE_ORDER=(docker db ai observability opensearch git plane nocobase k8s)

for s in "${SUITE_ORDER[@]}"; do SUITE_STATUS[$s]=pending; done

_should_run() {
  [ -z "$ONLY_SUITE" ] || [ "$ONLY_SUITE" = "$1" ]
}

# ── Grafana live update ───────────────────────────────────────────────────────
VALIDATION_JSON="${REPO_ROOT}/setup/state/validation-live.json"
mkdir -p "${REPO_ROOT}/setup/state"
STARTED=$(date +%s)

_update_grafana() {
  [ "$NO_GRAFANA" -eq 1 ] && return 0
  local json='{"started":'$STARTED',"completed":0,"running":1,"suites":{'
  local first=1
  for s in "${SUITE_ORDER[@]}"; do
    local st="${SUITE_STATUS[$s]:-pending}"
    [ $first -eq 0 ] && json+=","
    json+='"'"$s"'":{"status":"'"$st"'"}'
    first=0
  done
  json+="}}"
  echo "$json" > "$VALIDATION_JSON" 2>/dev/null || true
}

_finalize_grafana() {
  [ "$NO_GRAFANA" -eq 1 ] && return 0
  local overall=pass
  for s in "${SUITE_ORDER[@]}"; do
    [ "${SUITE_STATUS[$s]:-}" = "fail" ] && overall=fail
  done
  local json='{"started":'$STARTED',"completed":'$(date +%s)',"running":0,"status":"'"$overall"'","suites":{'
  local first=1
  for s in "${SUITE_ORDER[@]}"; do
    local st="${SUITE_STATUS[$s]:-pending}"
    [ $first -eq 0 ] && json+=","
    json+='"'"$s"'":{"status":"'"$st"'"}'
    first=0
  done
  json+="}}"
  echo "$json" > "$VALIDATION_JSON" 2>/dev/null || true
}

# ── Suite runner ──────────────────────────────────────────────────────────────
_run_suite() {
  local suite="$1"
  local script="${VALIDATE_DIR}/${suite}.sh"
  local suite_start suite_end suite_dur rc=0

  if ! _should_run "$suite"; then
    return 0
  fi
  if [ ! -f "$script" ]; then
    warn "Suite script not found: $script — skipping"
    SUITE_STATUS[$suite]=skip
    _update_grafana
    return 0
  fi

  SUITE_STATUS[$suite]=running
  _update_grafana

  local flags=()
  [ "$DRY_RUN" -eq 1 ] && flags+=(--dry-run)
  [ "$QUICK" -eq 1 ]   && flags+=(--quick)

  suite_start=$(date +%s)
  echo ""
  echo "${C_BLU}╔════════════════════════════════════════════════════╗${C_RST}"
  echo "${C_BLU}║  SUITE: $suite${C_RST}"
  echo "${C_BLU}╚════════════════════════════════════════════════════╝${C_RST}"
  echo "    Script: $script"
  echo "    Flags : ${flags[*]:-<none>}"
  echo ""

  bash "$script" "${flags[@]}" 2>&1 | tee -a "$LOG_FILE" "$SCRIPT_LOG" || rc=$?

  suite_end=$(date +%s)
  suite_dur=$(( suite_end - suite_start ))

  case $rc in
    0)
      SUITE_STATUS[$suite]=pass
      echo "${C_GRN}  ✓  $suite — PASSED (${suite_dur}s)${C_RST}"
      ;;
    2)
      SUITE_STATUS[$suite]=skip
      echo "${C_GRY}  ↷  $suite — SKIPPED${C_RST}"
      ;;
    *)
      SUITE_STATUS[$suite]=fail
      echo "${C_RED}  ✗  $suite — FAILED (exit $rc, ${suite_dur}s)${C_RST}"
      echo "    Re-run: bash validate.sh --suite $suite"
      ;;
  esac

  _update_grafana
  echo ""
}

# ── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo "${C_BLU}╔══════════════════════════════════════════════════════╗${C_RST}"
echo "${C_BLU}║        oss-learn  —  Validate  (step 2 of 3)         ║${C_RST}"
echo "${C_BLU}╚══════════════════════════════════════════════════════╝${C_RST}"
echo ""
note "Workflow:  setup.sh  →  validate.sh  ← you are here  →  start.sh"
note "Mode     : $([ $QUICK -eq 1 ] && echo 'quick (healthz only)' || echo 'full')$([ $DRY_RUN -eq 1 ] && echo ' [DRY-RUN]' || echo '')"
[ -n "$ONLY_SUITE" ] && note "Suite    : $ONLY_SUITE only"
note "Grafana  : http://localhost:3000  (if running)"
echo ""

_update_grafana

# Run all suites
for suite in "${SUITE_ORDER[@]}"; do
  _run_suite "$suite"
done

# =============================================================================
# SUMMARY
# =============================================================================
_finalize_grafana
DURATION=$(( $(date +%s) - STARTED ))

echo ""
echo "${C_BLU}╔══════════════════════════════════════════════════════╗${C_RST}"
echo "${C_BLU}║                  Validation Results                  ║${C_RST}"
echo "${C_BLU}╚══════════════════════════════════════════════════════╝${C_RST}"
echo ""
printf "  %-14s  %-8s\n" "Suite" "Result"
printf "  %-14s  %-8s\n" "─────────────" "───────"

OVERALL=0
for s in "${SUITE_ORDER[@]}"; do
  st="${SUITE_STATUS[$s]:-pending}"
  case "$st" in
    pass)    printf "  %-14s  ${C_GRN}%-8s${C_RST}\n" "$s" "PASS" ;;
    fail)    printf "  %-14s  ${C_RED}%-8s${C_RST}\n" "$s" "FAIL"; OVERALL=1 ;;
    skip)    printf "  %-14s  ${C_GRY}%-8s${C_RST}\n" "$s" "SKIP" ;;
    pending) printf "  %-14s  ${C_GRY}%-8s${C_RST}\n" "$s" "---" ;;
    *)       printf "  %-14s  %s\n" "$s" "$st" ;;
  esac
done

echo ""
printf "  Duration : %ds\n" "$DURATION"
echo ""

if [ $OVERALL -eq 0 ]; then
  ok "All validation suites passed."
  echo ""
  echo "  ✓ Installation verified.  Next step:"
  echo ""
  echo "    bash start.sh              # start containers (step 3 of 3)"
  echo "    bash start.sh --ai         # + AI inference"
  echo "    pytest tests/ -v           # run tests with dummy data"
  echo ""
else
  fail "One or more suites failed — check output above."
  echo ""
  echo "  Fix and re-run specific suites:"
  echo "    bash validate.sh --suite db          # DB tests only"
  echo "    bash validate.sh --suite ai          # AI framework tests only"
  echo "    bash validate.sh --suite observability  # Prometheus/Grafana health"
  echo ""
  echo "  Or force-reinstall a component:"
  echo "    bash setup.sh --step postgres --force"
  echo "    bash setup.sh --step observability --force"
  echo ""
fi

exit $OVERALL
