#!/bin/bash
# =============================================================================
# install.sh — Minikube + kubectl + Helm setup (Setup Phase Only)
#
# PURPOSE:
#   Installs the three tools needed to run a local multi-node k8s simulation:
#     1. minikube  — local k8s cluster (driver: docker)
#     2. kubectl   — k8s CLI
#     3. helm      — k8s package manager (for KEDA, NATS charts)
#
# WHAT IT DOES NOT:
#   - Does not start the cluster (that is scripts/start/minikube.sh)
#   - Does not install Docker (run scripts/setup/docker.sh first)
#
# USAGE:
#   bash scripts/setup/minikube.sh
#   bash scripts/setup/minikube.sh --force   # reinstall all
#   bash scripts/setup/minikube.sh --check   # check only
#
# EXIT CODES:
#   0 — all three tools installed
#   1 — install failed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/common.sh"
set_script_log "minikube_setup"

# ── Parse arguments ───────────────────────────────────────────────────────────
FORCE=0; CHECK_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --check) CHECK_ONLY=1 ;;
    --help)  echo "Usage: $0 [--force|--check]"; exit 0 ;;
    *)       log_warn "Unknown option: $1" ;;
  esac
  shift
done

is_wsl2 && log_info "Runtime: WSL2" || log_info "Runtime: Linux"

# ── Guard: Docker required ────────────────────────────────────────────────────
if ! command -v docker &>/dev/null || ! docker info &>/dev/null 2>&1; then
  log_error "Docker is required for minikube --driver=docker"
  log_error "  FIX: bash scripts/setup/docker.sh"
  exit 1
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  command -v minikube &>/dev/null && log_info "minikube: $(minikube version --short)" || log_warn "minikube: NOT installed"
  command -v kubectl  &>/dev/null && log_info "kubectl:  $(kubectl version --client --short 2>/dev/null || kubectl version --client)" || log_warn "kubectl:  NOT installed"
  command -v helm     &>/dev/null && log_info "helm:     $(helm version --short)" || log_warn "helm:     NOT installed"
  exit 0
fi

# ── minikube ──────────────────────────────────────────────────────────────────
if ! command -v minikube &>/dev/null || [ "$FORCE" -eq 1 ]; then
  log_header "Installing minikube"
  curl -fsSLo /tmp/minikube-linux-amd64 \
    https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  sudo install /tmp/minikube-linux-amd64 /usr/local/bin/minikube
  rm /tmp/minikube-linux-amd64
  log_info "minikube installed: $(minikube version --short)"
else
  log_info "minikube already installed: $(minikube version --short)"
fi

# ── kubectl ───────────────────────────────────────────────────────────────────
if ! command -v kubectl &>/dev/null || [ "$FORCE" -eq 1 ]; then
  log_header "Installing kubectl"
  K8S_STABLE=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
  curl -fsSLo /tmp/kubectl \
    "https://dl.k8s.io/release/${K8S_STABLE}/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm /tmp/kubectl
  log_info "kubectl installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
else
  log_info "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
fi

# ── Helm ──────────────────────────────────────────────────────────────────────
if ! command -v helm &>/dev/null || [ "$FORCE" -eq 1 ]; then
  log_header "Installing Helm"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  log_info "Helm installed: $(helm version --short)"
else
  log_info "Helm already installed: $(helm version --short)"
fi

# ── Verify ────────────────────────────────────────────────────────────────────
log_header "Verification"
FAIL=0
command -v minikube &>/dev/null && log_info "  minikube: $(minikube version --short)" || { log_error "  minikube: MISSING"; FAIL=1; }
command -v kubectl  &>/dev/null && log_info "  kubectl:  $(kubectl version --client --short 2>/dev/null || kubectl version --client)" || { log_error "  kubectl:  MISSING"; FAIL=1; }
command -v helm     &>/dev/null && log_info "  helm:     $(helm version --short)" || { log_error "  helm:     MISSING"; FAIL=1; }

[ "$FAIL" -eq 0 ] && log_info "Next step: bash scripts/start/minikube.sh"
exit $FAIL
