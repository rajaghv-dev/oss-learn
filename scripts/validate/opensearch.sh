#!/bin/bash
# =============================================================================
# opensearch.sh — Suite: OpenSearch cluster and Dashboards health
#
# WHAT IT CHECKS:
#   1. oss-opensearch container running
#   2. oss-opensearch-dashboards container running
#   3. Cluster health API (green or yellow)
#   4. Cluster info (_cluster/health) — node count, index count
#   5. OpenSearch Dashboards /api/status
#
# INTERFACE:
#   Accepts: --dry-run, --quick
#   Returns: exit 0 = pass, exit 1 = fail, exit 2 = skip (Docker absent)
# =============================================================================

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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

DRY_RUN=0
QUICK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --quick)   QUICK=1 ;;
    *) ;;
  esac
  shift
done

hdr "opensearch — OpenSearch cluster and Dashboards health"

if ! command -v docker &>/dev/null; then
  warn "Docker not found — skipping opensearch suite"
  exit 2
fi

if [ "$DRY_RUN" -eq 1 ]; then
  note "[dry-run] would check oss-opensearch containers + http://localhost:9200"
  exit 0
fi

OS_URL="http://localhost:9200"
DASH_URL="http://localhost:5601"
PASS=0; FAIL=0

_check_container() {
  local name="$1"
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
    ok "Container ${name} running"
    ((PASS++)) || true
  else
    fail "Container ${name} not running"
    note "  Start: bash scripts/setup/opensearch.sh"
    ((FAIL++)) || true
  fi
}

_check_container "oss-opensearch"
_check_container "oss-opensearch-dashboards"

# Cluster health
if curl -sf --max-time 5 "${OS_URL}/_cluster/health" >/dev/null 2>&1; then
  raw=$(curl -sf --max-time 5 "${OS_URL}/_cluster/health" 2>/dev/null || echo "{}")
  status=$(echo "$raw" | grep -o '"status":"[^"]*"' | sed 's/"status":"//;s/"//' | head -1)
  nodes=$(echo  "$raw" | grep -o '"number_of_nodes":[0-9]*' | grep -o '[0-9]*' | head -1)
  case "$status" in
    green)  ok  "Cluster health: green  (nodes=${nodes:-?})" ; ((PASS++)) || true ;;
    yellow) warn "Cluster health: yellow (nodes=${nodes:-?}) — replicas unassigned (OK for single-node)" ; ((PASS++)) || true ;;
    red)    fail "Cluster health: red    (nodes=${nodes:-?})" ; ((FAIL++)) || true ;;
    *)      fail "Cluster health: unknown (${status:-no response})" ; ((FAIL++)) || true ;;
  esac
else
  fail "OpenSearch API not reachable at ${OS_URL}"
  note "  Check: docker logs oss-opensearch"
  note "  Hint:  sudo sysctl -w vm.max_map_count=262144"
  ((FAIL++)) || true
fi

# Index count (quick-skip in --quick mode)
if [ "$QUICK" -eq 0 ]; then
  if curl -sf --max-time 5 "${OS_URL}/_cat/indices?h=index" >/dev/null 2>&1; then
    idx_count=$(curl -sf --max-time 5 "${OS_URL}/_cat/indices?h=index" 2>/dev/null | grep -c . || echo 0)
    ok "Index catalogue reachable (${idx_count} indices)"
    ((PASS++)) || true
  else
    warn "Index catalogue not reachable (non-critical)"
  fi
fi

# Dashboards
if curl -sf --max-time 10 "${DASH_URL}/api/status" >/dev/null 2>&1; then
  ok "OpenSearch Dashboards: ${DASH_URL}"
  ((PASS++)) || true
else
  fail "OpenSearch Dashboards not reachable: ${DASH_URL}"
  note "  Check: docker logs oss-opensearch-dashboards"
  ((FAIL++)) || true
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  ok "opensearch suite passed ($PASS checks)"
  exit 0
else
  fail "opensearch suite: $FAIL check(s) failed, $PASS passed"
  note "  Restart: bash scripts/setup/opensearch.sh --force"
  note "  Prereq:  sudo sysctl -w vm.max_map_count=262144"
  exit 1
fi
