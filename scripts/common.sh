#!/bin/bash
# common.sh — Shared utilities for oss-learn setup scripts

# ── Colors ──────────────────────────────────────────────────────────
if [ -t 1 ] && command -v tput &>/dev/null && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  C_RST=$(tput sgr0); C_BLD=$(tput bold)
  C_BLU="${C_BLD}$(tput setaf 4)"; C_GRN="${C_BLD}$(tput setaf 2)"
  C_YLW="${C_BLD}$(tput setaf 3)"; C_RED="${C_BLD}$(tput setaf 1)"
  C_CYN="${C_BLD}$(tput setaf 6)"; C_GRY=$(tput setaf 7)
  C_WHT="${C_BLD}$(tput setaf 15)"
else
  C_RST=""; C_BLD=""; C_BLU=""; C_GRN=""; C_YLW=""; C_RED=""; C_CYN=""; C_GRY=""; C_WHT=""
fi

# ── Paths ────────────────────────────────────────────────────────────
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOG_DIR="$REPO_ROOT/logs"
STATE_DIR="${STATE_DIR:-$REPO_ROOT/setup/state}"
MANIFEST_DIR="$STATE_DIR/installs"
mkdir -p "$LOG_DIR" "$STATE_DIR" "$MANIFEST_DIR" 2>/dev/null || true
export STATE_DIR LOG_DIR MANIFEST_DIR REPO_ROOT
export LOG_FILE="$LOG_DIR/setup.log"

# ── Run ID for log correlation ────────────────────────────────────────
if [ -z "${OSS_RUN_ID:-}" ]; then
  export OSS_RUN_ID="$(date '+%Y%m%d-%H%M%S')-$$"
fi

set_script_log() {
  export SCRIPT_NAME="${1:-setup}"
  local stable="$LOG_DIR/${SCRIPT_NAME}.log"
  local timestamped="$LOG_DIR/${SCRIPT_NAME}__${OSS_RUN_ID}.log"
  export SCRIPT_LOG="$timestamped"
  export LOG_FILE="$SCRIPT_LOG"
  {
    echo "=== oss-learn component log ==="
    echo "  component : ${SCRIPT_NAME}"
    echo "  run_id    : ${OSS_RUN_ID}"
    echo "  started   : $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "  pid       : $$  | user: $(id -un)  | host: $(hostname)"
    echo "  cwd       : $(pwd)"
    echo "================================"
  } >> "$SCRIPT_LOG"
  ln -sfn "$(basename "$timestamped")" "$stable" 2>/dev/null || true
}

set_script_log "setup"

# ── Logging ──────────────────────────────────────────────────────────
log_info()  { echo "${C_GRN}[INFO]${C_RST}  $1" | tee -a "$SCRIPT_LOG"; }
log_warn()  { echo "${C_YLW}[WARN]${C_RST}  $1" | tee -a "$SCRIPT_LOG"; }
log_error() { echo "${C_RED}[ERROR]${C_RST} $1" | tee -a "$SCRIPT_LOG" >&2; }
log_step()  { echo "${C_CYN}[STEP]${C_RST}  $1" | tee -a "$SCRIPT_LOG"; }
log_skip()  { echo "${C_GRY}[SKIP]${C_RST}  $1" | tee -a "$SCRIPT_LOG"; }
log_header(){
  echo ""
  echo "${C_BLU}══════════════════════════════════════════════════${C_RST}"
  echo "${C_BLU}  $1${C_RST}"
  echo "${C_BLU}══════════════════════════════════════════════════${C_RST}"
  echo ""
}

log_pass() {
  local component="${1:-(unnamed)}"
  local checked="${2:-(no check evidence recorded)}"
  local why="${3:-(no pass reason recorded)}"
  local artifacts="${4:-(no artifacts recorded)}"
  local next="${5:-}"
  echo "${C_GRN}━━━ ✓ ${component} — PASSED ━━━${C_RST}" | tee -a "$SCRIPT_LOG"
  log_info "  → WHAT WAS CHECKED: $checked"
  log_info "  → WHY IT PASSED:    $why"
  log_info "  → ARTIFACTS:        $artifacts"
  [ -n "$next" ] && log_info "  → NEXT STEP:        $next"
}

