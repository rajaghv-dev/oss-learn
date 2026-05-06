#!/bin/bash
# =============================================================================
# main.sh — oss-learn Master Start Orchestrator
#
# Starts the OSS tool stack in the right order and prints a dashboard URL
# summary at the end.
#
# STEPS (run in order):
#   1. docker.sh          — ensure Docker daemon is running
#   2. registry.sh        — local Docker registry (localhost:5000)
#   3. observability.sh   — Prometheus :9090, Grafana :3000, Blackbox :9115
#   4. database.sh        — PostgreSQL :5432
#   5. ai.sh              — AI containers (--ai flag)
#   6. opensearch.sh      — OpenSearch :9200 + Dashboards :5601 (--opensearch flag)
#   7. smoke.sh           — quick health-check smoke test
#
# FLAGS:
#   --ai           Start AI inference containers
#   --opensearch   Start OpenSearch + Dashboards
#   --git          Start Gitea (:3001)
#   --plane        Start Plane (:4000)
#   --nocobase     Start NocoBase (:13000)
#   --k8s          Start k3s cluster (Linux/WSL2)
#   --minikube     Start minikube cluster (cross-platform)
#   --no-obs       Skip observability stack
#   --no-registry  Skip local Docker registry
#   --dry-run      Print what would run, execute nothing
#
# USAGE:
#   bash start.sh                        # core stack (DB + observability)
#   bash start.sh --ai                   # + AI containers
#   bash start.sh --opensearch           # + OpenSearch
#   bash start.sh --ai --opensearch      # everything
#   bash start.sh --no-obs               # skip Prometheus/Grafana
#
# GRAFANA: http://localhost:3000  (admin / oss-admin)
# EXIT CODES:
#   0  — All steps passed
#   1  — One or more steps failed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

# ── Colors ────────────────────────────────────────────────────────────────────
if [ -t 1 ] && command -v tput &>/dev/null && [ "$(tput colors 2>/dev/null||echo 0)" -ge 8 ]; then
  C_RST=$(tput sgr0); C_BLD=$(tput bold)
  C_BLU="${C_BLD}$(tput setaf 4)"; C_GRN="${C_BLD}$(tput setaf 2)"
  C_YLW="${C_BLD}$(tput setaf 3)"; C_RED="${C_BLD}$(tput setaf 1)"
  C_CYN="${C_BLD}$(tput setaf 6)"; C_GRY=$(tput setaf 7)
  C_WHT="${C_BLD}$(tput setaf 15)"
else
  C_RST=""; C_BLD=""; C_BLU=""; C_GRN=""; C_YLW=""; C_RED=""; C_CYN=""; C_GRY=""; C_WHT=""
fi

_ts()  { date '+%H:%M:%S'; }
ok()   { echo "${C_GRN}  ✓  $1${C_RST}"; }
warn() { echo "${C_YLW}  ⚠  $1${C_RST}"; }
fail() { echo "${C_RED}  ✗  $1${C_RST}"; }
note() { echo "${C_GRY}      $1${C_RST}"; }

# ── Flags ─────────────────────────────────────────────────────────────────────
START_AI=0; START_OS=0; START_GIT=0; START_PLANE=0; START_NOCO=0
START_K8S=0; START_MINIKUBE=0
NO_OBS=0; NO_REGISTRY=0; DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --ai)           START_AI=1 ;;
    --opensearch)   START_OS=1 ;;
    --git)          START_GIT=1 ;;
    --plane)        START_PLANE=1 ;;
    --nocobase)     START_NOCO=1 ;;
    --k8s)          START_K8S=1 ;;
    --minikube)     START_MINIKUBE=1 ;;
    --no-obs)       NO_OBS=1 ;;
    --no-registry)  NO_REGISTRY=1 ;;
    --dry-run)      DRY_RUN=1 ;;
    --help|-h)      grep '^#   ' "$0" | sed 's/^#   //'; exit 0 ;;
    *) warn "Unknown flag: $1" ;;
  esac
  shift
done

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo "${C_BLU}╔══════════════════════════════════════════════════════╗${C_RST}"
echo "${C_BLU}║         oss-learn  —  Start  (step 3 of 3)           ║${C_RST}"
echo "${C_BLU}╚══════════════════════════════════════════════════════╝${C_RST}"
echo ""
note "Workflow:  setup.sh  →  validate.sh  →  start.sh  ← you are here"
echo ""
echo "  ${C_WHT}Configuration${C_RST}"
echo "  ─────────────────────────────────────────────────────"
echo "  Obs         : $([ $NO_OBS      -eq 1 ] && echo 'skipped (--no-obs)'       || echo 'yes (Prometheus + Grafana + Blackbox)')"
echo "  Registry    : $([ $NO_REGISTRY -eq 1 ] && echo 'skipped (--no-registry)'  || echo 'yes (localhost:5000)')"
echo "  AI          : $([ $START_AI -eq 1 ] && echo 'yes (AI containers will start)' || echo 'no  (add --ai to start them)')"
echo "  OpenSearch  : $([ $START_OS   -eq 1 ] && echo 'yes (:9200 + :5601)'          || echo 'no  (add --opensearch to start)')"
echo "  Dry-run     : $([ $DRY_RUN    -eq 1 ] && echo 'yes (no changes)'             || echo 'no')"
echo ""

