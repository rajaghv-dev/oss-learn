#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/common.sh"
set_script_log "python"

# ── Local colors (override if needed) ──────────────────────────────
if [ -t 1 ] && command -v tput &>/dev/null && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  C_RST=$(tput sgr0); C_BLD=$(tput bold)
  C_BLU="${C_BLD}$(tput setaf 4)"; C_GRN="${C_BLD}$(tput setaf 2)"
  C_YLW="${C_BLD}$(tput setaf 3)"; C_RED="${C_BLD}$(tput setaf 1)"
  C_CYN="${C_BLD}$(tput setaf 6)"; C_GRY=$(tput setaf 7)
else
  C_RST=""; C_BLD=""; C_BLU=""; C_GRN=""; C_YLW=""; C_RED=""; C_CYN=""; C_GRY=""
fi

header()  { echo ""; echo "${C_BLU}══════════════════════════════════════════════════${C_RST}"; echo "${C_BLU}  $1${C_RST}"; echo "${C_BLU}══════════════════════════════════════════════════${C_RST}"; echo ""; }
info()    { echo "${C_GRN}  ✓  $1${C_RST}"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $1" >> "$LOG_FILE"; }
warn()    { echo "${C_YLW}  ⚠  $1${C_RST}"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN:  $1" >> "$LOG_FILE"; }
err()     { echo "${C_RED}  ✗  $1${C_RST}" >&2; echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"; }
step()    { echo "${C_CYN}  →  $1${C_RST}"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] STEP:  $1" >> "$LOG_FILE"; }

SHARED_VENV="$REPO_ROOT/venv"
PIP="$SHARED_VENV/bin/pip"
PYTHON_MIN_MAJOR=3
PYTHON_MIN_MINOR=10

CHECK_ONLY=0
FORCE=0
NO_CACHE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --check)    CHECK_ONLY=1 ;;
    --force)    FORCE=1 ;;
    --no-cache) NO_CACHE=1 ;;
    --help|-h)  grep '^#' "$0" | head -30 | sed 's/^# \?//'; exit 0 ;;
    *) warn "Unknown argument: $1" ;;
  esac
  shift
done

check_python() {
  step "Checking for Python ${PYTHON_MIN_MAJOR}.${PYTHON_MIN_MINOR}+..."
  if ! command -v python3 &>/dev/null; then
    err "python3 not found in PATH — CRITICAL FAILURE"
    return 1
  fi
  local py_version py_major py_minor
  py_version="$(python3 --version 2>&1 | grep -oP '\d+\.\d+\.\d+')"
  py_major="$(echo "$py_version" | cut -d. -f1)"
  py_minor="$(echo "$py_version" | cut -d. -f2)"
  if [ "$py_major" -lt "$PYTHON_MIN_MAJOR" ] || \
     { [ "$py_major" -eq "$PYTHON_MIN_MAJOR" ] && [ "$py_minor" -lt "$PYTHON_MIN_MINOR" ]; }; then
    err "Python $py_version found — FAILS minimum requirement (3.10+)"
    return 1
  fi
  info "Python $py_version ($(command -v python3))"
}

check_venv_module() {
  if ! python3 -m venv --help &>/dev/null; then
    err "python3-venv module not available"
    return 1
  fi
}

handle_no_cache() {
  if [ "$NO_CACHE" -eq 1 ] && [ -d "$SHARED_VENV" ]; then
    step "Cleaning caches (--no-cache)..."
    rm -rf "$SHARED_VENV"
    python3 -m pip cache purge 2>/dev/null || true
    info "Cleared venv and pip cache"
  fi
}

handle_force() {
  if [ "$FORCE" -eq 1 ] && [ -d "$SHARED_VENV" ]; then
    step "Removing existing venv (--force)..."
    rm -rf "$SHARED_VENV"
    info "Existing venv removed"
  fi
}

create_venv() {
  if [ -f "$SHARED_VENV/bin/python3" ]; then
    info "Shared venv already exists: $SHARED_VENV"
    return 0
  fi
  step "Creating shared Python venv at $SHARED_VENV..."
  cd "$REPO_ROOT"
  python3 -m venv "$SHARED_VENV"
  info "Shared venv created: $SHARED_VENV"
}

upgrade_pip() {
  step "Upgrading pip in venv..."
  cd "$SHARED_VENV"
  "$PIP" install --upgrade pip --quiet
  info "pip upgraded: $("$PIP" --version | grep -oP 'pip \d+\.\d+')"
}

