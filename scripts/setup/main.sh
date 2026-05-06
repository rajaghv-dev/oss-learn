#!/bin/bash
# =============================================================================
# main.sh — oss-learn Master Setup Orchestrator
#
# Runs each component setup script in order, tracks pass/fail per step,
# and prints a comprehensive summary at the end.
#
# COMPONENTS (run in order):
#   1.  preflight.sh      — OS, Python 3.10+, Docker, disk, RAM
#   2.  docker.sh         — Docker Engine + Compose v2 (apt/brew)
#   3.  python.sh         — shared venv + pip upgrade + shared deps
#   4.  postgres.sh       — PostgreSQL 16 + pgvector + Apache AGE (Docker)
#   5.  openvino.sh       — Intel OpenVINO inference engine (pip, CPU)
#   6.  onnxruntime.sh    — ONNX Runtime CPU (pip)
#   7.  ollama.sh         — Ollama LLM server (system install + model pull)
#   8.  llama_cpp.sh      — llama.cpp prebuilt binaries or source build
#   9.  registry.sh       — local Docker registry (localhost:5000)
#  10.  observability.sh  — Prometheus + Grafana + Blackbox + OTel Collector
#  11.  opensearch.sh     — OpenSearch + Dashboards
#  12.  git.sh            — Gitea self-hosted git server (localhost:3001)
#  13.  plane.sh          — Plane project management (localhost:4000)
#  14.  nocobase.sh       — NocoBase low-code platform (localhost:13000)
#  15.  wireshark.sh      — Wireshark + tshark CLI (system install)
#  16.  pyshark.sh        — pyshark Python wrapper (pip into venv)
#  17.  k8s.sh            — k3s + kubectl + helm (Linux/WSL2; for k8s learning)
#  18.  minikube.sh       — minikube + kubectl (cross-platform; for k8s learning)
#
# USAGE:
#   bash setup.sh                          # full setup
#   bash setup.sh --check                  # show status, no changes
#   bash setup.sh --step postgres          # run only one step
#   bash setup.sh --skip ollama            # skip a step
#   bash setup.sh --force                  # redo all steps
#   bash setup.sh --no-model              # skip LLM model downloads
#   bash setup.sh --dry-run               # print actions only
#
# EXIT CODES:
#   0 — all steps passed (or skipped)
#   1 — one or more steps failed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

STATE_DIR="$REPO_ROOT/setup/state"
mkdir -p "$STATE_DIR"

source "$REPO_ROOT/scripts/common.sh"
set_script_log "setup_main"

log_info "════════════════════════════════════════════════════════"
log_info "oss-learn Master Setup Orchestrator started"
log_info "  Repository : $REPO_ROOT"
log_info "  State dir  : $STATE_DIR"
log_info "════════════════════════════════════════════════════════"

# ── Colors ───────────────────────────────────────────────────────────────────
if [ -t 1 ] && command -v tput &>/dev/null && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  C_RST=$(tput sgr0); C_BLD=$(tput bold)
  C_BLU="${C_BLD}$(tput setaf 4)"; C_GRN="${C_BLD}$(tput setaf 2)"
  C_YLW="${C_BLD}$(tput setaf 3)"; C_RED="${C_BLD}$(tput setaf 1)"
  C_CYN="${C_BLD}$(tput setaf 6)"; C_GRY=$(tput setaf 7)
  C_WHT="${C_BLD}$(tput setaf 15)"
else
  C_RST="" C_BLD="" C_BLU="" C_GRN="" C_YLW="" C_RED="" C_CYN="" C_GRY="" C_WHT=""
fi

