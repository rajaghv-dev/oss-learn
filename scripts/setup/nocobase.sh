#!/bin/bash
# =============================================================================
# nocobase.sh — NocoBase Self-Hosted Low-Code Platform Setup
#
# PURPOSE:
#   Starts NocoBase (open-source Airtable/Notion alternative) at
#   http://localhost:13000, backed by a dedicated PostgreSQL 16 instance.
#   Provides data tables, forms, workflows, and dashboards without coding.
#
# ── Sources ───────────────────────────────────────────────────────────
# Docker Hub:   nocobase/nocobase:latest
#               https://hub.docker.com/r/nocobase/nocobase
#               postgres:16-alpine
# Compose:      infra/nocobase/docker-compose.yml
# Web:          http://localhost:13000
# Default creds: admin@nocobase.com / admin1234
#
# ── Usage Examples ────────────────────────────────────────────────────
#   bash scripts/infra/nocobase.sh              # Start NocoBase
#   bash scripts/infra/nocobase.sh --check      # Show status, no changes
#   bash scripts/infra/nocobase.sh --force      # Tear down + rebuild
#   bash scripts/infra/nocobase.sh --help       # This help text
#
# EXIT CODES:
#   0  — NocoBase running and responding
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

set_script_log "nocobase"

usage() {
  cat <<'USAGE'
Usage: bash scripts/infra/nocobase.sh [OPTIONS]

Options:
  --check   Check whether NocoBase is running; do not start
  --force   Tear down and recreate all NocoBase containers
  --help    Show this message

Returns 0 on success, 1 on failure.
Writes manifest: setup/state/installs/nocobase.yaml
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

NOCOBASE_DIR="$REPO_ROOT/infra/nocobase"
NOCOBASE_COMPOSE="$NOCOBASE_DIR/docker-compose.yml"
NOCOBASE_URL="http://localhost:13000"

# =============================================================================
# --check: report status and exit
# =============================================================================
if [ "$CHECK_ONLY" -eq 1 ]; then
  log_header "NocoBase — status check"

  if ! command -v docker &>/dev/null; then
    log_warn "Docker not found"; exit 0
  fi

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "oss-nocobase$"; then
    log_info "Container oss-nocobase is running"
  else
    log_warn "Container oss-nocobase is not running"
  fi

  if curl -sf "${NOCOBASE_URL}/api/app:getInfo" >/dev/null 2>&1; then
    log_info "NocoBase API reachable at ${NOCOBASE_URL}"
  else
    log_warn "NocoBase API not reachable at ${NOCOBASE_URL}"
  fi

  if [ -f "$MANIFEST_DIR/nocobase.yaml" ]; then
    log_info "Manifest: $MANIFEST_DIR/nocobase.yaml"
  else
    log_warn "No install manifest for nocobase"
  fi

  exit 0
fi

# =============================================================================
# STEP 0: Preflight — Docker required
# =============================================================================
log_header "NocoBase Self-Hosted Low-Code (localhost:13000)"

if ! command -v docker &>/dev/null; then
  log_warn "Docker not found — skipping NocoBase"
  exit 0
fi

if [ ! -f "$NOCOBASE_COMPOSE" ]; then
  log_warn "Compose file not found: $NOCOBASE_COMPOSE — skipping"
  exit 0
fi

# =============================================================================
# STEP 1: --force: tear down existing containers
# =============================================================================
if [ "$FORCE" -eq 1 ]; then
  log_step "Force mode: tearing down existing NocoBase containers..."
  # --remove-orphans + 3 s settle to avoid docker's down-vs-up race
  # ("dependency failed to start: No such container ...").
  docker compose -f "$NOCOBASE_COMPOSE" down -v --remove-orphans 2>/dev/null || true
  sleep 3
  log_info "Existing containers removed"
fi

# =============================================================================
# STEP 2: Start via docker compose
# =============================================================================
log_step "Starting NocoBase (2 containers)..."

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "oss-nocobase$"; then
  log_info "oss-nocobase is already running"
else
  if ! docker compose -f "$NOCOBASE_COMPOSE" up -d; then
    log_error "Failed to start NocoBase"
    exit 1
  fi
fi

# =============================================================================
# STEP 3: Wait for API (up to 150 s — first-run DB install takes ~60 s)
# =============================================================================
log_step "Waiting for NocoBase at ${NOCOBASE_URL} (up to 150 s)..."

attempts=0
while [ $attempts -lt 30 ]; do
  if curl -sf "${NOCOBASE_URL}/api/app:getInfo" >/dev/null 2>&1; then
    break
  fi
  printf "  . "
  sleep 5
  ((attempts++)) || true
done
echo ""

if ! curl -sf "${NOCOBASE_URL}/api/app:getInfo" >/dev/null 2>&1; then
  log_error "NocoBase did not become ready after 150 s"
  log_error "Check: docker logs oss-nocobase"
  exit 1
fi

log_info "NocoBase ready at ${NOCOBASE_URL}"
log_info "Default login: admin@nocobase.com / admin1234"

# =============================================================================
# STEP 4: Write install manifest
# =============================================================================
write_manifest nocobase \
  location=local \
  container=oss-nocobase \
  image="nocobase/nocobase:latest" \
  web_url="${NOCOBASE_URL}" \
  compose_file="$NOCOBASE_COMPOSE" \
  data_dir="$NOCOBASE_DIR/data"

log_info "Install manifest written: $MANIFEST_DIR/nocobase.yaml"
log_pass "NocoBase Self-Hosted Low-Code (localhost:13000)" \
  "docker compose up -d for nocobase + postgres-16 backing store, then HTTP GET ${NOCOBASE_URL}/api/app:getInfo until 200 OK (max 150s for first-run DB install)" \
  "oss-nocobase container started from nocobase/nocobase:latest; API endpoint /api/app:getInfo responded; default login admin@nocobase.com / admin1234" \
  "compose=$NOCOBASE_COMPOSE, container=oss-nocobase, web_url=${NOCOBASE_URL}, data_dir=$NOCOBASE_DIR/data, manifest=$MANIFEST_DIR/nocobase.yaml" \
  "open ${NOCOBASE_URL} in a browser, or run: bash scripts/infra/nocobase.sh --check"
