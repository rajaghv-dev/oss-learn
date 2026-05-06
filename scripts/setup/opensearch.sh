#!/bin/bash
# =============================================================================
# opensearch.sh — OpenSearch Self-Hosted Search & Analytics Setup
#
# PURPOSE:
#   Installs the vm.max_map_count kernel parameter (required by OpenSearch),
#   then starts OpenSearch 2.x and OpenSearch Dashboards via Docker Compose.
#   Security plugin is disabled for local dev (no credentials required).
#
# ── Sources ───────────────────────────────────────────────────────────
# Docker Hub:   opensearchproject/opensearch:2
#               opensearchproject/opensearch-dashboards:2
#               https://hub.docker.com/u/opensearchproject
# Compose:      setup/opensearch/docker-compose.yml
# API:          http://localhost:9200   (Elasticsearch-compatible REST)
# Dashboards:   http://localhost:5601   (Kibana-compatible UI, no auth)
#
# Port conflict note: 9200 and 9300 overlap with emp-reg and analytics gRPC
#   ports when PROTOCOL_GRPC=true — those are off by default.
#
# ── Usage Examples ────────────────────────────────────────────────────
#   bash scripts/setup/opensearch.sh              # Install + start
#   bash scripts/setup/opensearch.sh --check      # Show status, no changes
#   bash scripts/setup/opensearch.sh --force      # Tear down + rebuild
#   bash scripts/setup/opensearch.sh --help       # This help text
#
# EXIT CODES:
#   0  — OpenSearch running and cluster healthy
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

set_script_log "opensearch"

usage() {
  cat <<'USAGE'
Usage: bash scripts/setup/opensearch.sh [OPTIONS]

Options:
  --check   Check whether OpenSearch is running; do not start
  --force   Tear down and recreate all OpenSearch containers
  --help    Show this message

Returns 0 on success, 1 on failure.
Writes manifest: setup/state/installs/opensearch.yaml
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

OS_DIR="$REPO_ROOT/setup/opensearch"
OS_COMPOSE="$OS_DIR/docker-compose.yml"
OS_URL="http://localhost:9200"
DASH_URL="http://localhost:5601"

# =============================================================================
# --check: report status and exit
# =============================================================================
if [ "$CHECK_ONLY" -eq 1 ]; then
  log_header "OpenSearch — status check"

  if ! command -v docker &>/dev/null; then
    log_warn "Docker not found"; exit 0
  fi

  for cname in oss-opensearch oss-opensearch-dashboards; do
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${cname}$"; then
      log_info "Container ${cname} is running"
    else
      log_warn "Container ${cname} is not running"
    fi
  done

  if curl -sf "${OS_URL}/_cluster/health" >/dev/null 2>&1; then
    health=$(curl -sf "${OS_URL}/_cluster/health" 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 || echo "unknown")
    log_info "OpenSearch API reachable at ${OS_URL}  (${health})"
  else
    log_warn "OpenSearch API not reachable at ${OS_URL}"
  fi

  if curl -sf "${DASH_URL}/api/status" >/dev/null 2>&1; then
    log_info "Dashboards reachable at ${DASH_URL}"
  else
    log_warn "Dashboards not reachable at ${DASH_URL}"
  fi

  if [ -f "$MANIFEST_DIR/opensearch.yaml" ]; then
    log_info "Manifest: $MANIFEST_DIR/opensearch.yaml"
  else
    log_warn "No install manifest for opensearch"
  fi

  exit 0
fi

# =============================================================================
# STEP 0: Preflight — Docker required
# =============================================================================
log_header "OpenSearch 2.x  (API=localhost:9200  Dashboards=localhost:5601)"

if ! command -v docker &>/dev/null; then
  log_warn "Docker not found — skipping OpenSearch"
  exit 0
fi

if [ ! -f "$OS_COMPOSE" ]; then
  log_warn "Compose file not found: $OS_COMPOSE — skipping"
  exit 0
fi

# =============================================================================
# STEP 1: Set vm.max_map_count (OpenSearch requires ≥ 262144)
# =============================================================================
log_step "Checking vm.max_map_count (OpenSearch requires ≥ 262144)..."

current_map_count=$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo 0)
if [ "$current_map_count" -lt 262144 ]; then
  log_step "Setting vm.max_map_count=262144 (requires sudo)..."
  if sudo sysctl -w vm.max_map_count=262144; then
    log_info "vm.max_map_count set to 262144"
    log_warn "This is runtime-only. To persist across reboots, add to /etc/sysctl.conf:"
    log_warn "  vm.max_map_count=262144"
  else
    log_warn "Could not set vm.max_map_count — OpenSearch may fail to start"
    log_warn "Run manually: sudo sysctl -w vm.max_map_count=262144"
  fi
else
  log_info "vm.max_map_count=${current_map_count} (sufficient)"
fi

# =============================================================================
# STEP 2: --force: tear down existing containers
# =============================================================================
if [ "$FORCE" -eq 1 ]; then
  log_step "Force mode: tearing down existing OpenSearch containers..."
  # --remove-orphans + 3 s settle to avoid docker's down-vs-up race
  # ("dependency failed to start: No such container ...").
  docker compose -f "$OS_COMPOSE" down -v --remove-orphans 2>/dev/null || true
  sleep 3
  log_info "Existing containers removed"
fi

# =============================================================================
# STEP 3: Pull images
# =============================================================================
log_step "Pulling OpenSearch images (opensearchproject/opensearch:2)..."
docker compose -f "$OS_COMPOSE" pull --quiet 2>/dev/null || \
  log_warn "Image pull had warnings — images may already be cached"

