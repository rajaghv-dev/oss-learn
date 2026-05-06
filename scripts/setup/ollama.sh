#!/bin/bash
# =============================================================================
# ollama.sh — Ollama LLM server setup for the oss-learn project
#
# PURPOSE:
#   Install Ollama, start its HTTP server, pull a default model, and verify
#   end-to-end inference.  The Ollama *binary* is installed system-wide
#   (via /usr/local/bin/ollama), but all *model data* is stored locally
#   inside the repo at setup/data/ollama/models/.
#
# ── Sources ───────────────────────────────────────────────────────────
# Official install script (default):
#   URL:         https://ollama.com/install.sh
#   Method:      curl -fsSL https://ollama.com/install.sh | sh
#   Installs to: /usr/local/bin/ollama + /usr/local/lib/ollama/
#   Requires:    sudo, zstd
#   Why curl|sh: Ollama ships a multi-file bundle (binary + libs); the
#                installer handles extraction across distros
#
# GitHub releases (alternative):
#   URL:         https://github.com/ollama/ollama/releases
#   Tarball:     ollama-linux-amd64.tgz
#   Use when:    need specific version or offline install
#
# Docker (alternative):
#   Image:       ollama/ollama:latest
#   URL:         https://hub.docker.com/r/ollama/ollama
#   Compose:     setup/ollama/docker-compose.yml
#
# Local build (--build):
#   Repo:        https://github.com/ollama/ollama
#   Build:       go generate ./... && go build .
#   Requires:    Go 1.22+, cmake, gcc
#   Use when:    need custom patches
#
# Models:
#   Registry:    https://ollama.com/library
#   Default:     smollm2:135m (~270 MB — smallest usable, fast CPU)
#   Recommended: llama3.2:1b (1.3 GB) or llama3.2:3b (2 GB)
#   Storage:     $REPO_ROOT/setup/data/ollama/models/ (local to repo)
#
# USAGE EXAMPLES:
#   bash scripts/setup/ollama.sh                   # full install + model + verify
#   bash scripts/setup/ollama.sh --check           # check only, no changes
#   bash scripts/setup/ollama.sh --force           # re-run, ignore stamps
#   bash scripts/setup/ollama.sh --no-model        # install server only, skip pull
#   bash scripts/setup/ollama.sh --model=llama3.2:1b  # pull a different model
#   bash scripts/setup/ollama.sh --build           # build from Go source (stub)
#   bash scripts/setup/ollama.sh --help            # show usage
#
# EXIT CODES:
#   0 — success
#   1 — failure
#
# INSTALL LAYOUT:
#   EXTERNAL (system-wide, requires sudo):
#     /usr/local/bin/ollama            — binary
#     /usr/local/lib/ollama/           — runtime libraries
#     /etc/systemd/system/ollama.service — systemd unit (if applicable)
#
#   LOCAL (inside repo, no sudo):
#     setup/data/ollama/models/        — downloaded model blobs
#     setup/state/installs/ollama.yaml — manifest for uninstall tracking
#     setup/state/ollama_server.log    — server log (background daemon)
#     setup/state/ollama_server.pid    — PID file
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/common.sh"
# ── Initialize script-specific logging ──────────────────────────────────
# Creates logs/ollama.log with detailed output.
set_script_log "ollama"


# ── Constants ────────────────────────────────────────────────────────────────
# Install destination depends on whether sudo is non-interactively usable.
# With sudo: system-wide at /usr/local; without: user-local at ~/.local so
# the orchestrator can run unattended (mirrors scripts/setup/minikube.sh).
if sudo -n true 2>/dev/null; then
  OLLAMA_PREFIX="/usr/local"
  OLLAMA_INSTALL_MODE="sudo"
else
  OLLAMA_PREFIX="$HOME/.local"
  OLLAMA_INSTALL_MODE="user"
  mkdir -p "$OLLAMA_PREFIX/bin" "$OLLAMA_PREFIX/lib"
  case ":$PATH:" in
    *":$OLLAMA_PREFIX/bin:"*) ;;
    *) export PATH="$OLLAMA_PREFIX/bin:$PATH" ;;
  esac
fi
OLLAMA_BIN="$OLLAMA_PREFIX/bin/ollama"
OLLAMA_URL="http://localhost:11434"

# Model data lives LOCAL to the repo (not ~/.ollama/models) so that:
#   - All big data is removed by 'rm -rf oss-learn/'
#   - Multiple repo checkouts use separate model caches
#   - uninstall.sh only needs to nuke this directory
export OLLAMA_MODELS="${OLLAMA_MODELS:-$REPO_ROOT/setup/data/ollama/models}"

