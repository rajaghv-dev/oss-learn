#!/bin/bash
# =============================================================================
# install.sh — Docker Installation Script (Setup Phase Only)
#
# PURPOSE:
#   Installs Docker Engine and Docker Compose v2 plugin.
#   Handles plain Linux and WSL2 (Docker Desktop integration or native engine).
#
# WHAT IT DOES:
#   1. Detects WSL2 vs plain Linux
#   2. WSL2 + Docker Desktop active  → skips install (already available)
#   3. Resolves the distro family (ubuntu/debian/rhel/fedora) from /etc/os-release.
#      Reads ID first, then ID_LIKE so Ubuntu/Debian/RHEL DERIVATIVES work too:
#        Ubuntu family : SuryaOS, Linux Mint, Pop!_OS, Elementary, Zorin, KDE neon
#        Debian family : Kali, MX Linux, Devuan, Raspberry Pi OS
#        RHEL family   : Rocky, AlmaLinux, CentOS Stream
#      For derivatives, picks UBUNTU_CODENAME / DEBIAN_CODENAME (the upstream
#      codename Docker actually publishes — e.g. "noble"), NOT VERSION_CODENAME
#      which is the derivative's own marketing name (e.g. "prithvi").
#   4. Installs Docker via official apt/dnf repo for the resolved family
#   5. Adds current user to the docker group
#   6. Starts Docker service (systemd if available, else service fallback)
#   7. Verifies: docker --version + docker info
#
# USAGE:
#   bash scripts/setup/docker.sh
#   bash scripts/setup/docker.sh --force  # reinstall
#   bash scripts/setup/docker.sh --check  # check only, no install
#
# EXIT CODES:
#   0 — Docker installed and daemon accessible
#   1 — Installation failed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/common.sh"
set_script_log "docker_setup"

# ── Robust docker-daemon reachability check ─────────────────────────────────
# After a fresh install, the user gets added to the `docker` group, but the
# CURRENT shell's effective groups (per `id -nG`) were captured at shell
# startup and do NOT yet include `docker`. So plain `docker info` will fail
# with EACCES on /var/run/docker.sock even though the daemon is fine and the
# user IS in the group on disk (per `getent group docker`).
#
# This helper tries, in order:
#   1. docker info                  — works once shell has the group loaded
#   2. sg docker -c 'docker info'   — runs in a sub-shell with docker as the
#                                     primary group, picking up the membership
#                                     written to /etc/group without re-login
#   3. sudo -n docker info          — only if passwordless sudo is configured;
#                                     never prompts (the -n flag aborts on auth)
#
# Returns 0 if any of those reaches the daemon, 1 otherwise. On success via
# fallback, sets DOCKER_GROUP_RELOGIN_NEEDED=1 so the caller can warn the user
# that their interactive shell still needs `newgrp docker` / re-login.
_docker_info_ok() {
  DOCKER_GROUP_RELOGIN_NEEDED=0
  if docker info &>/dev/null; then
    return 0
  fi
  # Direct check failed. Distinguish "daemon down" from "permission denied
  # because current shell hasn't reloaded the docker group".
  local in_group_on_disk=0
  if getent group docker 2>/dev/null | awk -F: -v u="$USER" '{split($4,m,","); for (i in m) if (m[i]==u) found=1} END {exit !found}'; then
    in_group_on_disk=1
  fi
  local sock_exists=0
  [ -S /var/run/docker.sock ] && sock_exists=1

  if [ "$in_group_on_disk" -eq 1 ] && [ "$sock_exists" -eq 1 ] && command -v sg &>/dev/null; then
    if sg docker -c 'docker info' &>/dev/null; then
      DOCKER_GROUP_RELOGIN_NEEDED=1
      return 0
    fi
  fi

  # Last resort: passwordless sudo. -n means "non-interactive" — fails fast
  # without prompting if a password would be required.
  if sudo -n docker info &>/dev/null; then
    DOCKER_GROUP_RELOGIN_NEEDED=1
    return 0
  fi

  return 1
}

