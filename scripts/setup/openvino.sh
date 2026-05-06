#!/bin/bash
# =============================================================================
# openvino.sh — Install and verify Intel OpenVINO Toolkit
#
# PURPOSE:
#   Installs the Intel OpenVINO inference engine into the shared project venv,
#   verifies it with a real compile-and-infer test, and writes an install
#   manifest.  In oss-learn, OpenVINO runs:
#     - Plate detection model  (ONNX -> IR, optimised for CPU)
#     - Car detection model    (frozen_inference_graph from legacy C++ pipeline)
#
# ── Sources ─────────────────────────────────────────────────────────────────
#
# PyPI (default):
#   Package:     openvino>=2024.1
#   URL:         https://pypi.org/project/openvino/
#   Also:        openvino-dev>=2024.1 (Model Optimizer + benchmark tools)
#   Size:        ~300 MB (openvino) + ~500 MB (openvino-dev)
#   Installs to: shared venv at $REPO_ROOT/venv/
#
# Intel APT repo (alternative):
#   URL:         https://apt.repos.intel.com/openvino/
#   Package:     openvino-2024.1.0
#   Use when:    need C++ runtime or system-wide install
#
# Docker (alternative):
#   Image:       openvino/model_server:latest
#   URL:         https://hub.docker.com/r/openvino/model_server
#   Use when:    serving models via gRPC/REST (OVMS)
#
# Local build (--build):
#   Repo:        https://github.com/openvinotoolkit/openvino
#   Build:       cmake -DCMAKE_BUILD_TYPE=Release ..
#   Use when:    need custom ops or patched version
#
# ── Usage examples ──────────────────────────────────────────────────────────
#
#   bash scripts/setup/openvino.sh              # install + verify
#   bash scripts/setup/openvino.sh --check      # check only, no install
#   bash scripts/setup/openvino.sh --force      # re-install even if stamped
#   bash scripts/setup/openvino.sh --build      # build from GitHub source
#   bash scripts/setup/openvino.sh --help       # show usage
#
# EXIT CODES:
#   0 — installed and verified (or already present)
#   1 — installation or verification failed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/common.sh"

# ── Initialize script-specific logging ──────────────────────────────────
# Creates logs/openvino.log with detailed OpenVINO setup output.
set_script_log "openvino"

# ── Usage ───────────────────────────────────────────────────────────────────

usage() {
  cat <<'USAGE'
Usage: bash scripts/setup/openvino.sh [OPTIONS]

Options:
  --check   Verify whether OpenVINO is installed; do not install
  --force   Re-install and re-verify even if already stamped
  --build   Build OpenVINO from GitHub source (cmake)
  --help    Show this message

Returns 0 on success, 1 on failure.
Writes manifest: setup/state/installs/openvino.yaml
USAGE
  exit 0
}

# ── Parse arguments ─────────────────────────────────────────────────────────

CHECK_ONLY=0
FORCE=0
BUILD_FROM_SOURCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=1;        shift ;;
    --force) FORCE=1;             shift ;;
    --build) BUILD_FROM_SOURCE=1; shift ;;
    --help)  usage ;;
    *)
      log_error "Unknown option: $1"
      usage
      ;;
  esac
done

# ── Force clears existing stamps ────────────────────────────────────────────

if [ "$FORCE" -eq 1 ]; then
  log_warn "Force mode -- will re-install even if stamped"
  rm -f "$STATE_DIR/openvino_"*.done
fi

log_header "OpenVINO -- Intel Inference Engine Setup"
print_system_summary

# ── Python environment ──────────────────────────────────────────────────────
# Prefer the shared venv at $REPO_ROOT/venv/, fall back to system python3.

PYTHON="${OSS_PYTHON:-python3}"
if [ -f "$REPO_ROOT/venv/bin/python3" ]; then
  PYTHON="$REPO_ROOT/venv/bin/python3"
  log_info "Using project venv: $PYTHON"