_ts()     { date '+%Y-%m-%d %H:%M:%S'; }
_ts_short() { date '+%H:%M:%S'; }
banner()  {
  echo ""
  echo "${C_BLU}══════════════════════════════════════════════════════════════${C_RST}"
  echo "${C_BLU}  $1${C_RST}"
  echo "${C_BLU}══════════════════════════════════════════════════════════════${C_RST}"
}
minfo()  { echo "${C_GRN}  ✓  $1${C_RST}"; }
mwarn()  { echo "${C_YLW}  ⚠  $1${C_RST}"; }
merr()   { echo "${C_RED}  ✗  $1${C_RST}" >&2; }
mstep()  { echo "${C_CYN}  →  $1${C_RST}"; }
mskip()  { echo "${C_GRY}  ↷  $1 (already done — skipping)${C_RST}"; }
stamp()   { echo "$(_ts)" > "$STATE_DIR/${1}.done"; }
stamped() { [ -f "$STATE_DIR/${1}.done" ]; }

# ── Parse arguments ──────────────────────────────────────────────────────────
CHECK_ONLY=0; FORCE=0; DRY_RUN=0; NO_MODEL=0
ONLY_STEP=""; SKIP_STEPS=()
AGE_VERSION="${AGE_VERSION:-v1.5.0-rc0}"

while [ $# -gt 0 ]; do
  case "$1" in
    --check)    CHECK_ONLY=1 ;;
    --force)    FORCE=1 ;;
    --dry-run)  DRY_RUN=1 ;;
    --no-model) NO_MODEL=1 ;;
    --age)      shift; AGE_VERSION="$1" ;;
    --step)     shift; ONLY_STEP="$1" ;;
    --skip)     shift
                while [ $# -gt 0 ] && [[ "${1:-}" != --* ]]; do
                  SKIP_STEPS+=("$1"); shift
                done
                continue ;;
    --help|-h)  grep '^#' "${BASH_SOURCE[0]}" | head -30 | sed 's/^# \?//'; exit 0 ;;
    *)          mwarn "Unknown argument: $1" ;;
  esac
  shift
done

export AGE_TAG="PG16/${AGE_VERSION}"
export AGE_DIR="age-PG16-${AGE_VERSION}"

# ── Step definitions ─────────────────────────────────────────────────────────
# Format: name|label|script|extra_flags
STEPS=(
  "preflight|Preflight checks|preflight.sh|"
  "docker|Docker Engine + Compose v2|docker.sh|"
  "python|Python venv + shared deps|python.sh|"
  "postgres|PostgreSQL + pgvector + AGE|postgres.sh|--age $AGE_VERSION"
  "openvino|OpenVINO inference engine (CPU)|openvino.sh|"
  "onnxruntime|ONNX Runtime (CPU)|onnxruntime.sh|"
  "ollama|Ollama LLM server|ollama.sh|"
  "llama_cpp|llama.cpp binaries|llama_cpp.sh|"
  "registry|Local Docker registry|registry.sh|"
  "observability|Prometheus + Grafana + Blackbox + OTel|observability.sh|"
  "opensearch|OpenSearch + Dashboards|opensearch.sh|"
  "git|Gitea self-hosted git (:3001)|git.sh|"
  "plane|Plane project management (:4000)|plane.sh|"
  "nocobase|NocoBase low-code (:13000)|nocobase.sh|"
  "wireshark|Wireshark + tshark CLI|wireshark.sh|"
  "pyshark|pyshark Python wrapper|pyshark.sh|"
  "k8s|k3s + kubectl + helm (Linux/WSL2)|k8s.sh|"
  "minikube|minikube + kubectl (cross-platform)|minikube.sh|"
)

# ── Helpers ──────────────────────────────────────────────────────────────────
should_run() {
  local name="$1"
  [ -n "$ONLY_STEP" ] && [ "$name" != "$ONLY_STEP" ] && return 1
  if [ "$ONLY_STEP" = "ai" ]; then
    case "$name" in openvino|onnxruntime|ollama|llama_cpp) return 0 ;; esac
  fi
  local s
  for s in "${SKIP_STEPS[@]:-}"; do
    [ "$s" = "$name" ] && return 1
    if [ "$s" = "ai" ]; then
      case "$name" in openvino|onnxruntime|ollama|llama_cpp) return 1 ;; esac
    fi
  done
  return 0
}