# Print a clear explanation when verify only succeeded via the group-reload
# fallback. The daemon is fine; the *current shell* just hasn't picked up
# the new group membership yet.
_warn_docker_group_session() {
  log_warn "Docker daemon IS running, but your current shell can't reach the socket directly."
  log_warn "  → Cause: you were just added to the 'docker' group, but THIS shell's"
  log_warn "    effective groups were fixed at login and don't yet include 'docker'."
  log_warn "  → Verified working via: sg docker -c 'docker info'  (or via sudo)"
  log_warn "  → To use plain 'docker' in this terminal, run ONE of:"
  log_warn "        newgrp docker            # reload groups in current shell"
  log_warn "        exec su - \"\$USER\"        # full re-login"
  log_warn "        (or just open a new terminal / log out and back in)"
  log_warn "  This is a session issue, NOT an install failure — proceeding."
}

# ── Parse arguments ──────────────────────────────────────────────────────────
CHECK_ONLY=0
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=1 ;;
    --force) FORCE=1 ;;
    --help)  echo "Usage: $0 [--check|--force]"; exit 0 ;;
    *)       log_warn "Unknown option: $1" ;;
  esac
  shift
done

# ── Runtime info ─────────────────────────────────────────────────────────────
if is_wsl2; then
  log_info "Runtime: WSL2"
else
  log_info "Runtime: Linux"
fi
has_systemd && log_info "systemd: yes" || log_info "systemd: no (will use service fallback)"

# Helpers that summarise the live runtime state for log_pass evidence lines.
# These are factored out because Path A (--check) and Path B (already-installed,
# no --force) both want the same four facts: docker binary path, daemon-reachable
# verdict, group membership of $USER, and any prior install manifest.
_docker_socket_path() {
  [ -S /var/run/docker.sock ] && echo "/var/run/docker.sock" || echo "(no /var/run/docker.sock)"
}
_docker_user_in_group() {
  if getent group docker 2>/dev/null \
       | awk -F: -v u="$USER" '{split($4,m,","); for (i in m) if (m[i]==u) found=1} END {exit !found}'; then
    echo "yes"
  else
    echo "no"
  fi
}
_docker_manifest_path() {
  local m="$MANIFEST_DIR/docker.yaml"
  [ -f "$m" ] && echo "$m" || echo "(no manifest — install predates manifest tracking)"
}

# ── Check if already installed ────────────────────────────────────────────────
if command -v docker &>/dev/null && [ "$FORCE" -eq 0 ]; then
  DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
  log_info "Docker $DOCKER_VER already installed"
  if [ "$CHECK_ONLY" -eq 1 ]; then
    # Path A: --check mode, docker present. Emit a structured PASS so that
    # consumers (run_all.sh, dashboards, the user) get the same evidence
    # block as a fresh install path produces.
    DAEMON_VERDICT="not running"
    if _docker_info_ok; then
      DAEMON_VERDICT="running"
      log_info "Docker daemon: running"
      [ "${DOCKER_GROUP_RELOGIN_NEEDED:-0}" -eq 1 ] && _warn_docker_group_session
    else
      log_warn "Docker daemon: not running"
    fi
    COMPOSE_VER="$(docker compose version --short 2>/dev/null || echo 'plugin-missing')"
    log_pass "Docker Engine + Compose v2 (--check)" \
      "command -v docker, docker --version, _docker_info_ok (direct → sg docker → sudo -n), getent group docker, /var/run/docker.sock" \
      "docker ${DOCKER_VER} on PATH; daemon ${DAEMON_VERDICT}; compose v2 = ${COMPOSE_VER}; $USER in docker group: $(_docker_user_in_group); group-relogin-needed=${DOCKER_GROUP_RELOGIN_NEEDED:-0}" \
      "binary=$(command -v docker); socket=$(_docker_socket_path); manifest=$(_docker_manifest_path); log=logs/docker_setup.log" \
      "bash scripts/validate.sh --suite docker"
    exit 0
  fi
  # Path B: docker present, no --force, not just --check. Verify daemon, then
  # emit a structured PASS so the "already installed" path is no longer
  # silent green.
  log_info "Use --force to reinstall"
  if ! _docker_info_ok; then
    log_warn "Docker installed but daemon not running — attempting start"
    _start_docker_daemon
    _docker_info_ok || true
  fi
  [ "${DOCKER_GROUP_RELOGIN_NEEDED:-0}" -eq 1 ] && _warn_docker_group_session
  DAEMON_VERDICT="not reachable"
  _docker_info_ok && DAEMON_VERDICT="running"
  COMPOSE_VER="$(docker compose version --short 2>/dev/null || echo 'plugin-missing')"
  log_pass "Docker Engine + Compose v2 (already installed)" \
    "command -v docker, docker --version, _docker_info_ok (direct → sg docker → sudo -n), getent group docker, /var/run/docker.sock, prior install manifest" \
    "docker ${DOCKER_VER} already on PATH (skipping reinstall — pass --force to override); daemon ${DAEMON_VERDICT}; compose v2 = ${COMPOSE_VER}; $USER in docker group: $(_docker_user_in_group); group-relogin-needed=${DOCKER_GROUP_RELOGIN_NEEDED:-0}" \
    "binary=$(command -v docker); socket=$(_docker_socket_path); manifest=$(_docker_manifest_path); log=logs/docker_setup.log" \
    "bash scripts/validate.sh --suite docker    # then: bash scripts/setup/postgres.sh"
  exit 0
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  if command -v docker &>/dev/null; then
    log_info "Docker: installed"
    exit 0
  fi
  log_error "Docker: NOT installed"
  log_error "  → WHY IT MATTERS: --check requires docker on PATH; nothing to verify"
  log_error "  → HOW TO FIX: bash scripts/setup/docker.sh   # install Docker Engine + Compose v2"
  log_fail "Docker Engine (--check)" \
    "command -v docker" \
    "docker binary not on PATH and --check was requested (no install allowed in this mode)" \
    "run: bash scripts/setup/docker.sh   # to perform the install" \
    "bash scripts/setup/docker.sh --check   # to re-verify after install"
  exit 1