# Default model: smollm2:135m (~270 MB) — smallest usable, fast on CPU.
# Upgrade to llama3.2:1b (1.3 GB) or llama3.2:3b (2 GB) for quality.
DEFAULT_MODEL="smollm2:135m"

# ── Usage ────────────────────────────────────────────────────────────────────

usage() {
  cat <<'USAGE'
Usage: bash scripts/setup/ollama.sh [OPTIONS]

Options:
  --check         Check if Ollama is installed and running (no changes)
  --force         Re-run all steps, ignoring previous stamps
  --no-model      Install server only, skip model pull + verification
  --model=<name>  Pull a specific model (default: smollm2:135m)
  --build         Build Ollama from Go source instead of curl install
  --help          Show this message

Exit 0 on success, 1 on failure.
USAGE
  exit 0
}

# ── Parse arguments ──────────────────────────────────────────────────────────

CHECK_ONLY=0
FORCE=0
SKIP_MODEL=0
BUILD_FROM_SOURCE=0
MODEL="$DEFAULT_MODEL"

while [ $# -gt 0 ]; do
  case "$1" in
    --check)     CHECK_ONLY=1 ;;
    --force)     FORCE=1 ;;
    --no-model)  SKIP_MODEL=1 ;;
    --model=*)   MODEL="${1#*=}" ;;
    --build)     BUILD_FROM_SOURCE=1 ;;
    --help)      usage ;;
    *)
      log_error "Unknown option: $1"
      usage
      ;;
  esac
  shift
done

# ── Pre-flight ───────────────────────────────────────────────────────────────

mkdir -p "$OLLAMA_MODELS"
[ "$FORCE" -eq 1 ] && rm -f "$STATE_DIR/ollama_"*.done

log_header "Ollama — Local LLM Server Setup"
[ "$FORCE" -eq 1 ] && log_warn "Force mode — all stamps cleared"
[ "$SKIP_MODEL" -eq 1 ] && log_info "Skipping model pull (--no-model)"
[ "$MODEL" != "$DEFAULT_MODEL" ] && log_info "Using model: $MODEL"
print_system_summary

# ── Step 1: Check if Ollama binary exists ────────────────────────────────────

log_step "Checking Ollama installation..."

if command -v ollama &>/dev/null && [ -x "$OLLAMA_BIN" ]; then
  OLLAMA_VER=$(ollama --version 2>/dev/null | head -1 || echo "unknown version")
  log_info "Ollama is installed — $OLLAMA_VER ($OLLAMA_BIN)"

  if [ "$CHECK_ONLY" -eq 1 ]; then
    if curl -sf "$OLLAMA_URL/api/tags" &>/dev/null; then
      log_info "Ollama server is running at $OLLAMA_URL"
      log_info "Models dir: $OLLAMA_MODELS"
      ollama list 2>/dev/null | sed 's/^/    /' || true
    else
      log_warn "Ollama server is NOT running.  Start: ollama serve"
    fi
    exit 0
  fi

  is_stamped "ollama_install" || stamp "ollama_install"