log_fail() {
  local component="${1:-(unnamed)}"
  local checked="${2:-(no check evidence recorded)}"
  local why="${3:-(no failure reason recorded)}"
  local how="${4:-(no fix hint recorded)}"
  local next="${5:-}"
  echo "${C_RED}━━━ ✗ ${component} — FAILED ━━━${C_RST}" | tee -a "$SCRIPT_LOG" >&2
  log_error "  → WHAT WAS CHECKED: $checked"
  log_error "  → WHY IT FAILED:    $why"
  log_error "  → HOW TO FIX:       $how"
  [ -n "$next" ] && log_error "  → NEXT STEP:        $next"
}

# ── Test markers ─────────────────────────────────────────────────────
skip_test() { echo "${C_GRY}[SKIP]${C_RST} $1" | tee -a "$SCRIPT_LOG"; }
pass_test() { echo "${C_GRN}[PASS]${C_RST} $1" | tee -a "$SCRIPT_LOG"; }
fail_test() { echo "${C_RED}[FAIL]${C_RST} $1" | tee -a "$SCRIPT_LOG" >&2; }

# ── Hard dependency check ─────────────────────────────────────────────
require_cmd() {
  local cmd="$1"
  local fix="${2:-(no fix hint provided)}"
  local reason="${3:-}"
  if ! command -v "$cmd" &>/dev/null; then
    log_error "Required command not found: '$cmd'"
    [ -n "$reason" ] && log_error "  → WHY IT MATTERS: $reason"
    log_error "  → HOW TO FIX: $fix"
    exit 1
  fi
}

# ── Manifest writer ──────────────────────────────────────────────────
write_manifest() {
  local name="$1"
  shift
  local manifest="$MANIFEST_DIR/${name}.yaml"
  echo "install:" > "$manifest"
  echo "  name: $name" >> "$manifest"
  for kv in "$@"; do
    echo "  $kv" >> "$manifest"
  done
  echo "  timestamp: $(date -Iseconds)" >> "$manifest"
  log_info "Install manifest written: $manifest"
}

read_manifest_field() {
  local name="$1" field="$2"
  local manifest="$MANIFEST_DIR/${name}.yaml"
  [ -f "$manifest" ] || { echo ""; return 0; }
  awk -v k="$field" '
    $0 ~ "^[[:space:]]+"k":" {
      sub("^[[:space:]]+"k":[[:space:]]*","")
      print
      exit
    }' "$manifest"
}

# ── Docker group-aware helpers ────────────────────────────────────────
docker_daemon_reachable() {
  OSS_DOCKER_GROUP_RELOGIN_NEEDED=0
  if docker info &>/dev/null; then
    return 0
  fi
  local in_group_on_disk=0
  if getent group docker 2>/dev/null \
       | awk -F: -v u="$USER" '{split($4,m,","); for (i in m) if (m[i]==u) found=1} END {exit !found}'; then
    in_group_on_disk=1
  fi
  if [ "$in_group_on_disk" -eq 1 ] && [ -S /var/run/docker.sock ] && command -v sg &>/dev/null; then
    if sg docker -c 'docker info' &>/dev/null; then
      OSS_DOCKER_GROUP_RELOGIN_NEEDED=1
      return 0
    fi
  fi
  if sudo -n docker info &>/dev/null; then
    OSS_DOCKER_GROUP_RELOGIN_NEEDED=1
    return 0
  fi
  return 1
}

warn_docker_group_session() {
  log_warn "Docker daemon IS running, but your current shell can't reach the socket directly."
  log_warn "  → Your shell was started before you were added to the 'docker' group."
  log_warn "  → Fix: newgrp docker   OR open a new terminal and retry."
  log_warn "  Proceeding via 'sg docker' / sudo for this run."
}

