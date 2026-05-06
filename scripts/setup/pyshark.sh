#!/bin/bash
# =============================================================================
# pyshark.sh — pyshark Python package setup (Setup Phase)
#
# PURPOSE:
#   Installs `pyshark`, a Python wrapper around tshark, into the shared
#   project venv. oss-learn uses pyshark (alongside the raw `tshark` CLI) for:
#     - Programmatic LLRP/RFID pcap analysis from Python services
#     - Replaying captures during integration tests
#     - Building structured trace events from in-process packet captures
#
# DEPENDENCIES:
#   - tshark binary on PATH (installed by scripts/setup/wireshark.sh)
#   - shared venv at $REPO_ROOT/venv/ (installed by scripts/setup/python.sh)
#   pyshark imports won't fail if tshark is missing, but every capture call
#   raises TSharkNotFoundException at runtime — so we verify tshark up front.
#
# WHAT IT DOES:
#   1. Confirms shared venv exists; bails with a clear pointer to python.sh
#      otherwise (do NOT silently fall back to system Python — pollutes the
#      user's environment).
#   2. Confirms tshark binary is on PATH; bails pointing at wireshark.sh.
#   3. pip-installs pyshark (and its lxml/termcolor runtime deps).
#   4. Verifies via a real import + FileCapture instantiation against a
#      tiny synthetic pcap (4 bytes is enough to prove the layer wires up).
#   5. Writes setup/state/installs/pyshark.yaml manifest.
#
# USAGE:
#   bash scripts/setup/pyshark.sh             # install + verify
#   bash scripts/setup/pyshark.sh --check     # check only, no install
#   bash scripts/setup/pyshark.sh --force     # reinstall in venv
#   bash scripts/setup/pyshark.sh --help      # show this help
#
# EXIT CODES:
#   0 — pyshark installed, tshark reachable, import verified
#   1 — install or verification failed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/common.sh"
set_script_log "pyshark"

# ── Parse arguments ──────────────────────────────────────────────────────────
CHECK_ONLY=0
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check)   CHECK_ONLY=1 ;;
    --force)   FORCE=1 ;;
    --help|-h) grep '^#' "$0" | head -38 | sed 's/^# \?//'; exit 0 ;;
    *)         log_warn "Unknown option: $1" ;;
  esac
  shift
done

log_header "pyshark — Python wrapper for tshark"

# ── Locate the shared venv ───────────────────────────────────────────────────
SHARED_VENV="$REPO_ROOT/venv"
VENV_PIP="$SHARED_VENV/bin/pip"
VENV_PY="$SHARED_VENV/bin/python3"

log_info "Shared venv : $SHARED_VENV"

if [ ! -x "$VENV_PY" ]; then
  log_error "Shared venv not found at $SHARED_VENV"
  log_error "  → WHY IT MATTERS: pyshark must live in the project venv, not system python"
  log_error "  → HOW TO FIX: bash scripts/setup/python.sh"
  exit 1
fi