fi

# ── WSL2 + Docker Desktop check ───────────────────────────────────────────────
# Docker Desktop for Windows exposes the Docker socket into WSL2 distros.
# If the socket is already reachable, there is nothing to install.
if is_wsl2 && docker info &>/dev/null 2>&1; then
  log_info "Docker Desktop integration is active in this WSL2 distro — skipping native install"
  DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
  log_info "Docker $DOCKER_VER available via Docker Desktop"
  exit 0
fi

# ── Install Docker ────────────────────────────────────────────────────────────
log_header "Installing Docker Engine"

# ── Detect distro family ────────────────────────────────────────────────────
# Docker.com publishes apt repos for "ubuntu" and "debian" only, and dnf repos
# for "rhel"/"fedora"/"centos". Many real-world distros are derivatives of
# those (Linux Mint, Pop!_OS, SuryaOS, Elementary, Zorin → ubuntu; Kali, MX,
# Devuan → debian; Rocky, AlmaLinux → rhel). Their /etc/os-release sets:
#   ID=<derivative-name>           — does NOT match Docker repo path
#   ID_LIKE="ubuntu"|"debian"|...  — the upstream family (use this!)
#   UBUNTU_CODENAME=<noble|jammy>  — Ubuntu derivatives expose this
#   DEBIAN_CODENAME=<bookworm>     — Debian derivatives expose this
#   VERSION_CODENAME=<derivative>  — usually the derivative's OWN codename,
#                                    NOT recognised by Docker (e.g. "prithvi")
#
# Strategy: read /etc/os-release once, then resolve to a (FAMILY, CODENAME)
# pair where FAMILY ∈ {ubuntu, debian, rhel, fedora} that Docker actually
# publishes packages for, and CODENAME is one Docker recognises.
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
log_info "  UBUNTU_CODENAME   = '${OS_UBUNTU_CODENAME:-(none)}'"
log_info "  DEBIAN_CODENAME   = '${OS_DEBIAN_CODENAME:-(none)}'"

# Resolve FAMILY: prefer ID, fall back to ID_LIKE for derivatives.
# ID_LIKE may contain multiple space-separated tokens (e.g. "debian ubuntu"),
# so we test with a glob match.
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
# Normalise rocky/almalinux to the rhel repo (they're 1:1 RHEL rebuilds)
case "$FAMILY" in rocky|almalinux|centos) FAMILY="rhel" ;; esac

if [ -n "$FAMILY" ] && [ "$FAMILY" != "$OS_ID" ]; then
  log_warn "Detected '$OS_ID' — treating as '$FAMILY' derivative (via ID_LIKE)"
fi
log_info "Resolved family: '${FAMILY:-(unsupported)}'"

