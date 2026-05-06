#!/bin/bash
# =============================================================================
# registry.sh — Local Docker Registry Setup
#
# PURPOSE:
#   Starts a local Docker registry at localhost:5000 using the official
#   registry:2 image, waits for the API to become ready, then builds and
#   pushes all 12 oss-learn service images via build-and-push.sh.
#
#   Part of the scripts/setup/ split — called by scripts/setup.sh or run
#   standalone for registry-only setup / re-setup.
#
# ── Sources ───────────────────────────────────────────────────────────
# Docker Hub:   registry:2 (official Docker registry image)
#               https://hub.docker.com/_/registry
# Compose:      setup/registry/docker-compose.yml
# Build script: setup/registry/build-and-push.sh
# Endpoint:     http://localhost:5000
# Alternative:  Harbor (https://goharbor.io/) for production registries
# Local build:  N/A — uses official Docker image
#
# ── Usage Examples ────────────────────────────────────────────────────
#   bash scripts/setup/registry.sh              # Start registry + build/push
#   bash scripts/setup/registry.sh --check      # Show status, no changes
#   bash scripts/setup/registry.sh --force      # Tear down + rebuild
#   bash scripts/setup/registry.sh --help       # This help text
#
# EXIT CODES:
#   0  — Registry running, images pushed (or --check passed)
#   1  — Setup failed (see output for details)
# =============================================================================

set -euo pipefail

# ── Resolve paths ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Source shared helpers (logging, manifests, stamps) ───────────────────────
COMMON="$REPO_ROOT/scripts/common.sh"
if [ -f "$COMMON" ]; then
  source "$COMMON"

# ── Initialize script-specific logging ──────────────────────────────────
# Creates logs/registry.log with detailed output.
set_script_log "registry"
else
  echo "ERROR: $COMMON not found — cannot continue" >&2
  exit 1
fi

# Capture original args before any arg-parsing shifts (for sg-docker re-exec)
ORIG_ARGS=("$@")

# ── Usage ────────────────────────────────────────────────────────────────────
usage() {
  cat <<'USAGE'
Usage: bash scripts/setup/registry.sh [OPTIONS]

Options:
  --check   Check whether registry is running; do not start
  --force   Tear down and recreate the registry container
  --help    Show this message

Returns 0 on success, 1 on failure.
Writes manifest: setup/state/installs/registry.yaml
USAGE
  exit 0
}

# ── Parse arguments ──────────────────────────────────────────────────────────
CHECK_ONLY=0
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --check)    CHECK_ONLY=1 ;;
    --force)    FORCE=1 ;;
    --help|-h)  usage ;;
    *)
      log_warn "Unknown argument: $1"
      ;;
  esac
  shift
done

# Re-exec under `sg docker` if the daemon is only reachable that way
docker_reexec_if_needed "${BASH_SOURCE[0]}" "${ORIG_ARGS[@]}"

# ── Paths ────────────────────────────────────────────────────────────────────
REG_DIR="$REPO_ROOT/setup/registry"
REG_COMPOSE="$REG_DIR/docker-compose.yml"
BUILD_SCRIPT="$REG_DIR/build-and-push.sh"
REGISTRY_ENDPOINT="http://localhost:5000"

# =============================================================================
# --check: report status and exit
# =============================================================================
if [ "$CHECK_ONLY" -eq 1 ]; then
  log_header "Docker Registry — status check"

  # Docker available?
  if ! command -v docker &>/dev/null; then
    log_warn "Docker not found"
    exit 0
  fi

  # Container running?
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "oss-registry"; then
    log_info "Container oss-registry is running"
  else
    log_warn "Container oss-registry is not running"
  fi

  # API reachable?
  if curl -sf "${REGISTRY_ENDPOINT}/v2/" >/dev/null 2>&1; then
    log_info "Registry API reachable at ${REGISTRY_ENDPOINT}/v2/"
    # List images in catalog
    local_catalog=$(curl -sf "${REGISTRY_ENDPOINT}/v2/_catalog" 2>/dev/null || echo "")
    if [ -n "$local_catalog" ]; then
      log_info "Catalog: $local_catalog"
    fi
  else
    log_warn "Registry API not reachable at ${REGISTRY_ENDPOINT}/v2/"
  fi

  # Compose file?
  if [ -f "$REG_COMPOSE" ]; then
    log_info "Compose file: $REG_COMPOSE"
  else
    log_warn "Compose file not found: $REG_COMPOSE"
  fi

  # Manifest?
  if [ -f "$MANIFEST_DIR/registry.yaml" ]; then
    log_info "Manifest: $MANIFEST_DIR/registry.yaml"
    log_info "  endpoint = $(read_manifest_field registry endpoint)"
  else
    log_warn "No install manifest for registry"
  fi

  exit 0
