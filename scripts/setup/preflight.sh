#!/bin/bash
# =============================================================================
# preflight.sh — System preflight checks for oss-learn setup
#
# PURPOSE:
#   Validates that the host system meets the minimum requirements for running
#   the oss-learn platform.  No software is installed or modified — this is a
#   read-only check.  Called by the master orchestrator (scripts/setup.sh) as
#   Step 1, but can also be run standalone to audit a machine before setup.
#
# WHAT IT CHECKS:
#   1. OS         — Linux / macOS / WSL2 detection
#   2. Python     — 3.10+ required
#   3. Docker     — Engine present + Compose v2 plugin
#   4. Disk space — 20 GB minimum free, 10 GB warning
#   5. RAM        — 16 GB recommended, 8 GB minimum
#   6. CPU vendor — Xeon/Intel/AMD classification (informational only)
#   7. Downloads  — curl (required for Ollama), wget (optional)
#   8. git        — version control
#
# USAGE EXAMPLES:
#   bash scripts/setup/preflight.sh           # run all checks
#   bash scripts/setup/preflight.sh --check   # same — dry-run / audit mode
#   bash scripts/setup/preflight.sh --force   # re-run even if previously passed
#   bash scripts/setup/preflight.sh --help    # show usage
#
# EXIT CODES:
#   0 — all critical checks passed (warnings are non-fatal)
#   1 — one or more critical checks failed
#
# INTERFACE:
#   - Does NOT write install manifests (nothing to install)
#   - Does NOT stamp (master orchestrator handles that)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/common.sh"

# ── Initialize script-specific logging ──────────────────────────────────
# This creates logs/preflight.log with detailed check results.
# The main setup.log also receives all messages for centralized viewing.
set_script_log "preflight"

# ── Usage ────────────────────────────────────────────────────────────────────

usage() {
  cat <<'USAGE'
Usage: bash scripts/setup/preflight.sh [OPTIONS]

Options:
  --check   Run all checks (default behaviour)
  --force   Re-run checks unconditionally
  --help    Show this message

Exit 0 if all critical checks pass, 1 otherwise.
Warnings (disk tight, low RAM) are non-fatal.
USAGE
  exit 0
}

# ── Parse arguments ──────────────────────────────────────────────────────────

CHECK_ONLY=0
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=1; shift ;;
    --force) FORCE=1;      shift ;;
    --help)  usage ;;
    *)
      log_error "Unknown option: $1"
      usage
      ;;
  esac
done

# ── Run checks ───────────────────────────────────────────────────────────────