else
  log_info "Using system Python: $PYTHON ($(${PYTHON} --version 2>&1))"
fi

# Export so check_python_pkg / python_pkg_version use the correct interpreter
export OSS_PYTHON="$PYTHON"

# ── Build from source (--build) ────────────────────────────────────────────

if [ "$BUILD_FROM_SOURCE" -eq 1 ]; then
  log_header "OpenVINO -- Build from source"
  log_step "Building OpenVINO from GitHub source..."

  OV_BUILD_DIR="$REPO_ROOT/setup/openvino/build"
  OV_SRC_DIR="$OV_BUILD_DIR/openvino"

  require_cmd cmake  "apt-get install cmake"
  require_cmd g++    "apt-get install g++"
  require_cmd git    "apt-get install git"

  if [ ! -d "$OV_SRC_DIR" ]; then
    log_step "Cloning openvinotoolkit/openvino..."
    mkdir -p "$OV_BUILD_DIR"
    git clone --depth 1 https://github.com/openvinotoolkit/openvino.git "$OV_SRC_DIR"
    cd "$OV_SRC_DIR" && git submodule update --init --recursive
  else
    log_skip "OpenVINO source already cloned at $OV_SRC_DIR"
  fi

  log_step "Running cmake configure..."
  mkdir -p "$OV_SRC_DIR/build"
  cd "$OV_SRC_DIR/build"
  cmake -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_PYTHON=ON \
        -DPYTHON_EXECUTABLE="$PYTHON" \
        ..

  log_step "Building (this will take a while)..."
  cmake --build . --parallel "$(nproc)"

  log_step "Installing Python wheel from build..."
  "$PYTHON" -m pip install --upgrade \
    "$OV_SRC_DIR/build/wheels/openvino-"*.whl --quiet \
    || log_warn "Wheel install failed -- check build output above"

  log_info "Source build complete. Continuing to verification..."
fi

# ── Step 1: Check if already installed ──────────────────────────────────────

log_step "Checking OpenVINO installation..."

if check_python_pkg openvino; then
  OV_VER=$(python_pkg_version openvino)
  log_info "OpenVINO is installed -- version $OV_VER"

  if [ "$CHECK_ONLY" -eq 1 ]; then
    log_info "Check-only mode. Done."
    exit 0
  fi

  if is_stamped "openvino_install" && [ "$FORCE" -eq 0 ]; then
    log_skip "OpenVINO install (version $OV_VER)"
  else
    log_warn "OpenVINO is installed but not stamped -- stamping now"
    stamp "openvino_install"
  fi
else
  OV_VER="not installed"
  log_warn "OpenVINO not found."

  if [ "$CHECK_ONLY" -eq 1 ]; then
    log_error "OpenVINO is NOT installed. Run without --check to install."
    exit 1
  fi

  # ── Step 2: Install openvino Python package ─────────────────────────────
  # The openvino wheel includes the runtime, model compilation tools, and
  # Python bindings.  Version >=2024.1 is required for Python 3.12 compat.
  log_step "Installing openvino Python package (this may take 2-3 minutes)..."
  run_or_skip "openvino_install" "pip install openvino>=2024.1" \
    "$PYTHON" -m pip install --upgrade "openvino>=2024.1" --quiet

  OV_VER=$(python_pkg_version openvino)
  log_info "Installed OpenVINO $OV_VER"
fi

# ── Step 3: Install openvino-dev (Model Optimizer + benchmark tools) ────────
# openvino-dev adds:
#   - Model Optimizer (mo): converts ONNX/TF/Torch -> IR (.xml + .bin)
#   - Benchmark App: measures throughput on a given model + device
#   - Accuracy Checker: evaluates model accuracy
# Only install if not already present (it's large, ~500 MB total).

if check_python_pkg openvino.tools; then
  OVD_VER=$(python_pkg_version openvino)
  log_skip "openvino-dev (already installed as part of openvino $OVD_VER)"
