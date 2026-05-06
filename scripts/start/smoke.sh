#!/bin/bash
# =============================================================================
# smoke.sh — Step 7/7: Validate cluster health via validate_cluster.sh
#
# PURPOSE:
#   Runs validate_cluster.sh against the already-running oss-learn stack to confirm
#   all services pass their /healthz, /metrics, and ANPR file-drop checks.
#   Services must already be up (started by steps 1–4).
#
# INTERFACE:
#   Accepts: --dry-run
#   Returns: exit 0 = all checks passed, exit 1 = one or more failures
#
# STANDALONE USAGE:
#   bash scripts/start/smoke.sh            # run validate_cluster.sh
#   bash scripts/start/smoke.sh --dry-run  # print what would run
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Colours ───────────────────────────────────────────────────────────────────
if [ -t 1 ] && command -v tput &>/dev/null && [ "$(tput colors 2>/dev/null||echo 0)" -ge 8 ]; then
  C_RST=$(tput sgr0); C_BLD=$(tput bold)
  C_GRN="${C_BLD}$(tput setaf 2)"; C_YLW="${C_BLD}$(tput setaf 3)"
  C_RED="${C_BLD}$(tput setaf 1)"; C_CYN="${C_BLD}$(tput setaf 6)"
  C_BLU="${C_BLD}$(tput setaf 4)"
else
  C_RST=""; C_BLD=""; C_GRN=""; C_YLW=""; C_RED=""; C_CYN=""; C_BLU=""
fi

hdr()  { echo ""; echo "${C_BLU}════  $1${C_RST}"; }
step() { echo "${C_CYN}  →  $1${C_RST}"; }
ok()   { echo "${C_GRN}  ✓  $1${C_RST}"; }
warn() { echo "${C_YLW}  ⚠  $1${C_RST}"; }
fail() { echo "${C_RED}  ✗  $1${C_RST}"; }

# ── Flags ─────────────────────────────────────────────────────────────────────
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    *) warn "Unknown flag: $1" ;;
  esac
  shift
done

# ── Main ──────────────────────────────────────────────────────────────────────
hdr "Smoke — validate cluster health"

if ! command -v docker &>/dev/null; then
  warn "Docker not found — skipping smoke test"
  exit 0
fi

# Wait up to 60s for any still-starting containers to settle
step "Waiting for containers to settle (up to 60s)..."
elapsed=0
while [ "$elapsed" -lt 60 ]; do
  starting=$(docker compose -f "$REPO_ROOT/docker-compose.yml" ps 2>/dev/null \
    | grep -cE "(starting|unhealthy)" || true)
  [ "$starting" -eq 0 ] && break
  printf "  . (%d containers still starting)\n" "$starting"
  sleep 2
  (( elapsed += 2 )) || true
done

docker compose -f "$REPO_ROOT/docker-compose.yml" ps
echo ""

VALIDATE="$REPO_ROOT/scripts/validate_cluster.sh"
if [ ! -f "$VALIDATE" ]; then
  warn "scripts/validate_cluster.sh not found — skipping"
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  step "DRY-RUN: would run $VALIDATE"
  exit 0
fi

step "Running validate_cluster.sh..."
if bash "$VALIDATE"; then
  ok "Smoke test passed"
  exit 0
else
  fail "validate_cluster.sh reported failures — check above"
  exit 1
fi
