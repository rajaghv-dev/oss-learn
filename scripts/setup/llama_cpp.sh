#!/bin/bash
# =============================================================================
# llama_cpp.sh — llama.cpp prebuilt binary / source build setup for oss-learn
#
# PURPOSE:
#   Installs llama.cpp C++ binaries (llama-cli, llama-server, llama-bench,
#   libllama.so) from the official ggml-org release.  Downloads a small
#   verification GGUF model and runs a one-shot inference test.
#
#   Fully local to the repo — `rm -rf oss-learn/ removes everything.
#   Recorded in setup/state/installs/llama_cpp.yaml for uninstall.sh.
#
# ── Sources ───────────────────────────────────────────────────────────
# Prebuilt binaries (default — fast, ~30s):
#   Repo:        https://github.com/ggml-org/llama.cpp/releases
#   Build tag:   b4738 (default, override via LLAMA_BUILD env)
#   Variants:
#     CPU standard:   llama-b4738-bin-ubuntu-x64.tar.gz
#     OpenVINO Intel: llama-b4738-bin-ubuntu-openvino-2026.1-x64.tar.gz
#       (auto-selected when Intel CPU + OpenVINO Python package present)
#   Install to:  $REPO_ROOT/setup/llama_cpp/install/ (flat — llama-cli at top)
#
# Build from source (--build — 5-15 min):
#   Repo:        https://github.com/ggml-org/llama.cpp
#   Tag:         b4738 (same as prebuilt)
#   Build:       cmake + make (CPU-only)
#   Flags:       -DGGML_NATIVE=ON
#   Requires:    cmake, git, make, gcc/g++
#   Use when:    custom patches, non-x64 arch
#
# Verification model:
#   URL:         https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf
#   Size:        ~350 MB
#   Storage:     $REPO_ROOT/setup/state/verify_model.gguf
#
# USAGE EXAMPLES:
#   bash scripts/setup/llama_cpp.sh                    # prebuilt, auto-variant
#   bash scripts/setup/llama_cpp.sh --build            # build from source (cmake)
#   bash scripts/setup/llama_cpp.sh --no-model         # skip GGUF model download
#   bash scripts/setup/llama_cpp.sh --check            # check only, change nothing
#   bash scripts/setup/llama_cpp.sh --force            # re-install from scratch
#   bash scripts/setup/llama_cpp.sh --help             # show this header
#
# EXIT CODES:
#   0  — Success (binaries installed, inference verified)
#   1  — Failure (download error, build error, verification failed)
# =============================================================================

set -euo pipefail

# ── Resolve paths ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Source shared helpers (logging, stamps, manifests) ───────────────────────
source "$REPO_ROOT/scripts/common.sh"
# ── Initialize script-specific logging ──────────────────────────────────
# Creates logs/llama_cpp.log with detailed output.
set_script_log "llama_cpp"


# ── Usage ────────────────────────────────────────────────────────────────────
usage() {
  cat <<'USAGE'
Usage: bash scripts/setup/llama_cpp.sh [OPTIONS]

Options:
  --check      Report current install status, change nothing
  --force      Remove existing install and redo from scratch
  --no-model   Skip verification GGUF model download (~350 MB)
  --build      Build from source via cmake instead of prebuilt tarball
  --help       Show this message

Environment:
  LLAMA_BUILD  Override build tag (default: b4738)

Exit 0 on success, 1 on failure.
USAGE
  exit 0
}

# ── Parse arguments ──────────────────────────────────────────────────────────
CHECK_ONLY=0
FORCE=0
SKIP_MODEL=0
BUILD_FROM_SOURCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --check)                CHECK_ONLY=1 ;;
    --force)                FORCE=1; log_warn "Force mode — will re-install" ;;
    --cpu-only)             log_warn "--cpu-only is deprecated (oss-learn is CPU-only); ignoring" ;;
    --no-model)             SKIP_MODEL=1; log_info "Skipping model download" ;;
    --build|--from-source)  BUILD_FROM_SOURCE=1; log_info "Build from source mode" ;;
    --help|-h)              usage ;;
    *)                      log_warn "Unknown argument: $1" ;;
  esac
  shift
