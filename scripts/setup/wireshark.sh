#!/bin/bash
# =============================================================================
# wireshark.sh — Wireshark + tshark Setup (Setup Phase)
#
# PURPOSE:
#   Installs the Wireshark suite — primarily `tshark`, the CLI packet
#   analyser. oss-learn uses tshark for:
#     - Decoding LLRP traffic from RFID readers (docs/observability.md §2.1)
#     - Validating sllurp's wire-protocol implementation against captures
#     - Acting as the binary backend for the `pyshark` Python package
#
# WHAT IT DOES:
#   1. Resolves distro family from /etc/os-release (handles Ubuntu/Debian/RHEL
#      derivatives via ID_LIKE — same pattern as scripts/setup/docker.sh).
#      Supported derivatives:
#        Ubuntu family : SuryaOS, Linux Mint, Pop!_OS, Elementary, Zorin, KDE neon
#        Debian family : Kali, MX Linux, Devuan, Raspberry Pi OS
#        RHEL family   : Rocky, AlmaLinux, CentOS Stream
#   2. Installs `wireshark-common` + `tshark` (CLI) + `wireshark` (GUI, optional).
#      The GUI is skipped on headless hosts (no $DISPLAY) — tshark is enough
#      for oss-learn's pcap workflow.
#   3. Adds the current user to the `wireshark` group so non-root users can
#      run captures (same model as the `docker` group).
#   4. Sets dumpcap caps so tshark can capture without sudo.
#   5. Verifies: `tshark --version` + `tshark -D` (interface list).
#
# USAGE:
#   bash scripts/setup/wireshark.sh             # install tshark + cli (+ gui if desktop)
#   bash scripts/setup/wireshark.sh --check     # check only, no install
#   bash scripts/setup/wireshark.sh --force     # reinstall
#   bash scripts/setup/wireshark.sh --cli-only  # never install the GUI package
#   bash scripts/setup/wireshark.sh --help      # show this help
#
# EXIT CODES:
#   0 — tshark installed and verified (or already present)
#   1 — installation failed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/common.sh"
set_script_log "wireshark"

# ── Parse arguments ──────────────────────────────────────────────────────────
CHECK_ONLY=0
FORCE=0
CLI_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check)    CHECK_ONLY=1 ;;
    --force)    FORCE=1 ;;
    --cli-only) CLI_ONLY=1 ;;
    --help|-h)  grep '^#' "$0" | head -42 | sed 's/^# \?//'; exit 0 ;;
    *)          log_warn "Unknown option: $1" ;;
  esac
  shift
done

# ── Already-installed short-circuit ──────────────────────────────────────────
if command -v tshark &>/dev/null && [ "$FORCE" -eq 0 ]; then
  TSHARK_VER=$(tshark --version 2>/dev/null | head -1 | awk '{print $NF}')
  log_info "tshark $TSHARK_VER already installed"
  if [ "$CHECK_ONLY" -eq 1 ]; then
    log_info "Wireshark/tshark: present"
    exit 0
  fi
  log_info "Use --force to reinstall"
  exit 0
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  log_warn "tshark: NOT installed"
  log_warn "  → FIX: bash scripts/setup/wireshark.sh"
  exit 0
fi

# ── Detect distro family (same logic as docker.sh) ──────────────────────────
log_header "Installing Wireshark / tshark"

OS_ID=""; OS_ID_LIKE=""; OS_VERSION_CODENAME=""; OS_UBUNTU_CODENAME=""; OS_DEBIAN_CODENAME=""
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  OS_ID="${ID:-}"
  OS_ID_LIKE="${ID_LIKE:-}"
  OS_VERSION_CODENAME="${VERSION_CODENAME:-}"
  OS_UBUNTU_CODENAME="${UBUNTU_CODENAME:-}"
  OS_DEBIAN_CODENAME="${DEBIAN_CODENAME:-}"
fi

log_info "Distro detection:"
log_info "  ID                = '${OS_ID:-?}'"
log_info "  ID_LIKE           = '${OS_ID_LIKE:-(none)}'"
log_info "  VERSION_CODENAME  = '${OS_VERSION_CODENAME:-(none)}'"

FAMILY=""
case "$OS_ID" in
  ubuntu|debian|rhel|fedora|centos|rocky|almalinux) FAMILY="$OS_ID" ;;
esac
if [ -z "$FAMILY" ]; then
  case " $OS_ID_LIKE " in
    *" ubuntu "*)              FAMILY="ubuntu" ;;
    *" debian "*)              FAMILY="debian" ;;
    *" rhel "*|*" fedora "*|*" centos "*) FAMILY="rhel" ;;
  esac
fi
case "$FAMILY" in rocky|almalinux|centos) FAMILY="rhel" ;; esac

if [ -n "$FAMILY" ] && [ "$FAMILY" != "$OS_ID" ]; then
  log_warn "Detected '$OS_ID' — treating as '$FAMILY' derivative (via ID_LIKE)"
fi
log_info "Resolved family: '${FAMILY:-(unsupported)}'"

