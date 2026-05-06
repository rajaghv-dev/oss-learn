#!/bin/bash
# =============================================================================
# nocobase.sh — Suite: NocoBase self-hosted low-code platform health
#
# WHAT IT CHECKS:
#   1. oss-nocobase container running
#   2. oss-nocobase-db container running
#   3. NocoBase API reachable at http://localhost:13000/api/app:getInfo
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
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --quick)   ;; # no effect
    *) ;;
  esac
  shift
done

hdr "nocobase — NocoBase self-hosted low-code platform"

if ! command -v docker &>/dev/null; then
  warn "Docker not found — skipping nocobase suite"
  exit 2
fi

if [ "$DRY_RUN" -eq 1 ]; then
  note "[dry-run] would check oss-nocobase containers + http://localhost:13000"
  exit 0
fi

PASS=0; FAIL=0
NOCOBASE_URL="http://localhost:13000"

_check_container() {
  local name="$1"
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
    ok "Container ${name} running"
    ((PASS++)) || true
  else
    fail "Container ${name} not running"
    note "  Start: bash scripts/setup/nocobase.sh"
    ((FAIL++)) || true
  fi
}

_check_url() {
  local label="$1" url="$2"
  if curl -sf --max-time 10 "$url" >/dev/null 2>&1; then
    ok "${label}: ${url}"
    ((PASS++)) || true
  else
    fail "${label}: ${url}"
    note "  Check: docker logs oss-nocobase"
    ((FAIL++)) || true
  fi
}

_check_container "oss-nocobase"
_check_container "oss-nocobase-db"
_check_url "NocoBase API" "${NOCOBASE_URL}/api/app:getInfo"

echo ""
if [ "$FAIL" -eq 0 ]; then
  ok "nocobase suite passed ($PASS checks)"
  exit 0
else
  fail "nocobase suite: $FAIL check(s) failed, $PASS passed"
  note "  Restart: bash scripts/setup/nocobase.sh --force"
  exit 1
fi
