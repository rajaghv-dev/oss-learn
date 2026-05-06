#!/bin/bash
# =============================================================================
# onnxruntime.sh — ONNX Runtime inference engine setup for oss-learn (CPU-only)
#
# PURPOSE:
#   Installs and verifies ONNX Runtime (ORT) CPU-only.
#   Used for oss-learn's plate and vehicle detection models (.onnx format).
#   GPU support has been removed — oss-learn is CPU-only.
#
# ── Sources ───────────────────────────────────────────────────────────
# PyPI — CPU (always works):
#   Package:     onnxruntime
#   URL:         https://pypi.org/project/onnxruntime/
#
# Conda (alternative):
#   conda install -c conda-forge onnxruntime
#
# Microsoft releases (alternative):
#   https://github.com/microsoft/onnxruntime/releases
#
# Local build (--build):
#   Repo:        https://github.com/microsoft/onnxruntime
#   Build:       ./build.sh --config Release --parallel
#   Use when:    need custom execution providers or patched build
#
# USAGE EXAMPLES:
#   bash scripts/setup/onnxruntime.sh               # install + verify
#   bash scripts/setup/onnxruntime.sh --check       # check only, no install
#   bash scripts/setup/onnxruntime.sh --force       # re-install even if stamped
#   bash scripts/setup/onnxruntime.sh --build       # build from source (stub)
#   bash scripts/setup/onnxruntime.sh --help        # show usage
#
# EXIT CODES:
#   0 — CPU inference works
#   1 — CPU inference failed or install error
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/common.sh"
# ── Initialize script-specific logging ──────────────────────────────────
# Creates logs/onnxruntime.log with detailed output.
set_script_log "onnxruntime"


# ── Usage ────────────────────────────────────────────────────────────────────

usage() {
  cat <<'USAGE'
Usage: bash scripts/setup/onnxruntime.sh [OPTIONS]

Options:
  --check       Check installation status only, no install
  --force       Re-install even if previously completed
  --build       Build from Microsoft source (stub — not yet implemented)
  --help        Show this message

Exit 0 if CPU inference works.
USAGE
  exit 0
}

# ── Parse arguments ──────────────────────────────────────────────────────────

CHECK_ONLY=0
FORCE=0
BUILD_FROM_SOURCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --check)    CHECK_ONLY=1;        shift ;;
    --force)    FORCE=1;             shift ;;
    --build)    BUILD_FROM_SOURCE=1; shift ;;
    --help)     usage ;;
    *)
      log_error "Unknown option: $1"
      usage
      ;;
  esac
done

[ "$FORCE" -eq 1 ] && log_warn "Force mode — will re-install even if stamped"
[ "$FORCE" -eq 1 ] && rm -f "$STATE_DIR/ort_"*.done

log_header "ONNX Runtime — Inference Engine Setup"
print_system_summary

# ── Build from source (stub) ────────────────────────────────────────────────

if [ "$BUILD_FROM_SOURCE" -eq 1 ]; then
  log_header "ONNX Runtime — Build from Source"
  log_warn "Build-from-source is a stub — not yet implemented."
  echo ""
  echo "  To build manually:"
  echo "    git clone --recursive https://github.com/microsoft/onnxruntime.git"
  echo "    cd onnxruntime"
  echo "    ./build.sh --config Release --parallel"
  echo ""
  echo "  Use this when you need custom execution providers or a patched build."
  echo "  See: https://onnxruntime.ai/docs/build/"
  echo ""
  log_error "Exiting — --build not yet automated."
  exit 1
fi

# ── Python environment ───────────────────────────────────────────────────────

PYTHON="${OSS_PYTHON:-python3}"
if [ -f "$REPO_ROOT/venv/bin/python3" ]; then
  PYTHON="$REPO_ROOT/venv/bin/python3"
elif [ -f "$SCRIPT_DIR/venv/bin/python3" ]; then
  PYTHON="$SCRIPT_DIR/venv/bin/python3"
fi
log_info "Python: $PYTHON ($(${PYTHON} --version 2>&1))"

# ── Variant: CPU-only always ────────────────────────────────────────────────

ORT_PACKAGE="onnxruntime"
log_info "Using onnxruntime (CPU-only) — oss-learn is CPU-only"

# ── Step 1: Check current installation ───────────────────────────────────────

