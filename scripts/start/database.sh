#!/bin/bash
# Start database (Start Phase - Deployment)
# PURPOSE: Brings up the oss-postgres container if it's not already running.
#          Assumes infra/postgres.sh has already built the image (pgvector +
#          Apache AGE). If not, runs scripts/infra/postgres.sh on demand.
# USAGE:   bash scripts/start/database.sh [--dry-run]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/common.sh"
set_script_log "start_database"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

log_info "Starting database..."
log_info "  Log: $SCRIPT_LOG"

# ── Preflight: docker reachable? ─────────────────────────────────────
require_cmd docker "Run: bash scripts/setup/docker.sh" \
  "PostgreSQL runs as a Docker container (oss-postgres)"

if ! docker_daemon_reachable; then
  log_error "Docker daemon not reachable — start it first"
  log_error "  Run: bash scripts/start/docker.sh"
  exit 1
fi
[ "${DOCKER_GROUP_RELOGIN_NEEDED:-0}" -eq 1 ] && warn_docker_group_session

PGSQL_COMPOSE="$REPO_ROOT/infra/postgres/docker-compose.yml"
if [ ! -f "$PGSQL_COMPOSE" ]; then
  log_error "Missing compose file: $PGSQL_COMPOSE"
  exit 1
fi

# Pick docker compose flavour (v2 plugin preferred).
if docker compose version &>/dev/null; then
  DC="docker compose"
elif command -v docker-compose &>/dev/null; then
  DC="docker-compose"
else
  log_error "docker compose not available — install: sudo apt install docker-compose-plugin"
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  log_info "DRY-RUN: would run: $DC -f $PGSQL_COMPOSE up -d"
  exit 0
fi

# ── Already running? ────────────────────────────────────────────────
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^oss-postgres$'; then
  log_info "oss-postgres already running"
  exit 0
fi

# ── Image built? If not, defer to infra/postgres.sh which builds it. ─
if ! docker image inspect oss-postgres:pg16-pgvector-age &>/dev/null; then
  log_step "oss-postgres image missing — running scripts/infra/postgres.sh first..."
  bash "$REPO_ROOT/scripts/infra/postgres.sh"
  exit $?
fi

# ── Start the container ─────────────────────────────────────────────
log_step "Starting PostgreSQL container..."
if ! $DC -f "$PGSQL_COMPOSE" up -d; then
  log_error "docker compose up failed for $PGSQL_COMPOSE"
  exit 1
fi

# ── Wait briefly for readiness ──────────────────────────────────────
attempts=0
while [ $attempts -lt 30 ]; do
  if docker exec oss-postgres pg_isready -U postgres &>/dev/null; then
    log_info "PostgreSQL ready (after ${attempts}s)"
    log_info "RESULT: database started"
    exit 0
  fi
  sleep 1
  ((attempts++)) || true
done

log_error "PostgreSQL did not become ready after 30s"
log_error "  Check container logs: docker logs oss-postgres"
exit 1