build_flags() {
  local name="$1" extra="$2"
  local flags=()
  [ "$CHECK_ONLY" -eq 1 ] && flags+=("--check")
  [ "$FORCE" -eq 1 ]      && flags+=("--force")
  if [ "$NO_MODEL" -eq 1 ]; then
    case "$name" in ollama|llama_cpp) flags+=("--no-model") ;; esac
  fi
  [ -n "$extra" ] && flags+=($extra)
  echo "${flags[*]:-}"
}

FAILED_STEPS=(); PASSED_STEPS=(); SKIPPED_STEPS=()
declare -A STEP_DURATIONS=()
SETUP_START=$(date +%s)

# ── Banner ───────────────────────────────────────────────────────────────────
banner "oss-learn — Master Setup  (step 1 of 3: setup → validate → start)  [${#STEPS[@]} components]"
echo ""
echo "  ${C_WHT}Configuration${C_RST}"
echo "  ─────────────────────────────────────────────────────"
echo "  Repo       : $REPO_ROOT"
echo "  State dir  : $STATE_DIR"
echo -n "  Mode       : "
[ "$CHECK_ONLY" -eq 1 ] && echo -n "CHECK-ONLY" || echo -n "INSTALL"
[ "$FORCE" -eq 1 ]      && echo -n " + FORCE"
[ "$DRY_RUN" -eq 1 ]    && echo -n " + DRY-RUN"
echo ""
echo "  AGE version: ${AGE_TAG}"
echo "  Models     : $([ "$NO_MODEL" -eq 1 ] && echo 'SKIP (--no-model)' || echo 'will download')"
[ -n "$ONLY_STEP" ] && echo "  Only       : $ONLY_STEP"
echo ""