# ── Step tracking ─────────────────────────────────────────────────────────────
STEP_NAMES=(); STEP_LABELS=(); STEP_RESULTS=(); STEP_DURATIONS=()
START_TIME=$(date +%s)

run_step() {
  local name="$1"; shift
  local label="$1"; shift
  local script="$1"; shift
  local flags=("$@")

  STEP_NAMES+=("$name")
  STEP_LABELS+=("$label")

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  ${C_GRY}[dry-run] would run: scripts/start/$script ${flags[*]:-}${C_RST}"
    STEP_RESULTS+=("SKIP")
    STEP_DURATIONS+=("0")
    return 0
  fi

  local step_start rc=0
  step_start=$(date +%s)
  bash "$SCRIPT_DIR/$script" "${flags[@]+"${flags[@]}"}" || rc=$?
  local elapsed=$(( $(date +%s) - step_start ))
  STEP_DURATIONS+=("$elapsed")

  if [ $rc -eq 0 ]; then
    STEP_RESULTS+=("PASS")
  else
    STEP_RESULTS+=("FAIL")
  fi
}

skip_step() {
  STEP_NAMES+=("$1"); STEP_LABELS+=("$2"); STEP_RESULTS+=("SKIP"); STEP_DURATIONS+=("0")
}

# =============================================================================
# STEP 1 — Docker daemon
# =============================================================================
run_step "docker" "Docker daemon up" "docker.sh"

# =============================================================================
# STEP 2 — Registry
# =============================================================================
if [ $NO_REGISTRY -eq 0 ]; then
  run_step "registry" "Local Docker Registry" "registry.sh"
else
  skip_step "registry" "Local Docker Registry"
fi

# =============================================================================
# STEP 3 — Observability
# =============================================================================
if [ $NO_OBS -eq 0 ]; then
  run_step "observability" "Observability Stack" "observability.sh"
else
  skip_step "observability" "Observability Stack"
fi

# =============================================================================
# STEP 4 — Database
# =============================================================================
run_step "database" "Database (PostgreSQL)" "database.sh"

# =============================================================================
# STEP 5 — AI (optional)
# =============================================================================
if [ $START_AI -eq 1 ]; then
  run_step "ai" "AI Inference Containers" "ai.sh" "--ai"
else
  skip_step "ai" "AI Inference Containers"
fi

# =============================================================================
# STEP 6 — OpenSearch (optional)
# =============================================================================
if [ $START_OS -eq 1 ]; then
  run_step "opensearch" "OpenSearch + Dashboards" "opensearch.sh" "--opensearch"
else
  skip_step "opensearch" "OpenSearch + Dashboards"
fi