run_preflight() {
  # ── WHAT THIS FUNCTION DOES ───────────────────────────────────────────
  # Runs all system prerequisite checks before any software installation.
  # Each check is independent; a failure in one doesn't stop the others.
  #
  # CRITICAL FAILURES (exit 1): Python < 3.10, Disk < 10 GB
  # WARNINGS (non-fatal):       Low RAM, old Docker Compose
  #
  # LOGGING:
  #   - Terminal: coloured output (green ✓, yellow ⚠, red ✗)
  #   - logs/preflight.log: detailed timestamps + check rationale
  #   - setup/state/setup.log: centralized log for the whole run
  # ─────────────────────────────────────────────────────────────────────

  local critical_fail=0

  log_header "Preflight system checks"

  # ── CHECK 1: OPERATING SYSTEM ─────────────────────────────────────────
  # PURPOSE:  Verify we're on a supported OS for the oss-learn platform.
  # SUPPORTED: Linux (inc. WSL2), macOS
  # WHY:      Install paths, package managers, and library names differ by OS.
  # PASS:     Linux or macOS detected
  # FAIL:     (warning only) Unsupported OS — some steps may break
  # LOG:      Logs exact OS name + architecture for debugging
  # ─────────────────────────────────────────────────────────────────────
  log_step "Checking OS..."
  log_info "CHECK 1/8: Operating System — verifying Linux/macOS/WSL2 support"
  local os arch
  os=$(uname -s)
  arch=$(uname -m)
  case "$os" in
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        log_info "OS: WSL2 Linux ($arch) — fully supported"
        log_info "  → WSL2 detected: ensure Docker Desktop WSL2 integration is enabled"
      else
        log_info "OS: Linux ($arch) — fully supported"
      fi
      ;;
    Darwin)
      log_info "OS: macOS ($arch) — supported (Intel/Apple Silicon)"
      log_info "  → Note: some AI libs (OpenVINO) have limited macOS support"
      ;;
    *)
      log_warn "OS: $os ($arch) — UNTESTED platform"
      log_warn "  → This OS hasn't been validated — proceed at your own risk"
      log_warn "  → Supported platforms: Linux (x86_64), macOS (arm64/x86_64)"
      ;;
  esac

  # ── CHECK 2: PYTHON 3.10+ ─────────────────────────────────────────────
  # PURPOSE:  oss-learn services require Python 3.10+ for:
  #           - FastAPI (async support, type hints)
  #           - SQLAlchemy 2.x (requires Python 3.7+, recommended 3.10+)
  #           - OpenVINO 2026.1.0 (requires Python 3.8+)
  # PASS:     Python 3.10, 3.11, or 3.12 detected
  # FAIL:     Python < 3.10 (critical — exit 1)
  #           Python not found (critical — exit 1)
  # FIX:      Ubuntu: sudo apt install python3.12
  #           macOS:  brew install python@3.12
  # ─────────────────────────────────────────────────────────────────────
  log_step "Checking Python..."
  log_info "CHECK 2/8: Python 3.10+ — required for FastAPI services and AI libs"
  if command -v python3 &>/dev/null; then
    local py_ver py_maj py_min
    # FIX: Corrected Python version extraction
    # Original had malformed quotes: f'{sys.version_info.major}.{sys.version_info.minor'}'
    # The closing quote was inside the braces, causing syntax error
    py_ver=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    py_maj=${py_ver%%.*}
    py_min=${py_ver##*.}
    if [ "$py_maj" -ge 3 ] && [ "$py_min" -ge 10 ]; then
      log_info "Python $py_ver — OK (meets 3.10+ requirement)"
      log_info "  → Full version: $(python3 --version 2>&1)"
    else
      log_error "Python $py_ver found — FAILS minimum requirement (3.10+)"
      log_error "  → WHY IT FAILS: oss-learn uses type syntax and asyncio features from Python 3.10+"
      log_error "  → FIX: Install Python 3.10+:"
      log_error "       Ubuntu/Debian: sudo apt install python3.12 python3.12-venv"
      log_error "       macOS:          brew install python@3.12"
      log_error "       Then re-run:   bash scripts/setup/preflight.sh --force"
      critical_fail=1
    fi
  else
    log_error "python3 command not found — CRITICAL FAILURE"
    log_error "  → WHY IT FAILS: All oss-learn services are Python FastAPI applications"
    log_error "  → CHECKED: 'command -v python3' returned nothing in PATH"
    log_error "  → FIX: Install Python 3.10+ and ensure 'python3' is in your PATH:"
    log_error "       Ubuntu/Debian: sudo apt update && sudo apt install python3.12"
    log_error "       Verify:        which python3 && python3 --version"
    critical_fail=1
  fi

  # ── CHECK 3: DOCKER + DOCKER COMPOSE ──────────────────────────────────
  # PURPOSE:  All oss-learn services run as Docker containers (except local dev).
  #           Docker Compose v2 is needed for multi-service orchestration.
  # PASS:     docker command found + docker compose (v2 plugin) works
  # WARN:     Docker found but Compose v2 missing (can use docker-compose v1)
  # FAIL:     Docker not found (warning only — user may run services locally)
  # FIX:      https://docs.docker.com/get-docker/
  #           https://docs.docker.com/compose/install/
  # ─────────────────────────────────────────────────────────────────────
  log_step "Checking Docker..."
  log_info "CHECK 3/8: Docker + Compose — needed for containerized services"
  if command -v docker &>/dev/null; then
    local docker_ver docker_running
    docker_ver=$(docker --version | awk '{print $3}' | tr -d ',')
    log_info "Docker $docker_ver — OK (command found)"

    # Check if Docker daemon is actually running (not just binary present)
    if docker info &>/dev/null; then
      log_info "  → Docker daemon: RUNNING"
      docker_running="yes"
    else
      log_warn "  → Docker daemon: NOT RUNNING (start with: sudo systemctl start docker)"
      docker_running="no"
    fi

    # Check for Docker Compose v2 (plugin) — preferred
    if docker compose version &>/dev/null; then
      local compose_ver
      compose_ver=$(docker compose version --short 2>/dev/null || docker compose version 2>&1 | head -1)
      log_info "Docker Compose v2: $compose_ver — OK"
      log_info "  → 'docker compose up' will work for multi-service stacks"
    elif command -v docker-compose &>/dev/null; then
      log_warn "Docker Compose v1 found — recommend upgrading to v2 plugin"
      log_warn "  → WHY: v1 is deprecated; v2 is a Docker plugin (docker compose)"
      log_warn "  → FIX: sudo apt install docker-compose-plugin"
    else
      log_warn "Docker Compose not found — 'docker compose up' will fail"
      log_warn "  → WHY IT FAILS: docker-compose (v1) and docker compose (v2) both missing"
      log_warn "  → FIX: sudo apt install docker-compose-plugin"
      log_warn "  → Or:  sudo curl -SL \"https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-linux-x86_64\" -o /usr/local/bin/docker-compose && sudo chmod +x /usr/local/bin/docker-compose"
    fi
  else
    log_warn "Docker not found — services won't start without it"
    log_warn "  → WHY IT FAILS: 'command -v docker' returned nothing in PATH"
    log_warn "  → IMPACT: Cannot run containerized services (PostgreSQL, Ollama, stubs)"
    log_warn "  → FIX: Install Docker Desktop (Windows/WSL2/macOS) or Docker Engine (Linux):"
    log_warn "       https://docs.docker.com/get-docker/"
    log_warn "  → WSL2 USERS: Enable Docker Desktop WSL2 integration in Settings > Resources"
    log_warn "  → After install, verify: docker --version && docker compose version"
  fi

  # ── CHECK 4: DISK SPACE ───────────────────────────────────────────────
  # PURPOSE:  AI models are large; need minimum free space:
  #           - Ollama models: ~4-10 GB each (llama3: ~4.7 GB)
  #           - OpenVINO blobs: ~500 MB per model
  #           - Docker images: ~2-5 GB total
  # PASS:     20+ GB free
  # WARN:     10-19 GB (tight — can skip AI models)
  # FAIL:     <10 GB (critical — exit 1)
  # CHECK:    Runs 'df -k $REPO_ROOT' to check the filesystem hosting oss-learn
  # ─────────────────────────────────────────────────────────────────────
  log_step "Checking disk space..."
  log_info "CHECK 4/8: Disk space — AI models need ~20 GB free (Ollama + OpenVINO)"
  local avail_kb avail_gb
  avail_kb=$(df -k "$REPO_ROOT" | awk 'NR==2{print $4}')
  avail_gb=$((avail_kb / 1024 / 1024))
  log_info "  → Checking filesystem hosting: $REPO_ROOT"
    # FIX: Added closing quote to $REPO_ROOT
    # Original was missing closing quote: $REPO_ROOT" 
    log_info "  → Raw available: ${avail_kb} KB ($(df -h "$REPO_ROOT" | awk 'NR==2{print $4}') free)"

  if [ "$avail_gb" -ge 20 ]; then
    log_info "Disk: ${avail_gb} GB free — OK (enough for all AI models)"
  elif [ "$avail_gb" -ge 10 ]; then
    log_warn "Disk: ${avail_gb} GB free — TIGHT (need ~20 GB for LLM models)"
    log_warn "  → IMPACT: Can run core services, but skip AI model downloads"
    log_warn "  → FIX: Free up space, or run with: bash scripts/setup.sh (skip AI steps when prompted)"
  else
    log_error "Disk: ${avail_gb} GB free — CRITICAL FAILURE (need 20+ GB)"
    log_error "  → WHY IT FAILS: Less than 10 GB free; AI models alone need 4-10 GB each"
    log_error "  → CHECKED: 'df -k $REPO_ROOT' reported only ${avail_kb} KB available"
    log_error "  → FIX: Free up disk space before continuing:"
    log_error "       - Remove old Docker images: docker system prune -a"
    log_error "       - Clean package cache:    sudo apt clean"
    log_error "       - Check large files:      du -sh ~/* | sort -h"
    critical_fail=1
  fi

  # ── CHECK 5: RAM ──────────────────────────────────────────────────────
  # PURPOSE:  AI inference (llama.cpp, Ollama) loads models into RAM.
  #           - Small models (7B): ~4-6 GB RAM
  #           - Medium models (13B): ~8-10 GB RAM
  #           - PostgreSQL + 12 services: ~2-4 GB baseline
  # PASS:     16+ GB (recommended for full AI stack)
  # WARN:     8-15 GB (works, but limit model sizes)
  # INFO:     <8 GB (CPU-only mode, skip large models)
  # CHECK:    Uses 'free -g' (Linux) or 'sysctl hw.memsize' (macOS)
  # ─────────────────────────────────────────────────────────────────────
  log_step "Checking RAM..."
  log_info "CHECK 5/8: System RAM — AI inference loads models into memory"
  local ram_gb ram_bytes
  if command -v free &>/dev/null; then
    ram_gb=$(free -g | awk '/^Mem/{print $2}')
    ram_bytes=$(free -b | awk '/^Mem/{print $2}')
    log_info "  → Detected via 'free -g': ${ram_gb} GB (${ram_bytes} bytes)"
  elif sysctl -n hw.memsize &>/dev/null 2>&1; then
    # macOS fallback
    ram_bytes=$(sysctl -n hw.memsize)
    ram_gb=$(( ram_bytes / 1024 / 1024 / 1024 ))
    log_info "  → Detected via 'sysctl hw.memsize': ${ram_gb} GB"
  else
    log_warn "RAM: could not detect — no 'free' (Linux) or 'sysctl' (macOS) found"
    log_warn "  → CHECKED: 'command -v free' and 'sysctl -n hw.memsize' both failed"
    ram_gb=0
  fi

  if [ "$ram_gb" -ge 16 ]; then
    log_info "RAM: ${ram_gb} GB — OK (recommended for full AI stack with 7B+ models)"
    log_info "  → Can run: llama.cpp, Ollama (7B-13B models), all 12 microservices"
  elif [ "$ram_gb" -ge 8 ]; then
    log_warn "RAM: ${ram_gb} GB — OK for simulation, limited AI inference"
    log_warn "  → IMPACT: Can run core services + small AI models (7B or smaller)"
    log_warn "  → RECOMMENDATION: Use quantized models (Q4_K_M) to reduce RAM usage"
  elif [ "$ram_gb" -gt 0 ]; then
    log_warn "RAM: ${ram_gb} GB — limited, CPU-only inference recommended"
    log_warn "  → IMPACT: Skip llama.cpp/Ollama; use stub pods for AI services"
    log_warn "  → WHY: Small models need 4-6 GB; you only have ${ram_gb} GB total"
  else
    log_warn "RAM: could not detect system memory"
  fi

  # ── CHECK 6: CPU vendor / SIMD hints (INFO ONLY) ─────────────────────
  # oss-learn is CPU-only. This check just classifies the CPU so AI installers
  # can pick the most-optimized variant (e.g. OpenVINO build for Xeon AVX-512).
  # ─────────────────────────────────────────────────────────────────────
  log_step "Checking CPU vendor..."
  log_info "CHECK 6/8: CPU — oss-learn is CPU-only (no GPU paths)"
  if grep -qi "xeon" /proc/cpuinfo 2>/dev/null; then
    log_info "Intel Xeon detected — OpenVINO can use AVX-512/VNNI for INT8 inference"
  elif grep -qi "intel" /proc/cpuinfo 2>/dev/null; then
    log_info "Intel CPU detected — OpenVINO + ONNX Runtime CPU"
  elif grep -qi "amd" /proc/cpuinfo 2>/dev/null; then
    log_info "AMD CPU detected — ONNX Runtime CPU + llama.cpp AVX2"
  else
    log_info "Generic x86-64 — using CPU baseline (AVX2 if available)"
  fi

  # ── CHECK 7: DOWNLOAD TOOLS ──────────────────────────────────────────
  # PURPOSE:  Ollama and model downloads need curl or wget.
  #           - curl: Required for Ollama install script
  #           - wget: Optional, used for some model downloads
  # PASS:     curl found (required), wget found (bonus)
  # WARN:     curl missing (Ollama install will fail)
  # ─────────────────────────────────────────────────────────────────────
  log_step "Checking download tools..."
  log_info "CHECK 7/8: Download tools — curl (required), wget (optional)"
  if command -v curl &>/dev/null; then
    local curl_ver
    curl_ver=$(curl --version | head -1 | awk '{print $2}')
    log_info "curl $curl_ver — OK (needed for Ollama install)"
  else
    log_warn "curl not found — Ollama install will fail"
    log_warn "  → WHY IT FAILS: Ollama install script requires curl"
    log_warn "  → FIX: sudo apt install curl"
  fi
  if command -v wget &>/dev/null; then
    local wget_ver
    wget_ver=$(wget --version | head -1 | awk '{print $3}')
    log_info "wget $wget_ver — OK (optional, some scripts use it)"
  else
    log_info "wget not found — optional (no impact)"
  fi

  # ── CHECK 8: GIT ─────────────────────────────────────────────────────
  # PURPOSE:  Git is needed to clone repos, pull updates, and manage
  #           the oss-learn codebase itself.
  # PASS:     git command found, version logged
  # WARN:     git not found (can't pull updates, but can still run)
  # ─────────────────────────────────────────────────────────────────────
  log_step "Checking git..."
  log_info "CHECK 8/8: git — version control (needed for updates)"
  if command -v git &>/dev/null; then
    local git_ver
    git_ver=$(git --version | awk '{print $3}')
    log_info "git $git_ver — OK"
    if git rev-parse --git-dir &>/dev/null; then
      local git_branch git_remote
      git_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
      git_remote=$(git remote get-url origin 2>/dev/null || echo "no remote")
      log_info "  → Repository: branch=$git_branch, remote=$git_remote"
    fi
  else
    log_warn "git not found — cannot pull updates or clone repos"
    log_warn "  → IMPACT: oss-learn is already cloned, so it works; but can't update"
    log_warn "  → FIX: sudo apt install git"
  fi

  # ── FINAL SUMMARY ────────────────────────────────────────────────────
  # Prints final pass/fail and explains what to do next.
  # Logs the summary to both setup.log and preflight.log.
  # ─────────────────────────────────────────────────────────────────────
  log_info "════════════════════════════════════════════════════════════"
  if [ "$critical_fail" -ne 0 ]; then
    log_error "Preflight checks — FAILED (exit 1)"
    log_error "  → CRITICAL CHECKS FAILED — fix the errors above before continuing"
    log_error "  → Failed checks are marked with ✗ above — read the 'WHY IT FAILS' and 'FIX' lines"
    log_error "  → After fixing, re-run: bash scripts/setup/preflight.sh --force"
    log_error "  → Log file: logs/preflight.log (full details)"
    echo "" >&2
    # FIX: Changed C_RESET to C_RST to match the color variable defined in common.sh
    # The original code used C_RESET which doesn't exist, causing "unbound variable" error
    echo "${C_RED}  ━━━ Preflight checks — FAILED (exit 1, $(date +%s)s)━━━${C_RST}" >&2
    return 1
  fi

  log_pass "Preflight system checks" \
    "8 host checks: OS family, python3 ≥3.10, docker engine + compose v2, free disk on \$REPO_ROOT, system RAM, CPU vendor (AVX hints), curl/wget, git" \
    "OS=$os ($arch); Python=${py_ver:-not-detected}; Docker=${docker_ver:-not-detected} (daemon=${docker_running:-unknown}); disk=${avail_gb} GB free at $REPO_ROOT; RAM=${ram_gb} GB; curl=${curl_ver:-missing}; git=${git_ver:-missing}; no critical failures" \
    "logs/preflight.log; checked filesystem hosting $REPO_ROOT; no install manifest written (read-only audit)" \
    "bash scripts/setup.sh        # run full setup, or: bash scripts/setup.sh --step <name>"
  return 0
}

run_preflight