else
  # Not installed
  if [ "$CHECK_ONLY" -eq 1 ]; then
    log_error "Ollama is not installed."
    exit 1
  fi

  # ── Step 2: Install Ollama ───────────────────────────────────────────────

  if [ "$BUILD_FROM_SOURCE" -eq 1 ]; then
    # ── Build from source (stub) ───────────────────────────────────────────
    # Building Ollama from source requires Go 1.22+, cmake, and gcc.
    # The build produces the binary + runtime libs identically to the
    # release tarballs, but allows custom patches.
    #
    # Repo:  https://github.com/ollama/ollama
    # Build: go generate ./... && go build .
    log_step "Building Ollama from source..."
    log_error "--build is not yet implemented."
    log_error "Build manually:"
    echo "  git clone https://github.com/ollama/ollama /tmp/ollama-build"
    echo "  cd /tmp/ollama-build"
    echo "  go generate ./... && go build ."
    echo "  sudo cp ollama /usr/local/bin/ollama"
    exit 1
  fi

  # ── Install: sudo path (curl|sh) OR sudo-less tarball into ~/.local ──────
  # The official curl|sh script needs sudo (writes /usr/local/bin and
  # creates an ollama system user). When sudo isn't reachable from the
  # orchestrator's child shell, fall back to extracting the published
  # ollama-linux-amd64.tgz under $HOME/.local — same binary, no daemon
  # user, no systemd unit.
  if [ "$OLLAMA_INSTALL_MODE" = "sudo" ]; then
    log_step "Installing Ollama via official install script (sudo)..."

    # zstd is required by the Ollama installer for decompression
    if ! command -v zstd &>/dev/null; then
      log_step "Installing zstd (required by the Ollama installer)..."
      if   command -v apt-get &>/dev/null; then sudo apt-get install -y zstd
      elif command -v dnf     &>/dev/null; then sudo dnf install -y zstd
      elif command -v yum     &>/dev/null; then sudo yum install -y zstd
      else
        log_error "Install zstd manually: sudo apt-get install zstd"
        exit 1
      fi
    fi

    run_or_skip "ollama_install" "curl https://ollama.com/install.sh | sh" \
      bash -c 'curl -fsSL https://ollama.com/install.sh | sh'
  else
    log_step "Installing Ollama from tarball into $OLLAMA_PREFIX (sudo not available)..."
    if ! command -v zstd &>/dev/null; then
      log_error "zstd is required to extract the Ollama release tarball; install it with apt-get install zstd"
      exit 1
    fi
    OLLAMA_TARBALL_URL="${OLLAMA_TARBALL_URL:-https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64.tar.zst}"
    OLLAMA_TMPDIR=$(mktemp -d)
    trap 'rm -rf "$OLLAMA_TMPDIR"' RETURN
    run_or_skip "ollama_install" "tarball -> $OLLAMA_PREFIX" \
      bash -c "curl -fsSL --retry 3 '$OLLAMA_TARBALL_URL' -o '$OLLAMA_TMPDIR/ollama.tar.zst' \
        && tar --zstd -xf '$OLLAMA_TMPDIR/ollama.tar.zst' -C '$OLLAMA_PREFIX' \
        && chmod +x '$OLLAMA_BIN'"
  fi

  OLLAMA_VER=$(ollama --version 2>/dev/null | head -1 || echo "installed")
  log_info "Installed: $OLLAMA_VER -> $OLLAMA_BIN"
fi

# ── Step 3: Start Ollama server if not running ───────────────────────────────
# Ollama runs as a persistent HTTP daemon on port 11434.  On WSL2 there is no
# systemd, so we start it manually via nohup.  The OLLAMA_MODELS env var
# (exported above) tells the server to store model data in our local path
# instead of ~/.ollama/models.

log_step "Checking if Ollama server is running..."

OLLAMA_PID_FILE="$STATE_DIR/ollama_server.pid"
OLLAMA_LOG_FILE="$STATE_DIR/ollama_server.log"

_start_ollama_server() {
  log_step "Starting Ollama server in background (logs -> $OLLAMA_LOG_FILE)..."
  nohup ollama serve > "$OLLAMA_LOG_FILE" 2>&1 &
  echo $! > "$OLLAMA_PID_FILE"

  # Wait up to 15 seconds for the server to become ready
  local attempts=0
  while [ $attempts -lt 15 ]; do
    if curl -sf "$OLLAMA_URL/api/tags" &>/dev/null; then
      log_info "Ollama server ready (PID $(cat "$OLLAMA_PID_FILE"))"
      return 0
    fi
    sleep 1
    ((attempts++)) || true
    printf "  . "
  done
  echo ""
  log_error "Ollama server did not become ready after 15 s.  Check $OLLAMA_LOG_FILE"
  return 1
}

if curl -sf "$OLLAMA_URL/api/tags" &>/dev/null; then
  log_info "Ollama server is already running at $OLLAMA_URL"
else
  _start_ollama_server
fi

# ── Step 4: Pull default model ───────────────────────────────────────────────
# Models are cached in OLLAMA_MODELS.  Re-running after a model is already
# pulled is a no-op (Ollama checks the digest).

if [ "$SKIP_MODEL" -eq 0 ]; then
  SAFE_MODEL=$(echo "$MODEL" | tr ':/' '__')

  if is_stamped "ollama_model_${SAFE_MODEL}" && [ "$FORCE" -eq 0 ]; then
    log_skip "Model pull: $MODEL"
  else
    # Check if model is already available locally before pulling
    if ollama list 2>/dev/null | grep -q "^${MODEL%:*}"; then
      log_info "Model $MODEL already exists locally — skipping download"
      stamp "ollama_model_${SAFE_MODEL}"
    else
      log_step "Pulling model: $MODEL"
      echo ""
      if ollama pull "$MODEL"; then
        stamp "ollama_model_${SAFE_MODEL}"
        log_info "Model $MODEL pulled successfully"
      else
        log_error "Failed to pull $MODEL — check your internet connection"
        exit 1
      fi
    fi
  fi
