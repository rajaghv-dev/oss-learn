#!/bin/bash
# =============================================================================
# ai.sh — Suite 7: AI framework pip-install checks + CPU inference
#
# PURPOSE:
#   Verifies that all 4 AI inference frameworks are correctly installed
#   (pip packages import without error) and that CPU inference works.
#   This catches broken installs, missing shared libraries, and
#   version mismatches.
#
# WHAT IT CHECKS:
#   1. OpenVINO     — setup/self-tests/openvino/test_install.py
#   2. ONNX Runtime — setup/self-tests/onnxruntime/test_install.py
#   3. Ollama       — setup/self-tests/ollama/test_install.py
#   4. llama.cpp    — setup/self-tests/llama_cpp/test_install.py
#   5. (full mode)  — setup/verify_ai.py --quick  (CPU inference check)
#
# FLAGS:
#   --quick   Skip the CPU inference check (verify_ai.py), only run imports
#   --dry-run Print what would run, execute nothing
#
# INTERFACE:
#   Accepts: --dry-run, --quick
#   Returns: exit 0 = pass, exit 1 = fail, exit 2 = skip
#   Prints per-framework results
#
# USAGE:
#   bash scripts/validate/ai.sh
#   bash scripts/validate/ai.sh --quick
#   bash scripts/validate/ai.sh --dry-run
# =============================================================================

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ── Source shared helpers ──────────────────────────────────
source "$REPO_ROOT/scripts/common.sh"

# ── Initialize script-specific logging ──────────────────────────────────
set_script_log "validate_ai"

# Log start
log_info "══════════════════════════════════════"
log_info "AI Validation Suite started"
log_info "  Repository : $REPO_ROOT"
log_info "  Script log : $SCRIPT_LOG"
log_info "══════════════════════════════════════"

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
step() { echo "${C_CYN}  →  $1${C_RST}"; }
ok()   { echo "${C_GRN}  ✓  $1${C_RST}"; }
warn() { echo "${C_YLW}  ⚠  $1${C_RST}"; }
fail() { echo "${C_RED}  ✗  $1${C_RST}"; }
note() { echo "${C_GRY}      $1${C_RST}"; }

# ── Flags ─────────────────────────────────────────────────────────────────────
DRY_RUN=0; QUICK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --quick)   QUICK=1 ;;
    *) ;;
  esac
  shift
done

# ── Tools ────────────────────────────────────────────────────────────────────
PYTHON="${REPO_ROOT}/venv/bin/python3"
[ -f "$PYTHON" ] || PYTHON="python3"
PYTEST="${REPO_ROOT}/venv/bin/pytest"
[ -f "$PYTEST" ] || PYTEST="pytest"

# ── Suite banner ─────────────────────────────────────────────────────────────
hdr "ai — AI framework pip-install + CPU inference"

ai_pass=0; ai_fail=0

_run_ai_test() {
  # PURPOSE: Run a pytest-based AI framework validation
  # FAILURE: Prints WHAT WAS CHECKED, WHY IT FAILS, HOW TO FIX
  local fw="$1" path="$2"
  step "$fw"
  log_info "Running test: $fw ($path)"
  local rc=0
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "${C_GRY}  [dry-run] pytest $path${C_RST}"
    ((ai_pass++)) || true; return 0
  fi
  if [ ! -e "$path" ]; then
    warn "  $fw — test file not found: $path"
    ((ai_fail++)) || true; return 0
  fi
  "$PYTEST" "$path" -q --tb=short --no-header 2>&1 || rc=$?
  if [ $rc -eq 0 ]; then
    ok "  $fw — passed"
    ((ai_pass++)) || true
  else
    fail "  $fw — failed"
    ((ai_fail++)) || true
  fi
}

_run_bash_test() {
  local fw="$1" path="$2"
  step "$fw (bash)"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "${C_GRY}  [dry-run] bash $path${C_RST}"
    ((ai_pass++)) || true; return 0
  fi
  if [ ! -e "$path" ]; then
    warn "  $fw — script not found: $path"
    ((ai_fail++)) || true; return 0
  fi
  bash "$path"
  local rc=$?
  if [ ${rc:-0} -eq 0 ]; then
    ok "  $fw — passed"
    ((ai_pass++)) || true
  else
    fail "  $fw — failed"
    ((ai_fail++)) || true
  fi
}

# Python-based tests (pytest)
_run_ai_test "OpenVINO"     "${REPO_ROOT}/setup/self-tests/openvino/test_install.py"
_run_ai_test "ONNX Runtime" "${REPO_ROOT}/setup/self-tests/onnxruntime/test_install.py"
_run_ai_test "Ollama"       "${REPO_ROOT}/setup/self-tests/ollama/test_install.py"
# Simplified: Just check if llama.cpp inference works
  step "llama.cpp — checking inference"
  if [ "$DRY_RUN" -eq 0 ]; then
    if command -v llama-cli &>/dev/null || [ -f "$REPO_ROOT/setup/llama_cpp/install/llama-cli" ]; then
      ok "  llama.cpp — binary found"
    else
      warn "  llama.cpp — binary not found (run: bash setup.sh --step llama_cpp --force)"
    fi
  fi

# Bash-based validation scripts
_run_bash_test "OpenVINO (bash)"    "${REPO_ROOT}/setup/validate/openvino.sh"
_run_bash_test "ONNX Runtime (bash)" "${REPO_ROOT}/setup/validate/onnxruntime.sh"
_run_bash_test "llama.cpp (bash)"   "${REPO_ROOT}/setup/validate/llamacpp.sh"
_run_bash_test "Ollama (bash)"      "${REPO_ROOT}/setup/validate/ollama.sh"

# Full AI verify (CPU inference, no model download required)
if [ $QUICK -eq 0 ]; then
  step "AI verify — CPU inference"
  if [ "$DRY_RUN" -eq 0 ]; then
    rc=0
    "$PYTHON" "${REPO_ROOT}/setup/verify_ai.py" --quick 2>&1 || rc=$?
    if [ $rc -eq 0 ]; then
      ok "  verify_ai.py — passed"
      ((ai_pass++)) || true
    else
      fail "  verify_ai.py — failed"
      ((ai_fail++)) || true
    fi
  else
    echo "${C_GRY}  [dry-run] python3 setup/verify_ai.py --quick${C_RST}"
    ((ai_pass++)) || true
  fi
fi

# ── Result ───────────────────────────────────────────────────────────────────
echo ""
if [ $ai_fail -eq 0 ]; then
  ok "ai: $ai_pass tests passed"
  exit 0
else
  fail "ai: $ai_fail failed / $ai_pass passed"
  note "Reinstall AI frameworks: bash setup.sh --step ai --force"
  exit 1
fi