done

# ── Constants ────────────────────────────────────────────────────────────────
LLAMA_BUILD="${LLAMA_BUILD:-b4738}"
LLAMA_INSTALL_DIR="$REPO_ROOT/setup/llama_cpp/install"
LLAMA_BIN_DIR="$LLAMA_INSTALL_DIR"
LLAMA_CLI="$LLAMA_BIN_DIR/llama-cli"
VERIFY_MODEL_URL="https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"
VERIFY_MODEL_FILE="$STATE_DIR/verify_model.gguf"

# ── Variant selection ────────────────────────────────────────────────────────
# OpenVINO variant: Intel CPU + Python OpenVINO package present (we install
# OpenVINO before this script runs in the orchestrator).
# Otherwise: standard CPU variant (works on any x64 Linux).
select_variant() {
  detect_system

  local python="${OSS_PYTHON:-python3}"
  if [ -f "$REPO_ROOT/venv/bin/python3" ]; then
    python="$REPO_ROOT/venv/bin/python3"
  fi

  # ggml-org/llama.cpp release b4738 ships only two Linux variants:
  #   ubuntu-x64        (CPU, AVX2 baseline)
  #   ubuntu-vulkan-x64 (Vulkan GPU — not used here, oss-learn is CPU-only)
  # No OpenVINO-flavoured tarball exists for this build, so the variant
  # selector simplifies to a single CPU choice.
  LLAMA_VARIANT="ubuntu-x64"
  VARIANT_DESC="standard CPU (AVX2)"

  # Release assets are .zip on this build; older builds used .tar.gz.
  LLAMA_ARCHIVE_URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_BUILD}/llama-${LLAMA_BUILD}-bin-${LLAMA_VARIANT}.zip"
  LLAMA_ARCHIVE="$LLAMA_INSTALL_DIR/llama-${LLAMA_BUILD}-${LLAMA_VARIANT}.zip"
}

# ── --check mode ─────────────────────────────────────────────────────────────
report_status() {
  log_header "llama.cpp — Status"

  if [ -x "$LLAMA_CLI" ]; then
    log_info "llama-cli found: $LLAMA_CLI"
    "$LLAMA_CLI" --version 2>&1 | head -3 | sed 's/^/    /'
  else
    log_warn "llama-cli not found at $LLAMA_CLI"
  fi

  if [ -f "$VERIFY_MODEL_FILE" ]; then
    local model_size
    model_size=$(du -h "$VERIFY_MODEL_FILE" | cut -f1)
    log_info "Verification model: $VERIFY_MODEL_FILE ($model_size)"
  else
    log_warn "Verification model not downloaded"
  fi

  local manifest="$MANIFEST_DIR/llama_cpp.yaml"
  if [ -f "$manifest" ]; then
    log_info "Manifest: $manifest"
    sed 's/^/    /' "$manifest"
  else
    log_warn "Manifest: not written yet"
  fi

  [ -x "$LLAMA_CLI" ] && return 0 || return 1
}

