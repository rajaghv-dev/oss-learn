#!/bin/bash
# =============================================================================
# minikube.sh — Start a local minikube cluster for learning Kubernetes
#
# PURPOSE:
#   Starts a single-node minikube profile called 'oss-learn' and creates the
#   'oss-learn' namespace. No application-specific deployments.
#
# USAGE:
#   bash scripts/start/minikube.sh
#   bash scripts/start/minikube.sh --dry-run
#
# PREREQUISITES:
#   bash scripts/setup/minikube.sh   (installs minikube + kubectl)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/common.sh"
set_script_log "minikube_up"

DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --help)    grep '^#   ' "$0" | sed 's/^#   //'; exit 0 ;;
    *)         log_warn "Unknown flag: $1" ;;
  esac
  shift
done

PROFILE="oss-learn"
NS="oss-learn"

command -v minikube &>/dev/null || {
  log_error "minikube not found — run: bash scripts/setup/minikube.sh"
  exit 1
}
command -v kubectl &>/dev/null || {
  log_error "kubectl not found — run: bash scripts/setup/minikube.sh"
  exit 1
}

log_header "minikube Cluster Startup (profile=$PROFILE)"

if [ "$DRY_RUN" -eq 1 ]; then
  log_info "[dry-run] would start minikube profile=$PROFILE and create namespace $NS"
  exit 0
fi

# ── Start cluster ─────────────────────────────────────────────────────────────
if minikube status -p "$PROFILE" 2>/dev/null | grep -q "host: Running"; then
  log_info "minikube profile '$PROFILE' is already running"
else
  log_step "Starting minikube profile=$PROFILE..."
  minikube start -p "$PROFILE" --driver=docker --cpus=2 --memory=4096
fi

# ── Set kubectl context ───────────────────────────────────────────────────────
kubectl config use-context "$PROFILE" >/dev/null

# ── Create namespace ──────────────────────────────────────────────────────────
if ! kubectl get namespace "$NS" &>/dev/null; then
  log_step "Creating namespace $NS..."
  kubectl create namespace "$NS"
else
  log_info "Namespace $NS already exists"
fi

log_pass "minikube cluster is up" \
  "minikube status reports host: Running; kubectl context=$PROFILE; namespace $NS present" \
  "cluster ready for kubectl experiments" \
  "profile=$PROFILE, namespace=$NS, driver=docker" \
  "kubectl get nodes  |  minikube dashboard -p $PROFILE  |  minikube stop -p $PROFILE"