log_step "Checking ONNX Runtime installation..."

if check_python_pkg onnxruntime; then
  ORT_VER=$(python_pkg_version onnxruntime)
  log_info "ONNX Runtime is installed — version $ORT_VER"

  if [ "$CHECK_ONLY" -eq 1 ]; then
    log_info "Check-only mode. Done."
    exit 0
  fi

  if is_stamped "ort_install" && [ "$FORCE" -eq 0 ]; then
    log_skip "ONNX Runtime install ($ORT_VER)"
  else
    stamp "ort_install"
  fi
else
  log_warn "ONNX Runtime not found."
  [ "$CHECK_ONLY" -eq 1 ] && { log_error "Not installed. Run without --check."; exit 1; }

  # ── Step 2: Install ONNX Runtime (CPU) ───────────────────────────────────
  run_or_skip "ort_install" "pip install onnxruntime" \
    "$PYTHON" -m pip install --upgrade onnxruntime --quiet

  ORT_VER=$(python_pkg_version onnxruntime)
  log_info "Installed ONNX Runtime $ORT_VER"
fi

# ── Step 3: Install numpy + onnx (needed for verification model) ────────────
# onnx lets us build ONNX models programmatically for the verification test.
# Without it, the verify script falls back to pre-baked protobuf bytes which
# may not be valid for newer ORT versions.

run_or_skip "ort_deps" "pip install numpy onnx" \
  "$PYTHON" -m pip install --upgrade "numpy>=1.24" onnx --quiet

# ── Step 4: Verify — build synthetic ONNX model and run inference ────────────

if is_stamped "ort_verify" && [ "$FORCE" -eq 0 ]; then
  log_skip "ONNX Runtime verification inference"
else
  log_step "Running ONNX Runtime verification inference..."

  "$PYTHON" - <<'PYEOF'
import sys
import numpy as np

print("  [ort] Importing onnxruntime...", flush=True)
import onnxruntime as ort
providers = ort.get_available_providers()
print(f"  [ort] Version: {ort.__version__}", flush=True)
print(f"  [ort] Available providers: {providers}", flush=True)

# Build a minimal ONNX model (MatMul: output = A @ B)
print("  [ort] Creating a minimal ONNX MatMul model for verification...", flush=True)
import io

def make_onnx_matmul():
    """
    Build the smallest valid ONNX model for A @ B.
    A: [2, 3]   B: [3, 2]   output: [2, 2]
    Uses onnx helper if available, otherwise falls back to pre-baked protobuf.
    """
    try:
        import onnx
        from onnx import helper, TensorProto
        a = helper.make_tensor_value_info("A", TensorProto.FLOAT, [2, 3])
        b = helper.make_tensor_value_info("B", TensorProto.FLOAT, [3, 2])
        out = helper.make_tensor_value_info("C", TensorProto.FLOAT, [2, 2])
        node = helper.make_node("MatMul", ["A", "B"], ["C"])
        graph = helper.make_graph([node], "test", [a, b], [out])
        model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 13)])
        buf = io.BytesIO()
        buf.write(model.SerializeToString())
        buf.seek(0)
        return buf.read()
    except ImportError:
        # onnx package not installed — use a pre-serialised tiny MatMul model
        # (Minimal valid ONNX protobuf for [2,3] @ [3,2] -> [2,2])
        return bytes([
            0x08, 0x07, 0x12, 0x3e, 0x0a, 0x0c, 0x0a, 0x01, 0x41, 0x0a, 0x01,
            0x42, 0x12, 0x01, 0x43, 0x12, 0x06, 0x4d, 0x61, 0x74, 0x4d, 0x75,
            0x6c, 0x12, 0x10, 0x0a, 0x01, 0x41, 0x12, 0x09, 0x0a, 0x07, 0x08,
            0x01, 0x12, 0x03, 0x0a, 0x01, 0x02, 0x12, 0x03, 0x0a, 0x01, 0x03,
            0x12, 0x10, 0x0a, 0x01, 0x42, 0x12, 0x09, 0x0a, 0x07, 0x08, 0x01,
            0x12, 0x03, 0x0a, 0x01, 0x03, 0x12, 0x02, 0x0a, 0x02, 0x1a, 0x10,
            0x0a, 0x01, 0x43, 0x12, 0x09, 0x0a, 0x07, 0x08, 0x01, 0x12, 0x03,
            0x0a, 0x01, 0x02, 0x1a, 0x04, 0x74, 0x65, 0x73, 0x74, 0x1a, 0x02,
            0x08, 0x0d,
        ])