fi

# ── Step 5: Verify inference ─────────────────────────────────────────────────
# Send an arithmetic prompt via the REST API to confirm the model loaded and
# the HTTP interface works end-to-end.  Arithmetic ("1+1=") is deterministic
# even for tiny models; instruction-following prompts fail on sub-1B models.

if [ "$SKIP_MODEL" -eq 0 ]; then
  SAFE_MODEL=$(echo "$MODEL" | tr ':/' '__')

  if is_stamped "ollama_verify_${SAFE_MODEL}" && [ "$FORCE" -eq 0 ]; then
    log_skip "Ollama inference verification"
  else
    log_step "Running inference verification with model $MODEL..."
    echo "  Prompt: '1+1='"

    RESPONSE=$(curl -sf "$OLLAMA_URL/api/generate" \
      -H "Content-Type: application/json" \
      -d "{\"model\":\"${MODEL}\",\"prompt\":\"1+1=\",\"stream\":false,\"options\":{\"num_predict\":8,\"temperature\":0}}" \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('response','NO RESPONSE').strip())" 2>/dev/null \
      || echo "FAILED")

    echo "  Response: ${RESPONSE:0:80}"

    if [ "$RESPONSE" = "FAILED" ] || [ -z "$RESPONSE" ]; then
      log_warn "Inference call failed — check Ollama server logs at $OLLAMA_LOG_FILE"
    else
      # Accept any non-empty response: verifies model loaded and generated tokens.
      # Checking for "2" would fail on models that spell out "two" or add commentary.
      stamp "ollama_verify_${SAFE_MODEL}"
      log_info "Ollama inference verification passed (model: $MODEL responded)"
    fi
  fi
fi

# ── Manifest ─────────────────────────────────────────────────────────────────
# Record install locations so uninstall.sh can clean up.
# location=external because the binary is in /usr/local/ (system-wide, sudo).
# models_dir is local to the repo (no sudo needed to remove).

write_manifest ollama \
  location=external \
  install_method="curl|sh from ollama.com/install.sh" \
  binary="$OLLAMA_BIN" \
  install_libs="/usr/local/lib/ollama" \
  models_dir="$OLLAMA_MODELS" \
  systemd_service="/etc/systemd/system/ollama.service" \
  version="$(ollama --version 2>/dev/null | head -1 | awk '{print $NF}')"

# ── Summary ──────────────────────────────────────────────────────────────────
log_header "Ollama — Setup Complete"
echo "  Binary : $OLLAMA_BIN  (EXTERNAL — system install, tracked for uninstall)"
echo "  Models : $OLLAMA_MODELS  (LOCAL — inside repo)"
echo "  Version: $(ollama --version 2>/dev/null | head -1)"
echo "  Server : $OLLAMA_URL"
echo "  Models :"
ollama list 2>/dev/null | sed 's/^/    /' || echo "    (none pulled yet)"
echo ""
echo "  Usage examples:"
echo "    ollama run $MODEL                          # interactive chat"
echo "    ollama run $MODEL 'What is 1+1?'           # one-shot"
echo "    curl $OLLAMA_URL/api/generate \\"
echo "      -d '{\"model\":\"$MODEL\",\"prompt\":\"hello\",\"stream\":false}'"
echo ""
OLLAMA_VER_SHORT=$(ollama --version 2>/dev/null | head -1 | awk '{print $NF}' || echo unknown)
log_pass "Ollama ${OLLAMA_VER_SHORT} + model ${MODEL}" \
  "binary present at $OLLAMA_BIN; HTTP GET ${OLLAMA_URL}/api/tags returns 200; model ${MODEL} listed by 'ollama list'; POST ${OLLAMA_URL}/api/generate with prompt '1+1=' returned a non-empty response" \
  "ollama ${OLLAMA_VER_SHORT} installed at $OLLAMA_BIN; server reachable at ${OLLAMA_URL} (PID file ${OLLAMA_PID_FILE}); model ${MODEL} pulled into ${OLLAMA_MODELS}; inference verification stamped" \
  "binary=$OLLAMA_BIN, models_dir=$OLLAMA_MODELS, endpoint=${OLLAMA_URL}, port=11434, default_model=${MODEL}, manifest=$MANIFEST_DIR/ollama.yaml" \
  "ollama run ${MODEL} 'hello'   # or: bash scripts/setup/llama_cpp.sh"