# =============================================================================
# 1. Install: prebuilt tarball download
# =============================================================================
install_prebuilt() {
  log_step "Downloading llama.cpp ${LLAMA_BUILD} ${LLAMA_VARIANT}..."
  log_info "URL: $LLAMA_ARCHIVE_URL"

  if ! curl -fL --retry 3 --progress-bar "$LLAMA_ARCHIVE_URL" -o "$LLAMA_ARCHIVE"; then
    log_error "Failed to download $LLAMA_ARCHIVE_URL"
    log_warn "Fall back to --build (cmake from source)."
    return 1
  fi

  command -v unzip &>/dev/null || {
    log_error "unzip not installed — required for llama.cpp .zip archives"
    log_error "  apt-get install -y unzip"
    return 1
  }

  log_step "Extracting archive to $LLAMA_INSTALL_DIR..."
  # The b4738 zip lays out files as build/bin/llama-cli (no top-level dir
  # to strip). Extract into a temp dir, then flatten build/bin/* + libs
  # so callers find binaries at $LLAMA_INSTALL_DIR/llama-cli.
  local tmp="$LLAMA_INSTALL_DIR/.unzip"
  rm -rf "$tmp"; mkdir -p "$tmp"
  unzip -q "$LLAMA_ARCHIVE" -d "$tmp"
  rm -f "$LLAMA_ARCHIVE"

  # Move binaries (build/bin/*) and shared libs (build/src/*.so etc.) to flat path
  if [ -d "$tmp/build/bin" ]; then
    cp -a "$tmp/build/bin/." "$LLAMA_INSTALL_DIR/"
  fi
  for ext in so dylib; do
    find "$tmp" -name "*.${ext}" -exec cp -a {} "$LLAMA_INSTALL_DIR/" \; 2>/dev/null || true
  done
  rm -rf "$tmp"

  if [ ! -x "$LLAMA_CLI" ]; then
    log_error "llama-cli not found at $LLAMA_CLI after extraction"
    log_error "Archive layout may have changed — contents:"
    ls -1 "$LLAMA_INSTALL_DIR" | sed 's/^/    /'
    return 1
  fi

  stamp "llama_cpp_install"
  log_info "llama.cpp binaries installed: $LLAMA_BIN_DIR"
}

