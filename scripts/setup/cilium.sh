#!/bin/bash
# =============================================================================
# install.sh — Cilium CLI + Hubble CLI installer (Setup Phase Only)
#
# PURPOSE:
#   Cilium replaces the default CNI (flannel/kindnet) in our k8s clusters
#   with eBPF-based networking, network policy, and observability via Hubble.
#   This script installs the two host-side CLIs needed to drive that:
#
#     - cilium  : install + manage Cilium itself (`cilium install`, status)
#     - hubble  : query the Cilium observability layer (flows, drops, TLS)
#
# WHAT THIS DOES NOT DO:
#   - Does not deploy Cilium into any cluster — that happens in
#     scripts/start/k8s.sh and scripts/start/minikube.sh, which call
#     `cilium install` against the live kubeconfig context.
#   - Does not install Docker, kubectl, or Helm — those have their own
#     setup scripts.
#
# USAGE:
#   bash scripts/setup/cilium.sh
#   bash scripts/setup/cilium.sh --force   # reinstall both CLIs
#   bash scripts/setup/cilium.sh --check   # check only
#
# EXIT CODES:
#   0 — both CLIs installed (or already present)
#   1 — install failed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/common.sh"
set_script_log "cilium_setup"

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

# Pinned versions — bump after testing. Both are signed releases on GitHub.
CILIUM_CLI_VERSION="${CILIUM_CLI_VERSION:-v0.16.18}"
HUBBLE_CLI_VERSION="${HUBBLE_CLI_VERSION:-v1.16.5}"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  GOARCH=amd64 ;;
  aarch64) GOARCH=arm64 ;;
  *) log_error "Unsupported arch: $ARCH"; exit 1 ;;
esac

# ── Check mode ────────────────────────────────────────────────────────────────
if [ "$CHECK_ONLY" -eq 1 ]; then
  command -v cilium &>/dev/null && log_info "cilium: $(cilium version --client 2>/dev/null | head -1)" || log_warn "cilium: NOT installed"
  command -v hubble &>/dev/null && log_info "hubble: $(hubble version 2>/dev/null | head -1)" || log_warn "hubble: NOT installed"
  exit 0
fi

# ── cilium CLI ────────────────────────────────────────────────────────────────
if ! command -v cilium &>/dev/null || [ "$FORCE" -eq 1 ]; then
  log_header "Installing cilium CLI ($CILIUM_CLI_VERSION)"
  TARBALL="cilium-linux-${GOARCH}.tar.gz"
  URL="https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/${TARBALL}"
  log_info "URL: $URL"
  curl -fsSL --retry 3 -o "/tmp/${TARBALL}" "$URL"
  curl -fsSL --retry 3 -o "/tmp/${TARBALL}.sha256sum" "${URL}.sha256sum"
  ( cd /tmp && sha256sum --check "${TARBALL}.sha256sum" )
  sudo tar xzf "/tmp/${TARBALL}" -C /usr/local/bin
  rm -f "/tmp/${TARBALL}" "/tmp/${TARBALL}.sha256sum"
  log_info "cilium installed: $(cilium version --client | head -1)"
else
  log_info "cilium already installed: $(cilium version --client | head -1)"
fi

# ── hubble CLI ────────────────────────────────────────────────────────────────
if ! command -v hubble &>/dev/null || [ "$FORCE" -eq 1 ]; then
  log_header "Installing hubble CLI ($HUBBLE_CLI_VERSION)"
  TARBALL="hubble-linux-${GOARCH}.tar.gz"
  URL="https://github.com/cilium/hubble/releases/download/${HUBBLE_CLI_VERSION}/${TARBALL}"
  log_info "URL: $URL"
  curl -fsSL --retry 3 -o "/tmp/${TARBALL}" "$URL"
  curl -fsSL --retry 3 -o "/tmp/${TARBALL}.sha256sum" "${URL}.sha256sum"
  ( cd /tmp && sha256sum --check "${TARBALL}.sha256sum" )
  sudo tar xzf "/tmp/${TARBALL}" -C /usr/local/bin
  rm -f "/tmp/${TARBALL}" "/tmp/${TARBALL}.sha256sum"
  log_info "hubble installed: $(hubble version | head -1)"
else
  log_info "hubble already installed: $(hubble version | head -1)"
fi

# ── Verify ────────────────────────────────────────────────────────────────────
log_header "Verification"
FAIL=0
command -v cilium &>/dev/null && log_info "  cilium: $(cilium version --client | head -1)" || { log_error "  cilium: MISSING"; FAIL=1; }
command -v hubble &>/dev/null && log_info "  hubble: $(hubble version | head -1)" || { log_error "  hubble: MISSING"; FAIL=1; }

[ "$FAIL" -eq 0 ] && log_info "Cilium CLI ready. Cluster install happens in scripts/start/{k8s,minikube}.sh"
exit $FAIL
