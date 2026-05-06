#!/bin/bash
# =============================================================================
# db.sh — Suite: PostgreSQL + pgvector + Apache AGE validation
#
# PURPOSE:
#   Verifies that PostgreSQL is running with all required extensions
#   (pgvector, Apache AGE, etc.) and that PgBouncer connection pooling works.
#   Uses pytest to run the self-test suites.
#
# WHAT IT CHECKS:
#   - tests/db/test_postgres.py:
#     * PostgreSQL connectivity on port 5432
#     * pgvector extension loaded
#     * Apache AGE extension loaded
#     * Required schemas exist
#     * Basic CRUD operations work
#   - tests/db/test_pgvector.py:
#     * PgBouncer pool connectivity
#     * Connection reuse works
#     * Pool stats available
#
# INTERFACE:
#   Accepts: --dry-run
#   Returns: exit 0 = pass, exit 1 = fail, exit 2 = skip
#   Runs pytest with short traceback output
#
# USAGE:
#   bash scripts/validate/db.sh
#   bash scripts/validate/db.sh --dry-run
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
skip() { echo "${C_GRY}  ↷  $1 — skipped${C_RST}"; }
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

# ── Tools ────────────────────────────────────────────────────────────────────
PYTEST="${REPO_ROOT}/venv/bin/pytest"
[ -f "$PYTEST" ] || PYTEST="pytest"

# ── Suite banner ─────────────────────────────────────────────────────────────
hdr "db — PostgreSQL + PgBouncer"

TEST_FILES=(
  "${REPO_ROOT}/tests/db/test_postgres.py"
  "${REPO_ROOT}/tests/db/test_pgvector.py"
)

if [ "$DRY_RUN" -eq 1 ]; then
  echo "${C_GRY}  [dry-run] pytest ${TEST_FILES[*]}${C_RST}"
  ok "db: dry-run complete"
  exit 0
fi

# Verify test files exist
valid_paths=()
for p in "${TEST_FILES[@]}"; do
  if [ -e "$p" ]; then
    valid_paths+=("$p")
  else
    warn "path not found: $p"
  fi
done

if [ "${#valid_paths[@]}" -eq 0 ]; then
  skip "db — no test files found"
  note "Expected: ${TEST_FILES[*]}"
  exit 2
fi

# ── Run tests ────────────────────────────────────────────────────────────────
rc=0
"$PYTEST" "${valid_paths[@]}" -q --tb=short --no-header 2>&1 || rc=$?

echo ""
if [ $rc -eq 0 ]; then
  ok "db: all tests passed"
  exit 0
else
  fail "db: some tests failed"
  note "Run with verbose output:  pytest tests/db/ -v"
  note "Reinstall:  bash setup.sh --step postgres --force"
  exit 1
fi
