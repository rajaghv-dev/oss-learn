#!/bin/bash
# Validate k3s / kubectl installation and cluster health.
# USAGE: bash scripts/validate/k8s.sh [--dry-run]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/common.sh"
set_script_log "validate_k8s"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

log_info "Validating k8s (k3s)..."
is_wsl2 && log_info "  Runtime: WSL2" || log_info "  Runtime: Linux"

FAIL=0

# 1. k3s binary
if ! command -v k3s &>/dev/null; then
  log_error "k3s not found"
  log_error "  FIX: bash scripts/setup/k8s.sh"
  exit 1
fi
log_info "  k3s: $(k3s --version | head -1)"

# 2. kubectl (k3s ships its own; also accept standalone)
if command -v kubectl &>/dev/null; then
  KUBECTL="kubectl"
elif k3s kubectl version --client &>/dev/null 2>&1; then
  KUBECTL="k3s kubectl"
else
  log_warn "  kubectl not available (k3s kubectl also missing)"
  KUBECTL=""
  FAIL=1
fi

if [ -n "$KUBECTL" ]; then
  log_info "  kubectl: $($KUBECTL version --client --short 2>/dev/null || $KUBECTL version --client)"
fi

if [ "$DRY_RUN" -eq 1 ] || [ -z "$KUBECTL" ]; then
  log_info "  DRY-RUN or no kubectl: skipping cluster checks"
  [ "$FAIL" -eq 0 ] && log_info "RESULT: k8s validation PASSED (binary checks only)"
  exit $FAIL
fi

# 3. kubeconfig accessible
if [ ! -f ~/.kube/config ] && [ ! -f /etc/rancher/k3s/k3s.yaml ]; then
  log_warn "  kubeconfig not found at ~/.kube/config or /etc/rancher/k3s/k3s.yaml"
  log_warn "  FIX: sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config && chmod 600 ~/.kube/config"
  FAIL=1
fi

# 4. Node Ready
if $KUBECTL get nodes 2>/dev/null | grep -q "Ready"; then
  log_info "  Nodes:"
  $KUBECTL get nodes 2>/dev/null | sed 's/^/    /'
else
  log_warn "  No Ready nodes found"
  if is_wsl2 && ! has_systemd; then
    log_warn "  WSL2 fix: sudo k3s server --snapshotter=native &"
  else
    log_warn "  Fix: sudo systemctl start k3s"
  fi
  FAIL=1
fi

# 5. oss-learn namespace (optional — only if already deployed)
if $KUBECTL get namespace oss-learn &>/dev/null 2>&1; then
  RUNNING=$($KUBECTL get pods -n oss-learn --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | wc -l)
  TOTAL=$($KUBECTL get pods -n oss-learn --no-headers 2>/dev/null | wc -l)
  log_info "  oss-learn namespace: $RUNNING/$TOTAL pods Running"
fi

if [ "$FAIL" -eq 0 ]; then
  log_info "RESULT: k8s validation PASSED"
else
  log_warn "RESULT: k8s validation FAILED (see above)"
fi
exit $FAIL