# =============================================================================
# STEP 3.5: Pre-create + chown data dirs to OpenSearch container uid
# =============================================================================
# WHY: The bind mount `./data/opensearch` is created by the docker daemon as
# root:root on first up. The opensearch container runs as uid 1000 (the
# `opensearch` user) and tries to write to /usr/share/opensearch/data/nodes —
# fails with AccessDeniedException, container goes Up (unhealthy) forever.
# Fix: create the dir on the host first and chown it to 1000:0 (uid:gid that
# the container expects). Idempotent — running on an already-correct dir is
# a no-op except for a tiny chown call.
OS_DATA_DIR="$OS_DIR/data/opensearch"
OS_DASH_DATA_DIR="$OS_DIR/data/dashboards"
log_step "Ensuring data dirs exist + are owned by uid 1000 (opensearch container user)"
mkdir -p "$OS_DATA_DIR" "$OS_DASH_DATA_DIR" 2>/dev/null || true
# `id -u` of host user; if it's NOT 1000 OR if the dir is currently root-owned,
# we need sudo to chown. Try non-interactively first; warn (don't fail) if
# sudo isn't available — the user can re-run with sudo manually.
_owner_uid_now() { stat -c '%u' "$1" 2>/dev/null || echo unknown; }
for d in "$OS_DATA_DIR" "$OS_DASH_DATA_DIR"; do
  curr=$(_owner_uid_now "$d")
  if [ "$curr" = "1000" ]; then
    log_info "  $d already owned by uid 1000 — OK"
  elif sudo -n chown -R 1000:0 "$d" 2>/dev/null; then
    log_info "  chown 1000:0 $d  (was uid=$curr) — OK"
  elif [ "$curr" = "$(id -u)" ]; then
    # Host user owns it (e.g. mkdir created it just now under uid 1000 host).
    log_info "  $d owned by current user uid=$curr — OpenSearch may still fail; if so:"
    log_info "      sudo chown -R 1000:0 $d"
  else
    log_warn "  $d is owned by uid=$curr and sudo is not cached."
    log_warn "      → Run THIS yourself, then re-run setup:"
    log_warn "          sudo chown -R 1000:0 $d"
  fi
done

# =============================================================================
# STEP 4: Start via docker compose
# =============================================================================
log_step "Starting OpenSearch + Dashboards (2 containers)..."

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "oss-opensearch$"; then
  log_info "oss-opensearch is already running"
else
  if ! docker compose -f "$OS_COMPOSE" up -d; then
    log_error "Failed to start OpenSearch"
    exit 1
  fi
fi

# =============================================================================
# STEP 5: Wait for OpenSearch cluster health (up to 90 s)
# =============================================================================
log_step "Waiting for OpenSearch cluster health at ${OS_URL} (up to 90 s)..."

attempts=0
while [ $attempts -lt 18 ]; do
  if curl -sf "${OS_URL}/_cluster/health" 2>/dev/null | grep -qE '"status":"(green|yellow)"'; then
    break
  fi
  printf "  . "
  sleep 5
  ((attempts++)) || true
done
echo ""

if ! curl -sf "${OS_URL}/_cluster/health" >/dev/null 2>&1; then
  log_error "OpenSearch did not become ready after 90 s"
  log_error "Check: docker logs oss-opensearch"
  log_error "Hint:  sudo sysctl -w vm.max_map_count=262144"
  exit 1
fi

health=$(curl -sf "${OS_URL}/_cluster/health" 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 || echo "unknown")
log_info "OpenSearch cluster ready at ${OS_URL}  (${health})"

# =============================================================================
# STEP 6: Wait for Dashboards (up to 60 s — it starts after OpenSearch is healthy)
# =============================================================================
log_step "Waiting for OpenSearch Dashboards at ${DASH_URL} (up to 60 s)..."

attempts=0
while [ $attempts -lt 12 ]; do
  if curl -sf "${DASH_URL}/api/status" >/dev/null 2>&1; then
    break
  fi
  printf "  . "
  sleep 5
  ((attempts++)) || true
done
echo ""

if curl -sf "${DASH_URL}/api/status" >/dev/null 2>&1; then
  log_info "OpenSearch Dashboards ready at ${DASH_URL}"
else
  log_warn "Dashboards not yet ready — it may still be starting"
  log_warn "Check: docker logs oss-opensearch-dashboards"
fi

# =============================================================================
# STEP 7: Write install manifest
# =============================================================================
write_manifest opensearch \
  location=local \
  container=oss-opensearch \
  image="opensearchproject/opensearch:2" \
  api_url="${OS_URL}" \
  dashboards_url="${DASH_URL}" \
  compose_file="$OS_COMPOSE" \
  data_dir="$OS_DIR/data" \
  security=disabled

log_info "Install manifest written: $MANIFEST_DIR/opensearch.yaml"
log_pass "OpenSearch 2.x + Dashboards" \
  "vm.max_map_count >= 262144, docker compose up -d for opensearch + dashboards, then GET ${OS_URL}/_cluster/health until status=green|yellow (max 90s) and GET ${DASH_URL}/api/status (max 60s)" \
  "vm.max_map_count=${current_map_count}; cluster health reported ${health}; oss-opensearch + oss-opensearch-dashboards Up; security plugin disabled (no auth)" \
  "compose=$OS_COMPOSE, containers=oss-opensearch+oss-opensearch-dashboards, image=opensearchproject/opensearch:2, api=${OS_URL}, dashboards=${DASH_URL}, data_dir=$OS_DIR/data, manifest=$MANIFEST_DIR/opensearch.yaml" \
  "open ${DASH_URL} in a browser, or curl ${OS_URL}/_cluster/health"