# ── Sudo pre-check ───────────────────────────────────────────────────────────
if [ "$CHECK_ONLY" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  if command -v sudo &>/dev/null; then
    mstep "Requesting sudo credentials up front (Ollama install may need sudo)..."
    if sudo -v 2>/dev/null; then
      minfo "sudo credential acquired"
      ( while true; do sudo -n true; sleep 55; done ) &
      _SUDO_PID=$!
      trap 'kill "$_SUDO_PID" 2>/dev/null || true' EXIT
    else
      mwarn "sudo not available — steps that need it may prompt again"
    fi
  fi
  echo ""
fi

# =============================================================================
# RUN EACH STEP
# =============================================================================
run_step() {
  local name="$1" label="$2" script="$3" extra="$4"
  local script_path="$SCRIPT_DIR/$script"

  if ! should_run "$name"; then
    SKIPPED_STEPS+=("$name")
    return 0
  fi
  if stamped "step_${name}" && [ "$FORCE" -eq 0 ]; then
    mskip "$label"
    PASSED_STEPS+=("$name")
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  ${C_GRY}[dry-run] would run: scripts/setup/$script $(build_flags "$name" "$extra")${C_RST}"
    return 0
  fi
  if [ ! -f "$script_path" ]; then
    merr "Script not found: $script_path — skipping $name"
    FAILED_STEPS+=("$name")
    return 0
  fi

  local step_start step_end elapsed rc=0
  step_start=$(date +%s)

  banner "[$(_ts_short)] Step: $label"
  echo ""

  local flags
  flags=$(build_flags "$name" "$extra")
  # shellcheck disable=SC2086
  bash "$script_path" $flags 2>&1 | tee -a "$LOG_FILE" "$SCRIPT_LOG" || rc=$?

  step_end=$(date +%s)
  elapsed=$(( step_end - step_start ))
  STEP_DURATIONS[$name]="${elapsed}s"

  if [ $rc -eq 0 ]; then
    echo "  ${C_GRN}━━━ $label — PASSED (${elapsed}s) ━━━${C_RST}"
    stamp "step_${name}"
    PASSED_STEPS+=("$name")
  else
    echo "  ${C_RED}━━━ $label — FAILED (exit $rc, ${elapsed}s) ━━━${C_RST}"
    FAILED_STEPS+=("$name")
    echo "    Re-run:  bash setup.sh --step $name --force"
    echo "    Skip:    bash setup.sh --skip $name"
  fi
  echo ""
}

for entry in "${STEPS[@]}"; do
  IFS='|' read -r name label script extra <<< "$entry"
  run_step "$name" "$label" "$script" "$extra"
done

# =============================================================================
# SUMMARY
# =============================================================================
SETUP_END=$(date +%s)
TOTAL_ELAPSED=$(( SETUP_END - SETUP_START ))

banner "oss-learn Master Setup — Summary"
echo ""
echo "  ${C_WHT}Step Results${C_RST}"
echo "  ─────────────────────────────────────────────────────"
step_num=0
for entry in "${STEPS[@]}"; do
  IFS='|' read -r name label _ _ <<< "$entry"
  ((step_num++)) || true
  local_dur="${STEP_DURATIONS[$name]:-}"

  if printf '%s\n' "${SKIPPED_STEPS[@]:-}" | grep -qx "$name" 2>/dev/null; then
    printf "  ${C_GRY}  %2d. ↷  %-35s  skipped${C_RST}\n" "$step_num" "$name"
  elif printf '%s\n' "${FAILED_STEPS[@]:-}" | grep -qx "$name" 2>/dev/null; then
    printf "  ${C_RED}  %2d. ✗  %-35s  FAILED  %s${C_RST}\n" "$step_num" "$name" "$local_dur"
  elif printf '%s\n' "${PASSED_STEPS[@]:-}" | grep -qx "$name" 2>/dev/null; then
    printf "  ${C_GRN}  %2d. ✓  %-35s  OK      %s${C_RST}\n" "$step_num" "$name" "$local_dur"
  else
    printf "  ${C_YLW}  %2d. ⚠  %-35s  not run${C_RST}\n" "$step_num" "$name"
  fi
done

echo ""
echo "  ${C_WHT}Totals${C_RST}"
echo "  ─────────────────────────────────────────────────────"
echo "  Passed  : ${#PASSED_STEPS[@]}"
echo "  Failed  : ${#FAILED_STEPS[@]}"
echo "  Skipped : ${#SKIPPED_STEPS[@]}"
echo "  Duration: ${TOTAL_ELAPSED}s"
echo "  Log file: $LOG_FILE"

if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
  echo ""
  echo "  ${C_GRN}━━━ All ${#PASSED_STEPS[@]} steps passed. Setup complete. ━━━${C_RST}"
  echo ""
  echo "  ${C_WHT}Next steps${C_RST}"
  echo "  ─────────────────────────────────────────────────────"
  echo "  Step 2 — Verify the installation:"
  echo "    bash validate.sh             # full validation"
  echo "    bash validate.sh --quick     # healthz probes only"
  echo ""
  echo "  Step 3 — Start the system:"
  echo "    bash start.sh                # start containers"
  echo "    bash start.sh --ai           # + AI inference"
  echo "    bash start.sh --opensearch   # + OpenSearch"
  echo ""
  echo "  Run tests with dummy data:"
  echo "    pytest tests/ -v"
  echo ""
else
  echo ""
  echo "  ${C_RED}━━━ ${#FAILED_STEPS[@]} step(s) failed: ${FAILED_STEPS[*]} ━━━${C_RST}"
  echo ""
  echo "  Re-run a failed step:"
  echo "    bash setup.sh --step <name> --force"
  echo "  Skip failing steps:"
  echo "    bash setup.sh --skip ${FAILED_STEPS[*]}"
  echo ""
  exit 1
fi
