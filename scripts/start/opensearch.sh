#!/bin/bash
# =============================================================================
# opensearch.sh — Step 6/6: Start OpenSearch + Dashboards (optional)
#
# PURPOSE:
#   Starts OpenSearch 2.x and OpenSearch Dashboards via docker compose.
#   This step is optional and only runs when --opensearch is passed to start.sh.
#   Without it, a skip message is printed and the script exits 0.
#
# WHAT IT DOES:
#   1. Checks vm.max_map_count ≥ 262144 (warns if not set)
#   2. Starts oss-opensearch and oss-opensearch-dashboards containers
#   3. Waits for the cluster health endpoint (up to 90 s)
#   4. Waits for Dashboards /api/status (up to 60 s)
#   5. Reports UP/DOWN per component with URLs
#
# INTERFACE:
#   Accepts: --opensearch (required to actually start)
#            --dry-run
#   Returns: exit 0 = success or skipped, exit 1 = failed
#
# STANDALONE USAGE:
#   bash scripts/start/opensearch.sh --opensearch
#   bash scripts/start/opensearch.sh --opensearch --dry-run
#   bash scripts/start/opensearch.sh               # prints skip message
# =============================================================================

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

if [ -t 1 ] && command -v tput &>/dev/null && [ "$(tput colors 2>/dev/null||echo 0)" -ge 8 ]; then
  C_RED=$(tput setaf 1)$(tput bold); C_GRN=$(tput setaf 2)$(tput bold)
  C_YLW=$(tput setaf 3)$(tput bold); C_CYN=$(tput setaf 6)$(tput bold)
  C_BLU=$(tput setaf 4)$(tput bold); C_GRY=$(tput setaf 7); C_RST=$(tput sgr0)
else
  C_RED=""; C_GRN=""; C_YLW=""; C_CYN=""; C_BLU=""; C_GRY=""; C_RST=""
fi

_ts()  { date '+%H:%M:%S'; }
hdr()  { echo ""; echo "${C_BLU}════  [$(_ts)]  $1${C_RST}"; }
step() { echo "${C_CYN}  →  $1${C_RST}"; }
ok()   { echo "${C_GRN}  ✓  $1${C_RST}"; }
warn() { echo "${C_YLW}  ⚠  $1${C_RST}"; }
fail() { echo "${C_RED}  ✗  $1${C_RST}"; }
note() { echo "${C_GRY}      $1${C_RST}"; }

_run() {
  [ "${DRY_RUN:-0}" -eq 1 ] && { echo "${C_GRY}  [dry-run] $*${C_RST}"; return 0; }
  "$@"
}

_wait_url() {
  local url="$1" max="${2:-60}" i=0
  while [ $i -lt $max ]; do
    curl -sf "$url" >/dev/null 2>&1 && return 0
    printf "."; sleep 3; ((i+=3)) || true
  done
  echo ""; return 1
}

# ── Flags ─────────────────────────────────────────────────────────────────────
START_OS=0
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --opensearch) START_OS=1 ;;
    --dry-run)    DRY_RUN=1 ;;
    --help|-h)    grep '^#' "${BASH_SOURCE[0]}" | head -20 | sed 's/^# \?//'; exit 0 ;;
    *) warn "Unknown flag: $1" ;;
  esac
  shift
done

OS_COMPOSE="$REPO_ROOT/setup/opensearch/docker-compose.yml"
OS_URL="http://localhost:9200"
DASH_URL="http://localhost:5601"

# ── Step 6: OpenSearch ────────────────────────────────────────────────────────
hdr "6/6  OpenSearch (API :9200 · Dashboards :5601)"

if [ "$START_OS" -eq 0 ]; then
  note "Skipped — add --opensearch to start.sh to enable"
  note "  bash scripts/start.sh --opensearch"
  exit 0
fi

if ! command -v docker &>/dev/null; then
  fail "Docker not found — cannot start OpenSearch"
  exit 1
fi

if [ ! -f "$OS_COMPOSE" ]; then
  fail "setup/opensearch/docker-compose.yml not found"
  note "Run setup first:  bash scripts/setup.sh --step opensearch"
  exit 1
fi

# Check vm.max_map_count
current_map=$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo 0)
if [ "$current_map" -lt 262144 ]; then
  warn "vm.max_map_count=${current_map} (need ≥ 262144) — attempting to set..."
  if _run sudo sysctl -w vm.max_map_count=262144 2>/dev/null; then
    ok "vm.max_map_count set to 262144"
  else
    warn "Could not set vm.max_map_count — OpenSearch may fail"
    warn "Fix: sudo sysctl -w vm.max_map_count=262144"
  fi
fi

step "Starting OpenSearch containers..."
_run docker compose -f "$OS_COMPOSE" up -d

# Wait for cluster health
step "Waiting for OpenSearch cluster health (up to 90 s)..."
printf "  "
OS_UP=0
if [ "$DRY_RUN" -eq 0 ]; then
  attempts=0
  while [ $attempts -lt 18 ]; do
    if curl -sf "${OS_URL}/_cluster/health" 2>/dev/null | grep -qE '"status":"(green|yellow)"'; then
      OS_UP=1; break
    fi
    printf "."; sleep 5; ((attempts++)) || true
  done
  echo ""
else
  OS_UP=1
fi

if [ "$OS_UP" -eq 1 ]; then
  health=$(curl -sf "${OS_URL}/_cluster/health" 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 || echo "?")
  ok "OpenSearch: ${OS_URL}  (${health})"
else
  fail "OpenSearch not ready after 90 s — check: docker logs oss-opensearch"
fi

# Wait for Dashboards
step "Waiting for OpenSearch Dashboards (up to 60 s)..."
printf "  "
DASH_UP=0
if [ "$DRY_RUN" -eq 0 ]; then
  if _wait_url "${DASH_URL}/api/status" 60; then
    DASH_UP=1
  fi
  echo ""
else
  DASH_UP=1
fi

if [ "$DASH_UP" -eq 1 ]; then
  ok "OpenSearch Dashboards: ${DASH_URL}"
else
  warn "Dashboards not ready yet — check: docker logs oss-opensearch-dashboards"
fi

# Exit status driven by the cluster (Dashboards is non-critical)
[ "$OS_UP" -eq 1 ] && exit 0 || exit 1