docker_reexec_if_needed() {
  local script_path="$1"; shift
  if ! docker_daemon_reachable; then
    log_error "Docker daemon is not reachable."
    log_error "  → FIX: bash scripts/setup/docker.sh   # install + start daemon"
    log_error "  →      sudo systemctl start docker    # if installed but stopped"
    exit 1
  fi
  if [ "${OSS_DOCKER_GROUP_RELOGIN_NEEDED:-0}" -eq 1 ] && [ -z "${OSS_REEXEC_UNDER_SG:-}" ]; then
    warn_docker_group_session
    log_info "Re-executing $(basename "$script_path") under 'sg docker'"
    export OSS_REEXEC_UNDER_SG=1
    local argv_quoted=""
    for arg in "$@"; do argv_quoted+=" $(printf '%q' "$arg")"; done
    exec sg docker -c "bash $(printf '%q' "$script_path")$argv_quoted"
  fi
}

# ── State / stamps ────────────────────────────────────────────────────
stamp()      { mkdir -p "$STATE_DIR"; echo "$(date -Iseconds)" > "$STATE_DIR/${1}.done"; }
is_stamped() { [ -f "$STATE_DIR/${1}.done" ]; }

run_or_skip() {
  local name="$1" desc="$2"; shift 2
  if is_stamped "$name"; then
    log_skip "$desc"
    return 0
  fi
  log_step "$desc"
  if "$@"; then
    stamp "$name"
    return 0
  fi
  return 1
}

# ── Python venv helpers ───────────────────────────────────────────────
if [ -z "${OSS_PYTHON:-}" ]; then
  if [ -x "$REPO_ROOT/venv/bin/python3" ]; then
    OSS_PYTHON="$REPO_ROOT/venv/bin/python3"
  else
    OSS_PYTHON="$(command -v python3 || true)"
  fi
fi
export OSS_PYTHON

check_python_pkg() { "$OSS_PYTHON" -c "import $1" &>/dev/null; }

python_pkg_version() {
  "$OSS_PYTHON" -c "
import importlib.metadata as m
try: print(m.version('$1'))
except Exception: print('unknown')
" 2>/dev/null
}

# ── Platform detection ────────────────────────────────────────────────
is_wsl2()     { grep -qi "microsoft" /proc/version 2>/dev/null; }
has_systemd() { [ -d /run/systemd/system ]; }
is_macos()    { [ "$(uname -s)" = "Darwin" ]; }

detect_system() {
  local os arch
  os=$(uname -s)
  arch=$(uname -m)

  CPU_CORES=$(command -v nproc &>/dev/null && nproc || sysctl -n hw.ncpu 2>/dev/null || echo 1)

  if command -v free &>/dev/null; then
    MEM_GB=$(free -g | awk '/^Mem:/ {print $2}')
  elif [ "$os" = "Darwin" ]; then
    MEM_GB=$(($(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1024 / 1024 / 1024))
  else
    MEM_GB=0
  fi

  local disk_free
  disk_free=$(df -BG "$REPO_ROOT" 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G' || echo 0)
  DISK_GB=${disk_free:-0}

  if grep -qi "xeon" /proc/cpuinfo 2>/dev/null; then
    CPU_VENDOR="xeon"
  elif grep -qi "intel" /proc/cpuinfo 2>/dev/null; then
    CPU_VENDOR="intel"
  elif grep -qi "amd" /proc/cpuinfo 2>/dev/null; then
    CPU_VENDOR="amd"
  elif [ "$os" = "Darwin" ] && [ "$arch" = "arm64" ]; then
    CPU_VENDOR="apple-silicon"
  else
    CPU_VENDOR="generic"
  fi

  export CPU_CORES MEM_GB DISK_GB CPU_VENDOR

  log_info "System: $os ($arch) | CPU: ${CPU_CORES} cores ($CPU_VENDOR) | RAM: ${MEM_GB}GB | Disk: ${DISK_GB}GB"
}

detect_system