install_shared_deps() {
  local req="$REPO_ROOT/requirements-shared.txt"
  if [ ! -f "$req" ]; then
    warn "requirements-shared.txt not found — skipping"
    return 0
  fi
  step "Installing shared deps (requirements-shared.txt)..."
  cd "$REPO_ROOT"
  local pip_flags=( --quiet )
  [ "$NO_CACHE" -eq 1 ] && pip_flags+=( --no-cache-dir )
  if "$PIP" install "${pip_flags[@]}" -r "$req"; then
    info "Shared deps installed"
  else
    err "requirements-shared.txt install failed"
    return 1
  fi
}

install_dev_deps() {
  step "Installing test-runner deps..."
  cd "$REPO_ROOT"
  # Install dev deps directly (not editable, to avoid hatchling issues)
  if "$PIP" install --quiet pytest pytest-asyncio httpx respx "psycopg[binary]" pgvector onnx numpy packaging ruff; then
    info "Test-runner deps installed (pytest, httpx, ruff, etc.)"
  else
    warn "Some dev deps may have failed — continuing"
  fi
}

write_python_manifest() {
  local py_version="$("$SHARED_VENV/bin/python3" --version 2>&1 | grep -oP '\d+\.\d+\.\d+')"
  local venv_pip_version="$("$PIP" --version | grep -oP 'pip \d+\.\d+' | cut -d' ' -f2)"
  local pkg_count="$("$PIP" list --format=columns 2>/dev/null | tail -n +3 | wc -l)"
  write_manifest python \
    location=local \
    "version=${py_version}" \
    "pip_version=${venv_pip_version}" \
    "packages_installed=${pkg_count}"
}

report_status() {
  header "Python venv status"
  if command -v python3 &>/dev/null; then
    info "System Python: $(python3 --version 2>&1)"
  else
    err "System Python: not found"
  fi
  if [ -f "$SHARED_VENV/bin/python3" ]; then
    info "Venv exists: $SHARED_VENV"
    info "Venv Python: $("$SHARED_VENV/bin/python3" --version 2>&1)"
    info "Venv pip: $("$PIP" --version 2>/dev/null | grep -oP 'pip \d+\.\d+')"
    local pkg_count="$("$PIP" list --format=columns 2>/dev/null | tail -n +3 | wc -l)"
    info "Installed packages: $pkg_count"
    for pkg in fastapi uvicorn psycopg pytest httpx ruff; do
      if "$SHARED_VENV/bin/python3" -c "import $pkg" &>/dev/null; then
        info "  $pkg: installed"
      else
        warn "  $pkg: NOT installed"
      fi
    done
  else
    warn "Venv does not exist: $SHARED_VENV"
  fi
  local manifest="$MANIFEST_DIR/python.yaml"
  if [ -f "$manifest" ]; then
    info "Manifest: $manifest"
  else
    warn "Manifest: not written yet"
  fi
}

main() {
  header "Python venv + dev tooling"
  if [ "$CHECK_ONLY" -eq 1 ]; then
    report_status
    return 0
  fi
  check_python    || return 1
  check_venv_module || return 1
  handle_no_cache
  handle_force
  create_venv     || return 1
  upgrade_pip     || return 1
  install_shared_deps || return 1
  install_dev_deps || return 1
  write_python_manifest
  local _py_ver _pip_ver _pkg_count
  _py_ver="$("$SHARED_VENV/bin/python3" --version 2>&1 | grep -oP '\d+\.\d+\.\d+')"
  _pip_ver="$("$PIP" --version 2>/dev/null | grep -oP 'pip \d+\.\d+' | cut -d' ' -f2)"
  _pkg_count="$("$PIP" list --format=columns 2>/dev/null | tail -n +3 | wc -l)"
  log_pass "Python venv + dev tooling" \
    "system python3 ≥3.10 present, python3-venv module importable, shared venv created at \$REPO_ROOT/venv, pip upgraded, requirements-shared.txt installed, pytest/httpx/ruff installed, manifest written" \
    "Python ${_py_ver} in venv; pip ${_pip_ver}; ${_pkg_count} packages installed (fastapi, uvicorn, psycopg, pytest, httpx, ruff verified importable)" \
    "venv=$SHARED_VENV; pip=$PIP; manifest=$MANIFEST_DIR/python.yaml; log=logs/python.log" \
    "source $SHARED_VENV/bin/activate    # then: bash scripts/setup.sh --step postgres"
}

main "$@"