model_bytes = make_onnx_matmul()

# Print CPU/AVX info — oss-learn runs on CPU
import platform
cpu_info = ""
try:
    with open("/proc/cpuinfo") as f:
        for line in f:
            if "model name" in line:
                cpu_info = line.split(":")[1].strip()
                break
except Exception:
    cpu_info = platform.processor()
cpuinfo_text = ""
if platform.system() == "Linux":
    try:
        cpuinfo_text = open("/proc/cpuinfo").read()
    except Exception:
        pass
has_avx2   = "avx2"     in cpuinfo_text
has_avx512 = "avx512"   in cpuinfo_text
has_vnni   = "avx_vnni" in cpuinfo_text
print(f"  [ort] CPU: {cpu_info}", flush=True)
print(f"  [ort] AVX2={has_avx2}  AVX-512={has_avx512}  VNNI={has_vnni}", flush=True)
if has_vnni:
    print("  [ort]   VNNI detected — INT8 quantized models run ~2x faster on CPU", flush=True)
if has_avx2 and not has_avx512:
    print("  [ort]   AVX2 detected — float32 matrix ops are 8-wide vectorized on CPU", flush=True)
if has_avx512:
    print("  [ort]   AVX-512 detected — float32/16 throughput ~2x vs AVX2 on CPU", flush=True)

# ── CPU inference (mandatory — must pass for exit 0) ─────────────────────────
cpu_ok = False
try:
    sess_cpu = ort.InferenceSession(model_bytes, providers=["CPUExecutionProvider"])
    A = np.array([[1., 2., 3.], [4., 5., 6.]], dtype=np.float32)
    B = np.array([[7., 8.], [9., 10.], [11., 12.]], dtype=np.float32)
    result = sess_cpu.run(["C"], {"A": A, "B": B})[0]
    expected = A @ B
    if np.allclose(result, expected):
        print(f"  [ort] PASS: CPU inference correct. Output:\n{result}", flush=True)
        cpu_ok = True
    else:
        print(f"  [ort] FAIL: CPU inference wrong: {result} (expected {expected})", flush=True)
except Exception as e:
    print(f"  [ort] FAIL: CPU inference failed: {e}", flush=True)

if not cpu_ok:
    print("  [ort] FAIL: CPU inference broken — onnxruntime may be corrupt", flush=True)
    sys.exit(1)

print("  [ort] Verification complete (CPU-only).", flush=True)
PYEOF

  stamp "ort_verify"
  log_info "ONNX Runtime verification passed"
fi

# ── Step 5: Explicit test summary (per-test PASS/FAIL/SKIP) ─────────────────
# Runs the things downstream code depends on, prints a clear verdict per test,
# and returns a meaningful exit code:
#   exit 0 if CPU works
#   exit 1 if CPU import/inference is broken

log_step "Running explicit ONNX Runtime tests..."
TEST_OUTPUT=$("$PYTHON" - 2>/dev/null <<'PYEOF'
import sys, json

results = {}

# Test 1: import
try:
    import onnxruntime as ort
    results["import"] = {"status": "PASS", "detail": ort.__version__}
except Exception as e:
    print(json.dumps({"import": {"status": "FAIL", "detail": str(e)}}))
    sys.exit(1)

# Test 1b: variant (always CPU now)
results["variant"] = {"status": "PASS", "detail": "onnxruntime"}

# Test 2: providers
providers = ort.get_available_providers()
results["providers"] = {"status": "PASS", "detail": ",".join(providers)}

# Test 3: CPU inference
try:
    import numpy as np
    from onnx import helper, TensorProto
    a = helper.make_tensor_value_info("A", TensorProto.FLOAT, [2,3])
    b = helper.make_tensor_value_info("B", TensorProto.FLOAT, [3,2])
    out = helper.make_tensor_value_info("C", TensorProto.FLOAT, [2,2])
    g  = helper.make_graph([helper.make_node("MatMul",["A","B"],["C"])], "t", [a,b], [out])
    m  = helper.make_model(g, opset_imports=[helper.make_opsetid("",13)])
    model_bytes = m.SerializeToString()
    sess = ort.InferenceSession(model_bytes, providers=["CPUExecutionProvider"])
    A = np.array([[1.,2.,3.],[4.,5.,6.]], dtype=np.float32)
    B = np.array([[7.,8.],[9.,10.],[11.,12.]], dtype=np.float32)
    out = sess.run(["C"], {"A": A, "B": B})[0]
    if np.allclose(out, A @ B):
        results["cpu_inference"] = {"status": "PASS", "detail": "MatMul correct"}
    else:
        results["cpu_inference"] = {"status": "FAIL", "detail": "wrong output"}
except Exception as e:
    results["cpu_inference"] = {"status": "FAIL", "detail": str(e)[:80]}

print(json.dumps(results))
PYEOF
)
PY_RC=$?

