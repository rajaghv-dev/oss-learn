#!/bin/bash
# =============================================================================
# k8s.sh — Ensure k3s cluster is up and reachable
#
# PURPOSE:
#   Starts the k3s service (or confirms it is already running) and creates
#   the 'oss-learn' namespace for experimentation. No application-specific
#   deployments — this is a learning environment.
#
# USAGE:
#   bash scripts/start/k8s.sh
#   bash scripts/start/k8s.sh --dry-run
#
# PREREQUISITES:
#   bash scripts/setup/k8s.sh   (installs k3s + kubectl + helm)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/common.sh"
set_script_log "k8s_up"

DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --help)    grep '^#   ' "$0" | sed 's/^#   //'; exit 0 ;;
    *)         log_warn "Unknown flag: $1" ;;
  esac
  shift
done

if ! command -v k3s &>/dev/null && ! command -v kubectl &>/dev/null; then
  log_error "Neither k3s nor kubectl found — run: bash scripts/setup/k8s.sh"
  exit 1
fi

log_header "k3s Cluster Startup"

if [ "$DRY_RUN" -eq 1 ]; then
  log_info "[dry-run] would start k3s and create namespace oss-learn"
  exit 0
fi

# ── Start k3s service ────────────────────────────────────────────────────────
if has_systemd; then
  if ! systemctl is-active --quiet k3s 2>/dev/null; then
    log_step "Starting k3s service..."
    sudo systemctl start k3s 2>/dev/null || log_warn "Could not start k3s via systemd"
  else
    log_info "k3s service is already running"
  fi
else
  log_warn "systemd not detected (WSL2?) — start k3s manually if needed:"
  log_warn "  sudo k3s server &"
fi

# ── Wait for cluster to be reachable ──────────────────────────────────────────
KUBECTL="${KUBECTL:-kubectl}"
attempts=0
until $KUBECTL get nodes &>/dev/null; do
  ((attempts++))
  [ $attempts -gt 30 ] && { log_error "k3s API not reachable after 30s"; exit 1; }
  sleep 1
done
log_info "k3s API reachable"

# ── Create namespace if missing ───────────────────────────────────────────────
NS="oss-learn"
if ! $KUBECTL get namespace "$NS" &>/dev/null; then
  log_step "Creating namespace $NS..."
  $KUBECTL create namespace "$NS"
else
  log_info "Namespace $NS already exists"
fi

log_pass "k3s cluster is up" \
  "kubectl get nodes returned successfully; namespace $NS present" \
  "cluster ready for experimentation" \
  "namespace=$NS, kubectl context=$($KUBECTL config current-context 2>/dev/null || echo 'default')" \
  "kubectl get nodes  |  kubectl get pods -A"
