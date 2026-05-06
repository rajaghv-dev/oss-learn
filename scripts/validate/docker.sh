#!/bin/bash
# Validate Docker installation and daemon accessibility.
# USAGE: bash scripts/validate/docker.sh [--dry-run]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/common.sh"
set_script_log "validate_docker"

# Robust daemon check — see scripts/setup/docker.sh for full rationale.
# Falls back to `sg docker -c ...` / `sudo -n docker ...` to handle the case
# where the user is in the docker group on disk but the current shell's
# supplementary groups haven't been reloaded yet (no re-login since usermod).
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

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

log_info "Validating Docker..."
is_wsl2 && log_info "  Runtime: WSL2" || log_info "  Runtime: Linux"

FAIL=0

# 1. Binary present
if ! command -v docker &>/dev/null; then
  log_error "docker binary not found"
  log_error "  FIX: bash scripts/setup/docker.sh"
  exit 1
fi
log_info "  docker binary: $(docker --version)"

# 2. Compose plugin present
if ! docker compose version &>/dev/null; then
  log_warn "  docker compose plugin not found (needed for stack startup)"
  FAIL=1
else
  log_info "  docker compose: $(docker compose version --short 2>/dev/null || docker compose version)"
fi

# 3. Daemon reachable
if [ "$DRY_RUN" -eq 1 ]; then
  log_info "  DRY-RUN: skipping docker info"
else
  if ! _docker_info_ok; then
    log_error "  Docker daemon not reachable"
    if is_wsl2 && ! has_systemd; then
      log_error "  WSL2 fix: sudo service docker start"
    else
      log_error "  Fix: sudo systemctl start docker"
    fi
    FAIL=1
  else
    log_info "  Docker daemon: running"
  fi
fi

# 4. User can run docker without sudo
# Two distinct failure modes here:
#   (a) user NOT in docker group at all       → real fix needed (usermod)
#   (b) user IS in group but current shell    → just a session reload issue;
#       hasn't reloaded supplementary groups    don't fail, just warn
if [ "$DRY_RUN" -eq 0 ]; then
  if docker ps &>/dev/null; then
    log_info "  docker ps (no sudo): OK"
  else
    in_group_on_disk=0
    if getent group docker 2>/dev/null | awk -F: -v u="$USER" '{split($4,m,","); for (i in m) if (m[i]==u) found=1} END {exit !found}'; then
      in_group_on_disk=1
    fi
    if [ "$in_group_on_disk" -eq 1 ]; then
      log_warn "  docker ps (no sudo): not yet — user IS in 'docker' group on disk,"
      log_warn "    but current shell's supplementary groups predate the usermod."
      log_warn "    Reload with: newgrp docker   (or open a new terminal / re-login)"
      # Not a hard failure — daemon is reachable per check 3, this is just a session quirk.
    else
      log_warn "  Cannot run docker without sudo — add user to docker group:"
      log_warn "    sudo usermod -aG docker \$USER && newgrp docker"
      FAIL=1
    fi
  fi
fi

if [ "$FAIL" -eq 0 ]; then
  log_info "RESULT: Docker validation PASSED"
else
  log_warn "RESULT: Docker validation FAILED (see above)"
fi
exit $FAIL