# Pretty-print results
echo ""
echo "  ${C_BLU}--- ORT Test Results ---${C_RST}"
if [ -n "$TEST_OUTPUT" ]; then
  echo "$TEST_OUTPUT" | "$PYTHON" -c "
import json, sys
data = json.loads(sys.stdin.read())
for name, r in data.items():
    status = r['status']
    color = {'PASS':'\033[32m', 'FAIL':'\033[31m', 'SKIP':'\033[33m'}.get(status, '')
    reset = '\033[0m'
    print(f'  {color}{status:4}{reset}  {name:18}  {r[\"detail\"]}')
"
fi
echo ""

# Determine overall result from cpu_inference test
CPU_TEST=$(echo "$TEST_OUTPUT" | "$PYTHON" -c "
import json, sys
try: print(json.loads(sys.stdin.read()).get('cpu_inference', {}).get('status', 'FAIL'))
except: print('FAIL')
" 2>/dev/null)

if [ "$CPU_TEST" = "PASS" ]; then
  log_info "ONNX Runtime tests: CPU inference works — overall PASS"
  ORT_OVERALL=0
else
  log_error "ONNX Runtime tests: CPU inference FAILED — overall FAIL"
  ORT_OVERALL=1
fi

# ── Providers list for manifest ──────────────────────────────────────────────
ORT_PROVIDERS=$("$PYTHON" -c "
import onnxruntime as ort
print(','.join(ort.get_available_providers()))
" 2>/dev/null || echo "CPUExecutionProvider")

# ── Manifest ─────────────────────────────────────────────────────────────────
write_manifest onnxruntime \
  location=local \
  install_method="pip into shared venv" \
  venv="$REPO_ROOT/venv" \
  python="$PYTHON" \
  packages="$ORT_PACKAGE" \
  variant="$ORT_PACKAGE" \
  version="$(python_pkg_version onnxruntime)" \
  providers="$ORT_PROVIDERS"

# ── Summary ──────────────────────────────────────────────────────────────────
log_header "ONNX Runtime — Setup Complete"
echo "  Version  : $(python_pkg_version onnxruntime)"
echo "  Variant  : $ORT_PACKAGE"
echo "  Python   : $PYTHON"
echo ""
echo "  Providers available:"
"$PYTHON" -c "
import onnxruntime as ort
for p in ort.get_available_providers(): print('    -', p)
" 2>/dev/null || echo "    - CPUExecutionProvider"
echo ""
echo "  Usage example:"
echo "    import onnxruntime as ort"
echo "    sess = ort.InferenceSession('model.onnx', providers=['CPUExecutionProvider'])"
echo "    result = sess.run(None, {'input': data})"
echo ""
log_pass "ONNX Runtime $(python_pkg_version onnxruntime) (CPU)" \
  "pip install $ORT_PACKAGE into shared venv; build synthetic MatMul ONNX model; InferenceSession with CPUExecutionProvider; numeric check against numpy A@B" \
  "onnxruntime $(python_pkg_version onnxruntime) imported via $PYTHON; available providers: $ORT_PROVIDERS; MatMul([2,3]@[3,2]) on CPU matched np.allclose against expected A@B" \
  "venv=$REPO_ROOT/venv, python=$PYTHON, package=$ORT_PACKAGE, providers=$ORT_PROVIDERS, manifest=$MANIFEST_DIR/onnxruntime.yaml" \
  "bash scripts/setup/llama_cpp.sh"

# Exit code reflects the explicit-test verdict (0 if CPU works, 1 otherwise)
exit "${ORT_OVERALL:-0}"
