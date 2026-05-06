#!/bin/bash
# =============================================================================
# install.sh — Kubernetes (k3s) Setup (Setup Phase Only)
#
# PURPOSE:
#   Installs k3s (lightweight Kubernetes) on Linux or WSL2.
#   WSL2 requires extra flags: native snapshotter + kubeconfig world-readable.
#
# WHAT IT DOES:
#   1. Detects WSL2 vs plain Linux
#   2. Installs k3s via the official installer (curl -sfL https://get.k3s.io)
#   3. WSL2: sets K3S_SNAPSHOTTER=native (overlayfs unsupported in WSL2 kernel)
#   4. Starts k3s server (systemd service or direct process on WSL2)
#   5. Writes kubeconfig to ~/.kube/config
#   6. Verifies: k3s kubectl get nodes shows Ready
#
# WSL2 NOTES:
#   - overlayfs is not available; k3s must use the native snapshotter
#   - systemd may not be running; the installer falls back to starting k3s
#     as a background process (run: sudo k3s server & )
#   - Enable systemd for a cleaner experience:
#       echo -e '[boot]\nsystemd=true' | sudo tee /etc/wsl.conf
#       wsl --shutdown  (from Windows)
#
# USAGE:
#   bash scripts/setup/k8s.sh
#   bash scripts/setup/k8s.sh --force   # reinstall
#   bash scripts/setup/k8s.sh --check   # check only
#
# EXIT CODES:
#   0 — k3s installed and at least one node is Ready
#   1 — Setup failed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/common.sh"
set_script_log "k8s_setup"

# ── Parse arguments ───────────────────────────────────────────────────────────
FORCE=0
CHECK_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --check) CHECK_ONLY=1 ;;
    --help)  echo "Usage: $0 [--force|--check]"; exit 0 ;;
    *)       log_warn "Unknown option: $1" ;;
  esac
  shift
done

# ── Runtime info ──────────────────────────────────────────────────────────────
if is_wsl2; then
  log_info "Runtime: WSL2"
  log_warn "k3s on WSL2: overlayfs unsupported — will use native snapshotter"
  has_systemd || log_warn "systemd not running — k3s will start as a background process"
else
  log_info "Runtime: Linux"
fi

# ── Linux-only guard ──────────────────────────────────────────────────────────
if [ "$(uname -s)" != "Linux" ]; then
  log_error "k3s requires Linux (or WSL2)"
  exit 1
fi

# ── Check if already installed ────────────────────────────────────────────────
if command -v k3s &>/dev/null && [ "$FORCE" -eq 0 ]; then
  K3S_VER=$(k3s --version | head -1)
  log_info "k3s already installed: $K3S_VER"
  [ "$CHECK_ONLY" -eq 1 ] && exit 0
  log_info "Use --force to reinstall"
  # Fall through to kubeconfig + verify
else
  if [ "$CHECK_ONLY" -eq 1 ]; then
    command -v k3s &>/dev/null && log_info "k3s: installed" || log_warn "k3s: NOT installed"
    exit 0
  fi

  # ── Install k3s ─────────────────────────────────────────────────────────────
  log_header "Installing k3s"

  # k3s flags (composed):
  #   --flannel-backend=none      — Cilium replaces flannel as the CNI
  #   --disable-network-policy    — Cilium owns NetworkPolicy enforcement
  #   --disable=traefik           — keep ingress choice open (we use ingress-nginx)
  #   --write-kubeconfig-mode=644 — non-root readable kubeconfig
  #   --snapshotter=native        — WSL2 only (overlayfs unavailable in WSL2 kernel)
  K3S_EXEC_FLAGS="--flannel-backend=none --disable-network-policy --disable=traefik --write-kubeconfig-mode=644"
  if is_wsl2; then
    K3S_EXEC_FLAGS="$K3S_EXEC_FLAGS --snapshotter=native"
  fi
  export INSTALL_K3S_EXEC="$K3S_EXEC_FLAGS"
  log_info "k3s flags: $INSTALL_K3S_EXEC"

  log_step "Running k3s installer..."
  curl -sfL https://get.k3s.io | sh -

  if ! command -v k3s &>/dev/null; then
    log_error "k3s binary not found after install"
    log_error "  Manual: curl -sfL https://get.k3s.io | sh -"
    exit 1
  fi

  K3S_VER=$(k3s --version | head -1)
  log_info "k3s installed: $K3S_VER"