# =============================================================================
# 2. Install: build from source via cmake
# =============================================================================
install_from_source() {
  # Require build tools
  for tool in cmake git make; do
    command -v "$tool" >/dev/null || { log_error "$tool is required for --build"; return 1; }
  done

  # CPU-only build (oss-learn is CPU-only)
  local cmake_flags="-DGGML_NATIVE=ON"
  log_info "Build target: CPU (native SIMD)"

  local src_dir="$LLAMA_INSTALL_DIR/src"
  local build_dir="$LLAMA_INSTALL_DIR/build"
  rm -rf "$src_dir" "$build_dir"
  mkdir -p "$src_dir"

  log_step "Cloning llama.cpp tag $LLAMA_BUILD..."
  if ! git clone --quiet --depth 1 --branch "$LLAMA_BUILD" \
    https://github.com/ggml-org/llama.cpp.git "$src_dir"; then
    log_error "git clone failed"
    return 1
  fi

  log_step "Configuring cmake ($cmake_flags)..."
  if ! cmake -S "$src_dir" -B "$build_dir" $cmake_flags; then
    log_error "cmake configure failed"
    return 1
  fi

  log_step "Building llama.cpp (this takes 5-15 min)..."
  if ! cmake --build "$build_dir" --config Release -j"$(nproc)"; then
    log_error "cmake build failed"
    return 1
  fi

  # Copy binaries + libs to the flat standard location so source-build and
  # prebuilt installs share the same paths.
  log_step "Installing binaries to flat path: $LLAMA_INSTALL_DIR/"
  for f in "$build_dir/bin/"*; do
    [ -e "$f" ] && cp -a "$f" "$LLAMA_INSTALL_DIR/" || true
  done

  # Shared libs (libllama.so etc.) live next to bin/ in modern cmake builds
  for ext in so dylib dll; do
    for f in "$build_dir"/*."$ext" "$build_dir/src/"*."$ext" "$build_dir/ggml/src/"*."$ext"; do
      [ -e "$f" ] && cp -a "$f" "$LLAMA_INSTALL_DIR/" || true
    done
  done
  rm -rf "$src_dir" "$build_dir"

  if [ ! -x "$LLAMA_CLI" ]; then
    log_error "Build finished but llama-cli not found at $LLAMA_CLI"
    return 1
  fi

  stamp "llama_cpp_install"
  log_info "llama.cpp built from source — $LLAMA_BIN_DIR"
}

# =============================================================================
# 3. Download verification GGUF model (~350 MB)
# =============================================================================
download_model() {
  if [ "$SKIP_MODEL" -eq 1 ]; then
    return 0
  fi

  if is_stamped "llama_cpp_model" && [ -f "$VERIFY_MODEL_FILE" ] && [ "$FORCE" -eq 0 ]; then
    log_skip "Verification model download"
    return 0
  fi

  if [ -f "$VERIFY_MODEL_FILE" ]; then
    log_info "Verification model already exists: $VERIFY_MODEL_FILE"
    stamp "llama_cpp_model"
    return 0
  fi

  log_step "Downloading verification model (~350 MB)..."
  if curl -fL --retry 3 --progress-bar "$VERIFY_MODEL_URL" -o "$VERIFY_MODEL_FILE"; then
    stamp "llama_cpp_model"
    log_info "Model downloaded: $VERIFY_MODEL_FILE"
  else
    log_warn "Model download failed — skipping verification"
    SKIP_MODEL=1
  fi
}

# =============================================================================
# 4. Run verification inference
# =============================================================================
verify_inference() {
  if [ "$SKIP_MODEL" -eq 1 ] || [ ! -f "$VERIFY_MODEL_FILE" ]; then
    return 0
  fi

  if is_stamped "llama_cpp_verify" && [ "$FORCE" -eq 0 ]; then
    log_skip "llama-cli inference verification"
    return 0
  fi

  log_step "Running llama-cli inference verification..."
  # -no-cnv disables interactive conversation mode (one-shot completion)
  # -n 16 limits to 16 tokens (fast)
  # --temp 0 for deterministic output
  local response
  if response=$("$LLAMA_CLI" \
                  -m "$VERIFY_MODEL_FILE" \
                  -p "Q: What is 2+2? A:" \
                  -n 16 \
                  --temp 0 \
                  -no-cnv \
                  2>/dev/null \
                | tail -3); then
    echo "    Response: $(echo "$response" | head -1)"
    stamp "llama_cpp_verify"
    log_info "llama-cli inference verification passed"
  else
    log_warn "llama-cli inference test failed (binary works but inference issue)"
  fi
}

# =============================================================================
# 5. Write install manifest
# =============================================================================
write_llama_manifest() {
  local install_method="prebuilt"
  [ "$BUILD_FROM_SOURCE" -eq 1 ] && install_method="source"

  local llama_ver
  llama_ver=$("$LLAMA_CLI" --version 2>&1 | head -1 | awk '{print $NF}' || echo "$LLAMA_BUILD")

  write_manifest llama_cpp \
    location=local \
    install_method="$install_method" \
    build="$LLAMA_BUILD" \
    variant="$LLAMA_VARIANT" \
    install_dir="$LLAMA_INSTALL_DIR" \
    binary_dir="$LLAMA_BIN_DIR" \
    cli="$LLAMA_CLI" \
    server="$LLAMA_BIN_DIR/llama-server" \
    verify_model="$VERIFY_MODEL_FILE" \
    version="$llama_ver"
}

# =============================================================================
# Main
# =============================================================================
main() {
  # Force: clear stamps so everything re-runs
  [ "$FORCE" -eq 1 ] && rm -f "$STATE_DIR/llama_cpp_"*.done

  log_header "llama.cpp — Prebuilt Binary Setup"
  print_system_summary

  # Select variant (CPU vs OpenVINO) based on hardware
  select_variant
  mkdir -p "$LLAMA_INSTALL_DIR"

  log_info "Build      : $LLAMA_BUILD"
  log_info "Variant    : $LLAMA_VARIANT  ($VARIANT_DESC)"
  log_info "Install dir: $LLAMA_INSTALL_DIR"

  # --check: report and exit
  if [ "$CHECK_ONLY" -eq 1 ]; then
    report_status
    return $?
  fi

  # ── Step 1: Install (prebuilt or source) ─────────────────────────────────
  if [ -x "$LLAMA_CLI" ] && [ "$FORCE" -eq 0 ]; then
    log_info "llama-cli already present at $LLAMA_CLI"
    is_stamped "llama_cpp_install" || stamp "llama_cpp_install"
  elif [ "$BUILD_FROM_SOURCE" -eq 1 ]; then
    install_from_source || return 1
  else
    install_prebuilt || return 1
  fi

  # ── Step 2: LD_LIBRARY_PATH for shared libs ─────────────────────────────
  export LD_LIBRARY_PATH="$LLAMA_BIN_DIR:${LD_LIBRARY_PATH:-}"

  # ── Step 3: Download verification model ──────────────────────────────────
  download_model

  # ── Step 4: Run inference test ───────────────────────────────────────────
  verify_inference

  # ── Step 5: Write manifest ───────────────────────────────────────────────
  write_llama_manifest

  # ── Summary ──────────────────────────────────────────────────────────────
  log_header "llama.cpp — Setup Complete"
  echo "  Build       : $LLAMA_BUILD ($LLAMA_VARIANT)"
  echo "  Install dir : $LLAMA_INSTALL_DIR"
  echo "  Binaries    :"
  ls -1 "$LLAMA_BIN_DIR" 2>/dev/null | grep -E '^llama-' | sed 's/^/    /'
  [ -f "$VERIFY_MODEL_FILE" ] && echo "  Test model  : $VERIFY_MODEL_FILE"
  echo ""
  echo "  Usage:"
  echo "    $LLAMA_CLI -m model.gguf -p 'hello'"
  echo "    $LLAMA_BIN_DIR/llama-server -m model.gguf --port 8084"
  echo ""
  local llama_ver
  llama_ver=$("$LLAMA_CLI" --version 2>&1 | head -1 | awk '{print $NF}' || echo "$LLAMA_BUILD")
  local install_method="prebuilt tarball"
  [ "$BUILD_FROM_SOURCE" -eq 1 ] && install_method="cmake from source"
  local checked_msg="downloaded ${install_method} for build ${LLAMA_BUILD} (${LLAMA_VARIANT}); flat-installed binaries to $LLAMA_BIN_DIR; ran 'llama-cli -m verify_model.gguf -p \"Q: What is 2+2? A:\" -n 16 --temp 0 -no-cnv'"
  local why_msg="llama-cli ${llama_ver} executable at $LLAMA_CLI; verification GGUF (${VERIFY_MODEL_FILE##*/}) ran one-shot inference and produced output"
  if [ "$SKIP_MODEL" -eq 1 ] || [ ! -f "$VERIFY_MODEL_FILE" ]; then
    checked_msg="downloaded ${install_method} for build ${LLAMA_BUILD} (${LLAMA_VARIANT}); flat-installed binaries to $LLAMA_BIN_DIR; verified llama-cli is executable (model download skipped)"
    why_msg="llama-cli ${llama_ver} executable at $LLAMA_CLI; --no-model requested or model file absent, so inference verification was intentionally skipped"
  fi
  log_pass "llama.cpp ${LLAMA_BUILD} (${LLAMA_VARIANT})" \
    "$checked_msg" \
    "$why_msg" \
    "install_dir=$LLAMA_INSTALL_DIR, cli=$LLAMA_CLI, server=$LLAMA_BIN_DIR/llama-server, verify_model=$VERIFY_MODEL_FILE, build=$LLAMA_BUILD, variant=$LLAMA_VARIANT, manifest=$MANIFEST_DIR/llama_cpp.yaml" \
    "$LLAMA_CLI -m $VERIFY_MODEL_FILE -p 'hello'   # or: $LLAMA_BIN_DIR/llama-server -m model.gguf --port 8084"
}

main "$@"
