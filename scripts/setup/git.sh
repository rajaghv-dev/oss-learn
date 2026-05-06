#!/bin/bash
# =============================================================================
# git.sh — Gitea Self-Hosted Git Service Setup
#
# PURPOSE:
#   Starts a Gitea git server at http://localhost:3001 (SSH on port 222),
#   backed by a dedicated PostgreSQL 16 instance.  Provides a local GitHub-
#   style interface for oss-learn code, specs, and config files.
#
# ── Sources ───────────────────────────────────────────────────────────
# Docker Hub:   gitea/gitea:1  (official Gitea image)
#               https://hub.docker.com/r/gitea/gitea
#               postgres:16-alpine
# Compose:      infra/git/docker-compose.yml
# Web:          http://localhost:3001   (first-run admin wizard)
# SSH:          ssh://git@localhost:222
#
# ── Usage Examples ────────────────────────────────────────────────────
#   bash scripts/infra/git.sh              # Start Gitea
#   bash scripts/infra/git.sh --check      # Show status, no changes
#   bash scripts/infra/git.sh --force      # Tear down + rebuild
#   bash scripts/infra/git.sh --help       # This help text
#
# EXIT CODES:
#   0  — Gitea running and responding
#   1  — Setup failed (see output for details)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

COMMON="$REPO_ROOT/scripts/common.sh"
if [ -f "$COMMON" ]; then
  source "$COMMON"
else
  echo "ERROR: $COMMON not found" >&2; exit 1
fi

set_script_log "git"

usage() {
  cat <<'USAGE'
Usage: bash scripts/infra/git.sh [OPTIONS]

Options:
  --check   Check whether Gitea is running; do not start
  --force   Tear down and recreate all Gitea containers
  --help    Show this message

Returns 0 on success, 1 on failure.
Writes manifest: setup/state/installs/git.yaml
USAGE
  exit 0
}

CHECK_ONLY=0
FORCE=0

ORIG_ARGS=("$@")

while [ $# -gt 0 ]; do
  case "$1" in
    --check)   CHECK_ONLY=1 ;;
    --force)   FORCE=1 ;;
    --help|-h) usage ;;
    *) log_warn "Unknown argument: $1" ;;
  esac
  shift
done

docker_reexec_if_needed "${BASH_SOURCE[0]}" "${ORIG_ARGS[@]}"

GIT_DIR="$REPO_ROOT/infra/git"
GIT_COMPOSE="$GIT_DIR/docker-compose.yml"
GITEA_URL="http://localhost:3001"

# =============================================================================
# --check: report status and exit
# =============================================================================
if [ "$CHECK_ONLY" -eq 1 ]; then
  log_header "Gitea — status check"

  if ! command -v docker &>/dev/null; then
    log_warn "Docker not found"; exit 0
  fi

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "oss-gitea$"; then
    log_info "Container oss-gitea is running"
  else
    log_warn "Container oss-gitea is not running"
  fi

  if curl -sf "${GITEA_URL}/" >/dev/null 2>&1; then
    log_info "Gitea web reachable at ${GITEA_URL}"
  else
    log_warn "Gitea web not reachable at ${GITEA_URL}"
  fi

  if [ -f "$MANIFEST_DIR/git.yaml" ]; then
    log_info "Manifest: $MANIFEST_DIR/git.yaml"
  else
    log_warn "No install manifest for git"
  fi

  exit 0
fi

# =============================================================================
# STEP 0: Preflight — Docker required
# =============================================================================
log_header "Gitea Self-Hosted Git (localhost:3001)"

if ! command -v docker &>/dev/null; then
  log_warn "Docker not found — skipping Gitea"
  exit 0
fi

if [ ! -f "$GIT_COMPOSE" ]; then
  log_warn "Compose file not found: $GIT_COMPOSE — skipping"
  exit 0
fi

# =============================================================================
# STEP 1: --force: tear down existing containers
# =============================================================================
if [ "$FORCE" -eq 1 ]; then
  log_step "Force mode: tearing down existing Gitea containers..."
  # --remove-orphans + 3 s settle to avoid docker's down-vs-up race
  # ("dependency failed to start: No such container ...").
  docker compose -f "$GIT_COMPOSE" down -v --remove-orphans 2>/dev/null || true
  sleep 3
  log_info "Existing containers removed"
fi

# =============================================================================
# STEP 2: Start via docker compose
# =============================================================================
log_step "Starting Gitea (web=3001, SSH=222)..."

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "oss-gitea$"; then
  log_info "oss-gitea is already running"
else
  if ! docker compose -f "$GIT_COMPOSE" up -d; then
    log_error "Failed to start Gitea"
    exit 1
  fi
fi

# =============================================================================
# STEP 3: Wait for Gitea web (up to 120 s — first-run DB migration takes time)
# =============================================================================
log_step "Waiting for Gitea web at ${GITEA_URL} (up to 120 s)..."

attempts=0
while [ $attempts -lt 24 ]; do
  if curl -sf "${GITEA_URL}/" >/dev/null 2>&1; then
    break
  fi
  printf "  . "
  sleep 5
  ((attempts++)) || true
done
echo ""

if ! curl -sf "${GITEA_URL}/" >/dev/null 2>&1; then
  log_error "Gitea did not become ready after 120 s"
  log_error "Check: docker logs oss-gitea"
  exit 1
fi

log_info "Gitea ready at ${GITEA_URL}"
log_info "First-run: open ${GITEA_URL} to complete admin setup"
log_info "SSH:       ssh://git@localhost:222"

# =============================================================================
# STEP 4: Write install manifest
# =============================================================================
write_manifest git \
  location=local \
  container=oss-gitea \
  image="gitea/gitea:1" \
  web_url="${GITEA_URL}" \
  ssh_port="222" \
  compose_file="$GIT_COMPOSE" \
  data_dir="$GIT_DIR/data"

log_info "Install manifest written: $MANIFEST_DIR/git.yaml"
log_pass "Gitea self-hosted git" \
  "docker compose up -d, container 'oss-gitea' present, HTTP GET ${GITEA_URL}/ with up-to-120s readiness loop" \
  "container 'oss-gitea' is running and the Gitea web UI at ${GITEA_URL} returned 2xx after first-run DB migration; SSH endpoint exposed on port 222" \
  "container=oss-gitea, image=gitea/gitea:1, web=${GITEA_URL}, ssh_port=222, compose=$GIT_COMPOSE, data_dir=$GIT_DIR/data, manifest=$MANIFEST_DIR/git.yaml" \
  "open ${GITEA_URL}   # complete first-run admin wizard"