# =============================================================================
# STEP 7 — Gitea (optional)
# =============================================================================
if [ $START_GIT -eq 1 ]; then
  if [ -f "$REPO_ROOT/infra/git/docker-compose.yml" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "  ${C_GRY}[dry-run] would run: docker compose -f infra/git/docker-compose.yml up -d${C_RST}"
      skip_step "git" "Gitea (:3001)"
    else
      STEP_NAMES+=("git"); STEP_LABELS+=("Gitea (:3001)")
      _start=$(date +%s); _rc=0
      docker compose -f "$REPO_ROOT/infra/git/docker-compose.yml" up -d || _rc=$?
      STEP_DURATIONS+=("$(( $(date +%s) - _start ))")
      [ $_rc -eq 0 ] && STEP_RESULTS+=("PASS") || STEP_RESULTS+=("FAIL")
    fi
  else
    skip_step "git" "Gitea (:3001)"
  fi
else
  skip_step "git" "Gitea (:3001)"
fi

# =============================================================================
# STEP 8 — Plane (optional)
# =============================================================================
if [ $START_PLANE -eq 1 ]; then
  if [ -f "$REPO_ROOT/infra/plane/docker-compose.yml" ]; then
    STEP_NAMES+=("plane"); STEP_LABELS+=("Plane (:4000)")
    _start=$(date +%s); _rc=0
    [ "$DRY_RUN" -eq 1 ] || docker compose -f "$REPO_ROOT/infra/plane/docker-compose.yml" up -d || _rc=$?
    STEP_DURATIONS+=("$(( $(date +%s) - _start ))")
    [ $_rc -eq 0 ] && STEP_RESULTS+=("PASS") || STEP_RESULTS+=("FAIL")
  else
    skip_step "plane" "Plane (:4000)"
  fi
else
  skip_step "plane" "Plane (:4000)"
fi

# =============================================================================
# STEP 9 — NocoBase (optional)
# =============================================================================
if [ $START_NOCO -eq 1 ]; then
  if [ -f "$REPO_ROOT/infra/nocobase/docker-compose.yml" ]; then
    STEP_NAMES+=("nocobase"); STEP_LABELS+=("NocoBase (:13000)")
    _start=$(date +%s); _rc=0
    [ "$DRY_RUN" -eq 1 ] || docker compose -f "$REPO_ROOT/infra/nocobase/docker-compose.yml" up -d || _rc=$?
    STEP_DURATIONS+=("$(( $(date +%s) - _start ))")
    [ $_rc -eq 0 ] && STEP_RESULTS+=("PASS") || STEP_RESULTS+=("FAIL")
  else
    skip_step "nocobase" "NocoBase (:13000)"
  fi
else
  skip_step "nocobase" "NocoBase (:13000)"
fi

# =============================================================================
# STEP 10 — k3s (optional)
# =============================================================================
if [ $START_K8S -eq 1 ]; then
  run_step "k8s" "k3s cluster" "k8s.sh"
else
  skip_step "k8s" "k3s cluster"
fi

# =============================================================================
# STEP 11 — minikube (optional)
# =============================================================================
if [ $START_MINIKUBE -eq 1 ]; then
  run_step "minikube" "minikube cluster" "minikube.sh"
else
  skip_step "minikube" "minikube cluster"
fi

# =============================================================================
# STEP 12 — Smoke tests
# =============================================================================
run_step "smoke" "Smoke health checks" "smoke.sh"

# =============================================================================
# SUMMARY
# =============================================================================
TOTAL_DURATION=$(( $(date +%s) - START_TIME ))

echo ""
echo "${C_BLU}══════════════════════════════════════════════════════════════${C_RST}"
echo "${C_BLU}  oss-learn Start — Summary  (${TOTAL_DURATION}s total)${C_RST}"
echo "${C_BLU}══════════════════════════════════════════════════════════════${C_RST}"
echo ""
echo "  ${C_WHT}Step Results${C_RST}"
echo "  ─────────────────────────────────────────────"

PASS_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0
FAILED_NAMES=()

for ((i=0; i<${#STEP_NAMES[@]}; i++)); do
  local_name="${STEP_NAMES[$i]}"
  local_label="${STEP_LABELS[$i]}"
  local_result="${STEP_RESULTS[$i]}"
  local_dur="${STEP_DURATIONS[$i]}"
  local_num=$((i + 1))

  case "$local_result" in
    PASS)
      printf "  ${C_GRN}  %d. ✓  %-30s  PASS  %3ds${C_RST}\n" "$local_num" "$local_label" "$local_dur"
      ((PASS_COUNT++)) || true
      ;;
    FAIL)
      printf "  ${C_RED}  %d. ✗  %-30s  FAIL  %3ds${C_RST}\n" "$local_num" "$local_label" "$local_dur"
      ((FAIL_COUNT++)) || true
      FAILED_NAMES+=("$local_name")
      ;;
    SKIP)
      printf "  ${C_GRY}  %d. ↷  %-30s  SKIP${C_RST}\n" "$local_num" "$local_label"
      ((SKIP_COUNT++)) || true
      ;;
  esac
done

echo ""
echo "  ${C_WHT}Totals${C_RST}"
echo "  ─────────────────────────────────────────────"
echo "  Passed  : $PASS_COUNT"
echo "  Failed  : $FAIL_COUNT"
echo "  Skipped : $SKIP_COUNT"
echo "  Duration: ${TOTAL_DURATION}s"

if [ $FAIL_COUNT -eq 0 ]; then
  echo ""
  echo "  ${C_GRN}━━━ Stack started successfully ━━━${C_RST}"
  echo ""
  echo "  ${C_WHT}URLs${C_RST}"
  echo "  ─────────────────────────────────────────────"
  echo "  Grafana:    http://localhost:3000    (admin / oss-admin)"
  echo "  Prometheus: http://localhost:9090"
  echo "  Blackbox:   http://localhost:9115"
  [ $START_AI -eq 1 ]    && echo "  Ollama:        http://localhost:11434"
  [ $START_OS -eq 1 ]    && echo "  OpenSearch:    http://localhost:9200"
  [ $START_OS -eq 1 ]    && echo "  OS Dashboards: http://localhost:5601"
  [ $START_GIT -eq 1 ]   && echo "  Gitea:         http://localhost:3001"
  [ $START_PLANE -eq 1 ] && echo "  Plane:         http://localhost:4000"
  [ $START_NOCO -eq 1 ]  && echo "  NocoBase:      http://localhost:13000"
  [ $START_K8S -eq 1 ]   && echo "  k3s:           kubectl get nodes"
  [ $START_MINIKUBE -eq 1 ] && echo "  minikube:      kubectl get nodes (context=oss-learn)"
  echo ""
  echo "  ${C_WHT}Run tests with dummy data${C_RST}"
  echo "    pytest tests/ -v"
  echo ""
else
  echo ""
  echo "  ${C_RED}  ✗  ${#FAILED_NAMES[@]} step(s) failed: ${FAILED_NAMES[*]}${C_RST}"
  echo "  Check: docker ps  |  docker logs <container>"
  exit 1
fi