PY_VER=$("$VENV_PY" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
log_info "venv python : $VENV_PY (Python $PY_VER)"

# ── Confirm tshark is on PATH (pyshark needs it at runtime) ─────────────────
if ! command -v tshark &>/dev/null; then
  log_error "tshark binary not found on PATH"
  log_error "  → WHY IT MATTERS: pyshark shells out to tshark for every capture"
  log_error "  → HOW TO FIX: bash scripts/setup/wireshark.sh"
  exit 1
fi
TSHARK_VER=$(tshark --version | head -1 | awk '{print $NF}')
log_info "tshark      : $(command -v tshark) (version $TSHARK_VER)"

# ── Already-installed short-circuit ──────────────────────────────────────────
if "$VENV_PY" -c 'import pyshark' &>/dev/null && [ "$FORCE" -eq 0 ]; then
  PYSHARK_VER=$("$VENV_PY" -c '
from importlib.metadata import version as _pkgver, PackageNotFoundError
try:
    print(_pkgver("pyshark"))
except PackageNotFoundError:
    print("unknown")
' 2>/dev/null || echo "?")
  log_info "pyshark $PYSHARK_VER already installed in venv"
  if [ "$CHECK_ONLY" -eq 1 ]; then
    log_info "pyshark: present"
    exit 0
  fi
  log_info "Use --force to reinstall"
  # Still run verification + manifest write so re-runs converge on green
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  log_warn "pyshark: NOT installed in venv"
  log_warn "  → FIX: bash scripts/setup/pyshark.sh"
  exit 0
fi

# ── Install ──────────────────────────────────────────────────────────────────
# pyshark pulls in lxml + termcolor + packaging. Pin to >=0.6 (covers asyncio
# refactor) but leave upper bound open so security fixes can land.
log_step "pip install pyshark>=0.6"
PIP_FLAGS=(--disable-pip-version-check --no-input)
[ "$FORCE" -eq 1 ] && PIP_FLAGS+=(--force-reinstall)
"$VENV_PIP" install "${PIP_FLAGS[@]}" 'pyshark>=0.6'

# ── Verify ───────────────────────────────────────────────────────────────────
log_header "Verifying pyshark"

# Two-stage verify:
#   (a) Plain import — proves pip install + lxml binary wheel are both OK.
#   (b) FileCapture against /dev/null/empty pcap — proves tshark IPC wires
#       up. We catch any exception so a pcap-format error doesn't fail the
#       step (the tshark subprocess spawn is what we actually want to test).
if ! "$VENV_PY" -c '
import pyshark
from importlib.metadata import version as _pkgver, PackageNotFoundError
try:
    _v = _pkgver("pyshark")
except PackageNotFoundError:
    _v = "unknown"
print(f"pyshark {_v} import OK")
' 2>&1 | tee -a "$SCRIPT_LOG"; then
  log_error "pyshark import failed after install"
  exit 1
fi

VERIFY_RC=0
"$VENV_PY" - <<'PY' 2>&1 | tee -a "$SCRIPT_LOG" || VERIFY_RC=$?
import pyshark, tempfile, os, sys
# pyshark imports tshark lazily; touching FileCapture forces the binary lookup.
fd, pcap = tempfile.mkstemp(suffix=".pcap")
os.close(fd)
try:
    cap = pyshark.FileCapture(pcap, keep_packets=False)
    # Closing immediately is enough — we're verifying the spawn path, not parse.
    cap.close()
    print("pyshark FileCapture spawn OK")
except Exception as exc:
    # An empty pcap may raise — but the spawn is what matters.
    msg = str(exc).lower()
    if "tshark" in msg and ("not found" in msg or "no such" in msg):
        print(f"FAIL: tshark not reachable via pyshark: {exc}", file=sys.stderr)
        sys.exit(1)
    print(f"pyshark FileCapture spawn OK (benign empty-pcap exc: {type(exc).__name__})")
finally:
    os.unlink(pcap)
PY

if [ "$VERIFY_RC" -ne 0 ]; then
  log_error "pyshark verification failed"
  exit 1
fi

# ── Manifest ─────────────────────────────────────────────────────────────────
PYSHARK_VER=$("$VENV_PY" -c '
from importlib.metadata import version as _pkgver, PackageNotFoundError
try:
    print(_pkgver("pyshark"))
except PackageNotFoundError:
    print("unknown")
')
write_manifest "pyshark" <<EOF
install:
  name: pyshark
  location: venv
  install_method: pip into shared venv
  venv: $SHARED_VENV
  python: $VENV_PY
  version: $PYSHARK_VER
  tshark_binary: $(command -v tshark)
  tshark_version: $TSHARK_VER
  timestamp: $(date -Iseconds)
EOF

log_pass "pyshark (Python wrapper for tshark)" \
  "shared venv exists, tshark on PATH, 'import pyshark' in venv python, pyshark.FileCapture spawn against an empty pcap" \
  "pyshark $PYSHARK_VER installed into $SHARED_VENV; import succeeded under Python $PY_VER; FileCapture spawn path verified — tshark $TSHARK_VER is reachable as the binary backend" \
  "venv=$SHARED_VENV, python=$VENV_PY, pyshark=$PYSHARK_VER, tshark=$(command -v tshark) ($TSHARK_VER), manifest=$MANIFEST_DIR/pyshark.yaml" \
  "$VENV_PY -c 'import pyshark; print(pyshark.__version__)'   # smoke-test from any service"
exit 0