fi

# =============================================================================
# STEP 0: Preflight — Docker required
# =============================================================================
log_header "Local Docker Registry (localhost:5000)"

if ! command -v docker &>/dev/null; then
  log_warn "Docker not found — skipping registry"
  exit 0
fi

# =============================================================================
# STEP 1: Verify compose file exists
# =============================================================================
if [ ! -f "$REG_COMPOSE" ]; then
  log_warn "setup/registry/docker-compose.yml not found — skipping"
  exit 0
fi

# =============================================================================
# STEP 2: --force: tear down existing registry before rebuilding
# =============================================================================
if [ "$FORCE" -eq 1 ]; then
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "oss-registry"; then
    log_step "Force mode: tearing down existing oss-registry container..."
    docker compose -f "$REG_COMPOSE" down -v 2>/dev/null || true
    docker rm -f oss-registry 2>/dev/null || true
    log_info "Existing registry container removed"
  fi
fi

# =============================================================================
# STEP 3: Start local registry via docker compose
# =============================================================================
log_step "Starting local Docker registry (localhost:5000)..."

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "oss-registry"; then
  log_info "Registry container oss-registry is already running"
else
  if ! docker compose -f "$REG_COMPOSE" up -d; then
    log_error "Failed to start registry container"
    exit 1
  fi
fi

# =============================================================================
# STEP 4: Wait for registry API (up to 30 s)
# =============================================================================
log_step "Waiting for registry API at ${REGISTRY_ENDPOINT}/v2/..."

attempts=0
while [ $attempts -lt 30 ]; do
  if curl -sf "${REGISTRY_ENDPOINT}/v2/" >/dev/null 2>&1; then
    break
  fi
  printf "  . "
  sleep 1
  ((attempts++)) || true
done
echo ""

if ! curl -sf "${REGISTRY_ENDPOINT}/v2/" >/dev/null 2>&1; then
  log_error "Registry did not become ready after 30 s"
  log_error "Check container logs: docker logs oss-registry"
  exit 1
fi

log_info "Registry ready at ${REGISTRY_ENDPOINT}"

# =============================================================================
# STEP 5: Build and push all service images
# =============================================================================
if [ ! -f "$BUILD_SCRIPT" ]; then
  log_warn "build-and-push.sh not found at $BUILD_SCRIPT — skipping image build"
else
  log_step "Building and pushing all service images to registry..."
  if bash "$BUILD_SCRIPT"; then
    log_info "All service images pushed to localhost:5000/oss/<service>:latest"
  else
    log_error "One or more images failed to build/push — check output above"
    exit 1
  fi
fi

# =============================================================================
# STEP 6: Write install manifest
# =============================================================================
write_manifest registry \
  location=local \
  container=oss-registry \
  image="registry:2" \
  endpoint="${REGISTRY_ENDPOINT}" \
  compose_file="$REG_COMPOSE" \
  build_script="$BUILD_SCRIPT" \
  data_dir="$REG_DIR/data"

log_info "Install manifest written: $MANIFEST_DIR/registry.yaml"

log_pass "Local Docker Registry" \
  "docker compose up of oss-registry (registry:2); curl ${REGISTRY_ENDPOINT}/v2/ returns 200 within 30 s; ran setup/registry/build-and-push.sh to build and push all 12 oss-learn service images" \
  "container 'oss-registry' Up; registry API at ${REGISTRY_ENDPOINT}/v2/ responded; build-and-push.sh exited 0 — all images present at localhost:5000/oss/<service>:latest" \
  "container=oss-registry, image=registry:2, endpoint=${REGISTRY_ENDPOINT}, port=5000, compose=${REG_COMPOSE}, build_script=${BUILD_SCRIPT}, data_dir=${REG_DIR}/data, manifest=$MANIFEST_DIR/registry.yaml" \
  "curl ${REGISTRY_ENDPOINT}/v2/_catalog   # or: bash scripts/start.sh"
