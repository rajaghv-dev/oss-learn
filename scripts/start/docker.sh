#!/bin/bash
# Ensure Docker daemon is running before other start steps depend on it.
# USAGE: bash scripts/start/docker.sh [--dry-run]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$REPO_ROOT/scripts/common.sh"
set_script_log "start_docker"

# See scripts/setup/docker.sh for the rationale. Briefly: a freshly added
# user is in the docker group on disk but the current shell hasn't reloaded
# its supplementary groups, so plain `docker info` fails with EACCES on the
# socket even though the daemon is fine.
_docker_info_ok() {
  DOCKER_GROUP_RELOGIN_NEEDED=0
  if docker info &>/dev/null; then
    return 0
  fi
  local in_group_on_disk=0
  if getent group docker 2>/dev/null | awk -F: -v u="$USER" '{split($4,m,","); for (i in m) if (m[i]==u) found=1} END {exit !found}'; then
    in_group_on_disk=1
  fi
  if [ "$in_group_on_disk" -eq 1 ] && [ -S /var/run/docker.sock ] && command -v sg &>/dev/null; then
    if sg docker -c 'docker info' &>/dev/null; then
      DOCKER_GROUP_RELOGIN_NEEDED=1
      return 0
    fi
  fi
  if sudo -n docker info &>/dev/null; then
    DOCKER_GROUP_RELOGIN_NEEDED=1
    return 0
  fi
  return 1
}
_warn_docker_group_session() {
  log_warn "Docker daemon IS reachable, but only via 'sg docker' / sudo —"
  log_warn "  your current shell hasn't reloaded the docker group yet."
  log_warn "  Run 'newgrp docker' or open a new terminal to use plain 'docker'."
}

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

log_info "Ensuring Docker daemon is running..."
is_wsl2 && log_info "  Runtime: WSL2" || log_info "  Runtime: Linux"

if ! command -v docker &>/dev/null; then
  log_error "Docker not found — run: bash scripts/setup/docker.sh"
  exit 1
fi

if _docker_info_ok; then
  log_info "Docker daemon: already running"
  [ "${DOCKER_GROUP_RELOGIN_NEEDED:-0}" -eq 1 ] && _warn_docker_group_session
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  log_info "DRY-RUN: would start Docker daemon"
  exit 0
fi

log_step "Docker daemon not running — starting..."

if has_systemd; then
  sudo systemctl start docker
elif is_wsl2; then
  # WSL2 without systemd — service(8) wraps /etc/init.d/docker
  sudo service docker start 2>/dev/null || {
    log_warn "service(8) failed; starting dockerd directly..."
    sudo dockerd --host=unix:///var/run/docker.sock &>/tmp/dockerd.log &
    disown
    sleep 3
  }
else
  log_error "Cannot start Docker: no systemd and not WSL2"
  log_error "  Start manually: sudo systemctl start docker"
  exit 1
fi

# Verify daemon came up
if _docker_info_ok; then
  log_info "Docker daemon: running"
  [ "${DOCKER_GROUP_RELOGIN_NEEDED:-0}" -eq 1 ] && _warn_docker_group_session
else
  log_error "Docker daemon did not start"
  is_wsl2 && log_error "  WSL2: enable systemd via /etc/wsl.conf [boot] systemd=true"
  exit 1
fi

log_info "RESULT: Docker started"
exit 0