# ── Resolve apt CODENAME for ubuntu/debian families ─────────────────────────
# Docker.com only ships packages for upstream codenames (jammy, noble, bookworm).
# A derivative's VERSION_CODENAME is its OWN marketing name (e.g. "prithvi",
# "vanessa", "una") and is NOT a valid Docker repo path. Always prefer the
# upstream-family codename when present.
CODENAME=""
case "$FAMILY" in
  ubuntu)
    CODENAME="${OS_UBUNTU_CODENAME:-$OS_VERSION_CODENAME}"
    if [ -n "$OS_UBUNTU_CODENAME" ] && [ "$OS_UBUNTU_CODENAME" != "$OS_VERSION_CODENAME" ]; then
      log_info "Using UBUNTU_CODENAME='$OS_UBUNTU_CODENAME' for Docker apt repo"
      log_info "  (ignoring VERSION_CODENAME='$OS_VERSION_CODENAME' — Docker doesn't publish that)"
    fi
    ;;
  debian)
    CODENAME="${OS_DEBIAN_CODENAME:-$OS_VERSION_CODENAME}"
    if [ -n "$OS_DEBIAN_CODENAME" ] && [ "$OS_DEBIAN_CODENAME" != "$OS_VERSION_CODENAME" ]; then
      log_info "Using DEBIAN_CODENAME='$OS_DEBIAN_CODENAME' for Docker apt repo"
      log_info "  (ignoring VERSION_CODENAME='$OS_VERSION_CODENAME' — Docker doesn't publish that)"
    fi
    ;;
esac

case "$FAMILY" in
  ubuntu|debian)
    if [ -z "$CODENAME" ]; then
      log_error "No usable codename detected for family='$FAMILY'"
      log_error "  → WHY IT MATTERS: Docker apt repo path needs a codename Docker publishes"
      log_error "  → HOW TO FIX: set UBUNTU_CODENAME or DEBIAN_CODENAME in /etc/os-release,"
      log_error "       or override with: CODENAME=jammy bash scripts/setup/docker.sh"
      log_fail "Docker Engine" \
        "/etc/os-release UBUNTU_CODENAME / DEBIAN_CODENAME / VERSION_CODENAME for family='$FAMILY'" \
        "no upstream codename Docker publishes was found (VERSION_CODENAME='${OS_VERSION_CODENAME:-none}' is the derivative's own marketing name and is not recognised by download.docker.com)" \
        "set UBUNTU_CODENAME=<jammy|noble|...> or DEBIAN_CODENAME=<bookworm|...> in /etc/os-release; OR override at run time: CODENAME=noble bash scripts/setup/docker.sh" \
        "bash scripts/setup/docker.sh   # re-run with codename resolved"
      exit 1
    fi
    log_step "Installing via apt (family=$FAMILY, codename=$CODENAME)..."
    log_info "  Apt repo: https://download.docker.com/linux/$FAMILY $CODENAME stable"

    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl gnupg

    sudo install -m 0755 -d /etc/apt/keyrings
    log_step "Fetching Docker GPG key..."
    curl -fsSL "https://download.docker.com/linux/$FAMILY/gpg" \
      | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
    log_info "  GPG key installed → /etc/apt/keyrings/docker.gpg"

    log_step "Writing apt source list..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/$FAMILY $CODENAME stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    log_info "  Source list → /etc/apt/sources.list.d/docker.list"

    log_step "apt-get update + install (docker-ce + cli + containerd + buildx + compose)..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    ;;

  rhel|fedora)
    log_step "Installing via dnf (family=$FAMILY)..."
    log_info "  Repo URL: https://download.docker.com/linux/$FAMILY/docker-ce.repo"
    sudo dnf -y install dnf-plugins-core
    sudo dnf config-manager --add-repo "https://download.docker.com/linux/$FAMILY/docker-ce.repo"
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    ;;

  *)
    log_error "Unsupported OS: ID='${OS_ID:-unknown}' ID_LIKE='${OS_ID_LIKE:-none}'"
    log_error "  → WHY IT MATTERS: Docker only publishes packages for ubuntu/debian/rhel/fedora"
    log_error "  → HOW TO FIX:"
    log_error "      1. If your distro is derived from one of those, set ID_LIKE in /etc/os-release"
    log_error "      2. Or install Docker manually: https://docs.docker.com/engine/install/"
    log_error "      3. Then re-run:  bash scripts/validate.sh --suite docker"
    log_fail "Docker Engine" \
      "/etc/os-release ID + ID_LIKE against {ubuntu, debian, rhel, fedora, centos, rocky, almalinux}" \
      "ID='${OS_ID:-unknown}' ID_LIKE='${OS_ID_LIKE:-none}' resolved to no supported family — download.docker.com only publishes packages for ubuntu/debian/rhel/fedora" \
      "either (1) add a recognised family to /etc/os-release ID_LIKE (e.g. ID_LIKE=\"ubuntu\"), or (2) install Docker manually per https://docs.docker.com/engine/install/" \
      "bash scripts/validate.sh --suite docker   # after manual install"
    exit 1
    ;;
