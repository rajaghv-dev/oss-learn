#!/bin/bash
# =============================================================================
# infra.sh — Suite 1: Observability stack health checks
#
# PURPOSE:
#   Verifies that the oss-learn observability stack is up and healthy.
#   These are the monitoring components that every other suite's results
#   feed into.
#
# WHAT IT CHECKS:
#   1. Prometheus   — http://localhost:9090/-/healthy   (metrics collection)
#   2. Grafana      — http://localhost:3000/api/health  (dashboards)
#   3. Blackbox     — http://localhost:9115/health      (external probe exporter)
#   4. State-Exporter — http://localhost:9901/metrics   (oss-learn state → Prometheus)
#
# INTERFACE:
#   Accepts: --dry-run
#   Returns: exit 0 = pass (3+ of 4 up), exit 1 = fail, exit 2 = skip
#   Prints colour-coded per-check results
#
# USAGE:
#   bash scripts/validate/infra.sh
#   bash scripts/validate/infra.sh --dry-run
# =============================================================================

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ── Colours ───────────────────────────────────────────────────────────────────
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

# ── Flags ─────────────────────────────────────────────────────────────────────
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --quick)   ;; # accepted but no effect on this suite
    *) ;;
  esac
  shift
done

# ── Suite banner ─────────────────────────────────────────────────────────────
hdr "infra — Observability stack health"

infra_ok=0

_check_url() {
  local label="$1" url="$2"
  if curl -sf "$url" >/dev/null 2>&1; then
    ok "$label → $url"
    ((infra_ok++)) || true
  else
    warn "$label not reachable at $url"
    note "Start with: docker compose -f infra/observability/docker-compose.yml up -d"
  fi
}

if [ "$DRY_RUN" -eq 0 ]; then
  _check_url "Prometheus"      "http://localhost:9090/-/healthy"
  _check_url "Grafana"         "http://localhost:3000/api/health"
  _check_url "Blackbox"        "http://localhost:9115/health"
  _check_url "State-exporter"  "http://localhost:9901/metrics"
else
  echo "${C_GRY}  [dry-run] check 4 URLs: Prometheus :9090, Grafana :3000, Blackbox :9115, State-exporter :9901${C_RST}"
  infra_ok=4
fi

# ── Result ───────────────────────────────────────────────────────────────────
echo ""
if [ $infra_ok -ge 3 ]; then
  ok "infra: $infra_ok/4 components up"
  exit 0
else
  fail "infra: only $infra_ok/4 components reachable"
  note "At least 3 of 4 components must be up to pass."
  note "Run: docker compose -f infra/observability/docker-compose.yml up -d"
  exit 1
fi