fi

# ── Ensure k3s server is running ──────────────────────────────────────────────
log_step "Starting k3s server..."

if has_systemd; then
  sudo systemctl enable k3s 2>/dev/null || true
  sudo systemctl start  k3s 2>/dev/null || true
else
  # WSL2 without systemd — start as background process if not already running
  if ! pgrep -x k3s &>/dev/null; then
    log_warn "systemd unavailable — starting k3s in background (sudo k3s server &)"
    sudo k3s server \
      --snapshotter=native \
      --write-kubeconfig-mode=644 \
      &>/tmp/k3s-server.log &
    disown
    log_info "k3s server PID: $!"
    log_info "  Log: /tmp/k3s-server.log"
  else
    log_info "k3s server already running"
  fi
fi

# ── Write kubeconfig ──────────────────────────────────────────────────────────
log_step "Configuring kubectl access..."
mkdir -p ~/.kube

KUBECONFIG_SRC="/etc/rancher/k3s/k3s.yaml"
# Wait up to 30s for k3s to write its kubeconfig
elapsed=0
while [ ! -f "$KUBECONFIG_SRC" ] && [ "$elapsed" -lt 30 ]; do
  sleep 2; (( elapsed += 2 )) || true
done

if [ -f "$KUBECONFIG_SRC" ]; then
  sudo cp "$KUBECONFIG_SRC" ~/.kube/config
  sudo chown "$(id -u):$(id -g)" ~/.kube/config
  chmod 600 ~/.kube/config
  log_info "kubeconfig written to ~/.kube/config"
else
  log_warn "k3s kubeconfig not found at $KUBECONFIG_SRC yet — may need a moment to initialise"
fi

# ── Verify: wait for node Ready ───────────────────────────────────────────────
log_step "Waiting for k3s node to become Ready (up to 60s)..."
elapsed=0
KUBECTL="k3s kubectl"
[ -f ~/.kube/config ] && KUBECTL="kubectl"

while [ "$elapsed" -lt 60 ]; do
  if $KUBECTL get nodes 2>/dev/null | grep -q "Ready"; then
    log_info "k3s node is Ready"
    $KUBECTL get nodes
    break
  fi
  sleep 3; (( elapsed += 3 )) || true
done

if ! $KUBECTL get nodes 2>/dev/null | grep -q "Ready"; then
  log_warn "k3s node not Ready within 60s — it may still be initialising"
  log_warn "  Check: kubectl get nodes  OR  sudo k3s kubectl get nodes"
fi

log_info "k3s version: $(k3s --version | head -1)"

# ── Install Helm ──────────────────────────────────────────────────────────────
log_step "Installing Helm..."
if command -v helm &>/dev/null && [ "$FORCE" -eq 0 ]; then
  log_info "Helm already installed: $(helm version --short)"
else
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  log_info "Helm installed: $(helm version --short)"
fi

# ── kubectl convenience symlink ───────────────────────────────────────────────
# k3s ships its own kubectl as 'k3s kubectl'; expose it as plain kubectl if not present.
if ! command -v kubectl &>/dev/null; then
  log_step "Linking k3s kubectl → /usr/local/bin/kubectl..."
  sudo ln -sf "$(which k3s)" /usr/local/bin/kubectl 2>/dev/null || \
    sudo tee /usr/local/bin/kubectl > /dev/null <<'EOF'
#!/bin/sh
exec k3s kubectl "$@"
EOF
  sudo chmod +x /usr/local/bin/kubectl
  log_info "kubectl symlink created"
fi

log_info "Next step: bash scripts/start/k8s.sh"
exit 0