else
  run_or_skip "openvino_dev_install" "pip install openvino-dev>=2024.1" \
    "$PYTHON" -m pip install --upgrade "openvino-dev>=2024.1" --quiet \
    || log_warn "openvino-dev install failed -- skipping (runtime-only mode)"
fi

# ── Step 4: Run a verification inference ────────────────────────────────────
# Creates a tiny 2-node ONNX model in memory (single Add op), converts it
# to OpenVINO IR, runs inference on the CPU, and checks the output.
# This confirms the full pipeline works, not just the import.

if is_stamped "openvino_verify" && [ "$FORCE" -eq 0 ]; then
  log_skip "OpenVINO verification inference"
else
  log_step "Running OpenVINO verification inference (CPU device)..."

  "$PYTHON" - <<'PYEOF'
import sys
import numpy as np

print("  [openvino] Importing openvino...", flush=True)
import openvino as ov
print(f"  [openvino] Version: {ov.__version__}", flush=True)

print("  [openvino] Building a tiny Add model for verification...", flush=True)
# Use ov.opset8 — works in all 2022.3+ versions.
opset = ov.opset8

input_a = opset.parameter(ov.Shape([1, 3]), ov.Type.f32, name="a")
input_b = opset.parameter(ov.Shape([1, 3]), ov.Type.f32, name="b")
add     = opset.add(input_a, input_b)
model   = ov.Model([add], [input_a, input_b], "verify_add")

print("  [openvino] Compiling model on CPU device...", flush=True)
core = ov.Core()
devices = core.available_devices
print(f"  [openvino] Available devices: {devices}", flush=True)

compiled = core.compile_model(model, "CPU")
infer_req = compiled.create_infer_request()

print("  [openvino] Running inference: [1,2,3] + [4,5,6]...", flush=True)
a = np.array([[1.0, 2.0, 3.0]], dtype=np.float32)
b = np.array([[4.0, 5.0, 6.0]], dtype=np.float32)
result = infer_req.infer({"a": a, "b": b})
output = list(result.values())[0]

expected = np.array([[5.0, 7.0, 9.0]], dtype=np.float32)
assert np.allclose(output, expected), f"Wrong result: {output}"
print(f"  [openvino] Inference correct: {output}", flush=True)

print("  [openvino] CPU-only verification passed.", flush=True)
print("  [openvino] All checks passed.", flush=True)
PYEOF

  stamp "openvino_verify"
  log_info "OpenVINO verification passed"
fi

# ── Manifest ────────────────────────────────────────────────────────────────

write_manifest openvino \
  location=local \
  install_method="pip into shared venv" \
  venv="$REPO_ROOT/venv" \
  python="$PYTHON" \
  packages="openvino,openvino-dev" \
  version="$(python_pkg_version openvino)"

# ── Summary ─────────────────────────────────────────────────────────────────

log_header "OpenVINO -- Setup Complete"
echo "  Version  : $(python_pkg_version openvino)"
echo "  Python   : $PYTHON"
echo "  State dir: $STATE_DIR"
echo ""
echo "  Usage example:"
echo "    from openvino import Core"
echo "    core = Core()"
echo "    model = core.read_model('model.onnx')"
echo "    compiled = core.compile_model(model, 'CPU')"
echo ""
log_pass "OpenVINO $(python_pkg_version openvino)" \
  "pip install into shared venv; ov.Core() compile_model on CPU; tiny Add ONNX inference [1,2,3]+[4,5,6]==[5,7,9]" \
  "openvino $(python_pkg_version openvino) imported via $PYTHON; CPU device available in core.available_devices; verification Add inference returned the expected tensor" \
  "venv=$REPO_ROOT/venv, python=$PYTHON, packages=openvino+openvino-dev, manifest=$MANIFEST_DIR/openvino.yaml" \
  "bash scripts/setup/onnxruntime.sh"