esac

# ── Add user to docker group ──────────────────────────────────────────────────
if ! groups "$USER" 2>/dev/null | grep -q docker; then
  log_step "Adding $USER to docker group..."
  sudo usermod -aG docker "$USER"
  log_warn "Group change takes effect on next login (or run: newgrp docker)"
fi

# ── Start Docker daemon ───────────────────────────────────────────────────────
_start_docker_daemon() {
  if has_systemd; then
    log_step "Enabling and starting Docker via systemd..."
    sudo systemctl enable docker
    sudo systemctl start docker
  else
    # WSL2 without systemd, or container environments
    log_step "systemd not available — starting Docker via service(8)..."
    sudo service docker start 2>/dev/null || \
      sudo dockerd --host=unix:///var/run/docker.sock &>/dev/null &
    sleep 2
  fi
}

if ! _docker_info_ok; then
  _start_docker_daemon
fi

# ── Verify ────────────────────────────────────────────────────────────────────
log_header "Verifying Docker installation"

if ! command -v docker &>/dev/null; then
  log_error "docker binary not found after install"
  exit 1
fi

DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
log_info "docker $DOCKER_VER — OK"

if ! _docker_info_ok; then
  log_error "Docker daemon not reachable after install"
  if is_wsl2 && ! has_systemd; then
    log_error "  WSL2 without systemd: start the daemon manually:"
    log_error "    sudo service docker start"
    log_error "  Or enable systemd in /etc/wsl.conf:"
    log_error "    [boot]"
    log_error "    systemd=true"
  fi
  _DAEMON_FIX="run: sudo systemctl start docker   # or: sudo service docker start"
  if is_wsl2 && ! has_systemd; then
    _DAEMON_FIX="WSL2 without systemd: 'sudo service docker start' OR enable systemd in /etc/wsl.conf ([boot]\\nsystemd=true) and 'wsl --shutdown' from Windows"
  fi
  log_fail "Docker Engine" \
    "_docker_info_ok (docker info → sg docker -c 'docker info' → sudo -n docker info) after _start_docker_daemon" \
    "packages installed and daemon start invoked, but no reachability path to /var/run/docker.sock succeeded; daemon may have failed to start, or socket has wrong perms" \
    "$_DAEMON_FIX" \
    "bash scripts/setup/docker.sh --check   # re-verify; then bash scripts/validate.sh --suite docker"
  exit 1
fi

[ "${DOCKER_GROUP_RELOGIN_NEEDED:-0}" -eq 1 ] && _warn_docker_group_session
COMPOSE_VER="$(docker compose version --short 2>/dev/null || echo 'plugin-missing')"
log_pass "Docker Engine + Compose v2" \
  "distro family resolved from /etc/os-release (ID + ID_LIKE), apt/dnf repo configured (download.docker.com), docker-ce + cli + containerd + buildx + compose-plugin installed, $USER added to docker group, daemon started (systemd or service), 'docker --version' + docker_daemon_reachable() both succeeded" \
  "docker ${DOCKER_VER} installed for family='${FAMILY:-detected}' codename='${CODENAME:-n/a}'; compose v2 = ${COMPOSE_VER}; daemon reachable via /var/run/docker.sock; $USER is a member of the docker group" \
  "binary=$(command -v docker); socket=/var/run/docker.sock; log=logs/docker_setup.log; group-relogin-needed=${DOCKER_GROUP_RELOGIN_NEEDED:-0}" \
  "bash scripts/validate.sh --suite docker    # then: bash scripts/setup/postgres.sh"
exit 0