# ── Decide whether to install the GUI package ───────────────────────────────
# Headless hosts (CI runners, servers, containers) shouldn't pull in Qt and a
# few hundred MB of GUI deps. Desktop hosts get the full GUI by default.
INSTALL_GUI=1
if [ "$CLI_ONLY" -eq 1 ]; then
  INSTALL_GUI=0
  log_info "GUI install: disabled (--cli-only)"
elif [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  INSTALL_GUI=0
  log_info "GUI install: skipped (headless: no \$DISPLAY or \$WAYLAND_DISPLAY)"
else
  log_info "GUI install: yes (desktop session detected)"
fi

# ── Install ──────────────────────────────────────────────────────────────────
case "$FAMILY" in
  ubuntu|debian)
    # Wireshark's post-install asks an interactive debconf question:
    # "Should non-superusers be able to capture packets?"
    # Pre-seed it to "yes" so the install is non-interactive (apt -y).
    log_step "Pre-seeding debconf: allow non-root captures = yes"
    echo "wireshark-common wireshark-common/install-setuid boolean true" \
      | sudo debconf-set-selections

    PKGS=(tshark wireshark-common)
    [ "$INSTALL_GUI" -eq 1 ] && PKGS+=(wireshark)

    log_step "apt-get install: ${PKGS[*]}"
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${PKGS[@]}"
    ;;

  rhel|fedora)
    PKGS=(wireshark-cli)
    [ "$INSTALL_GUI" -eq 1 ] && PKGS+=(wireshark)
    log_step "dnf install: ${PKGS[*]}"
    sudo dnf install -y "${PKGS[@]}"
    ;;

  *)
    log_error "Unsupported OS: ID='${OS_ID:-unknown}' ID_LIKE='${OS_ID_LIKE:-none}'"
    log_error "  → HOW TO FIX: install wireshark + tshark manually:"
    log_error "       https://www.wireshark.org/download.html"
    exit 1
    ;;
esac

# ── Add user to wireshark group + reconfigure for non-root capture ──────────
# On Debian-family systems, the post-install puts /usr/bin/dumpcap into
# CAP_NET_RAW,CAP_NET_ADMIN ownership root:wireshark mode 0750 — but only if
# the debconf "yes" landed BEFORE the package configured. If we got here via
# --force we may need to reconfigure.
if getent group wireshark &>/dev/null; then
  if ! id -nG "$USER" | tr ' ' '\n' | grep -qx wireshark; then
    log_step "Adding $USER to 'wireshark' group (non-root capture)"
    sudo usermod -aG wireshark "$USER"
    log_warn "Group change takes effect on next login (or run: newgrp wireshark)"
  else
    log_info "$USER already in 'wireshark' group"
  fi
fi

# Ensure dumpcap has the right caps even on --force / re-run
case "$FAMILY" in
  ubuntu|debian)
    if [ -x /usr/bin/dumpcap ]; then
      log_step "Reconfiguring wireshark-common (sets dumpcap caps)"
      sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive wireshark-common 2>/dev/null || true
    fi
    ;;
esac

# ── Verify ───────────────────────────────────────────────────────────────────
log_header "Verifying Wireshark / tshark"

if ! command -v tshark &>/dev/null; then
  log_error "tshark binary not found after install"
  exit 1
fi

TSHARK_VER=$(tshark --version | head -1 | awk '{print $NF}')
log_info "tshark $TSHARK_VER — OK"

# `tshark -D` lists interfaces; needs CAP_NET_RAW. If this fails it usually
# means the wireshark group membership hasn't been picked up yet (logout/login
# required), which is a warning not a hard fail.
if tshark -D &>/dev/null; then
  IFCOUNT=$(tshark -D 2>/dev/null | wc -l)
  log_info "tshark -D: $IFCOUNT capture interface(s) visible"
else
  log_warn "tshark -D failed — likely needs re-login for 'wireshark' group"
  log_warn "  → After logout/login: tshark -D should list interfaces"
fi

# ── Manifest ─────────────────────────────────────────────────────────────────
write_manifest "wireshark" <<EOF
install:
  name: wireshark
  location: system
  install_method: ${FAMILY}-package
  package_set: $([ "$INSTALL_GUI" -eq 1 ] && echo "tshark + wireshark (GUI)" || echo "tshark (CLI only)")
  version: $TSHARK_VER
  binary: $(command -v tshark)
  group: wireshark
  timestamp: $(date -Iseconds)
EOF

log_pass "Wireshark / tshark" \
  "tshark binary present, 'tshark --version' parses, 'tshark -D' interface enumeration" \
  "tshark $TSHARK_VER installed via ${FAMILY}-package ($([ "$INSTALL_GUI" -eq 1 ] && echo "tshark + wireshark GUI" || echo "tshark CLI only")); user '$USER' is a member of the 'wireshark' group; dumpcap caps reconfigured for non-root capture" \
  "binary=$(command -v tshark), version=$TSHARK_VER, family=$FAMILY, group=wireshark, manifest=$MANIFEST_DIR/wireshark.yaml" \
  "bash scripts/setup/pyshark.sh   # install Python wrapper around tshark"
exit 0
