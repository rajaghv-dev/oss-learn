#!/bin/bash
# =============================================================================
# plane.sh — Plane Self-Hosted Project Management Setup
#
# PURPOSE:
#   Starts Plane (open-source Jira/Linear alternative) at http://localhost:4000,
#   including backend API, Celery workers, Next.js frontend/space, MinIO for
#   file storage, Redis for job queues, and a dedicated PostgreSQL 15 instance.
#
# ── Sources ───────────────────────────────────────────────────────────
# Docker Hub:   makeplane/plane-backend:stable
#               makeplane/plane-frontend:stable
#               makeplane/plane-space:stable
#               makeplane/plane-proxy:stable
#               https://hub.docker.com/u/makeplane
# Compose:      infra/plane/docker-compose.yml
# Web:          http://localhost:4000
# Default creds: admin@oss-learn.local / admin1234  (set in docker-compose env)
#
# ── Usage Examples ────────────────────────────────────────────────────
#   bash scripts/infra/plane.sh              # Start Plane stack
#   bash scripts/infra/plane.sh --check      # Show status, no changes
#   bash scripts/infra/plane.sh --force      # Tear down + rebuild
#   bash scripts/infra/plane.sh --help       # This help text
#
# EXIT CODES:
#   0  — Plane proxy running and responding
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

set_script_log "plane"

usage() {
  cat <<'USAGE'
Usage: bash scripts/infra/plane.sh [OPTIONS]

Options:
  --check   Check whether Plane is running; do not start
  --force   Tear down and recreate all Plane containers
  --help    Show this message

Returns 0 on success, 1 on failure.
Writes manifest: setup/state/installs/plane.yaml
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

PLANE_DIR="$REPO_ROOT/infra/plane"
PLANE_COMPOSE="$PLANE_DIR/docker-compose.yml"
PLANE_URL="http://localhost:4000"

# =============================================================================
# --check: report status and exit
# =============================================================================
if [ "$CHECK_ONLY" -eq 1 ]; then
  log_header "Plane — status check"

  if ! command -v docker &>/dev/null; then
    log_warn "Docker not found"; exit 0
  fi

  for cname in oss-plane-proxy oss-plane-api oss-plane-web; do
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "${cname}$"; then
      log_info "Container ${cname} is running"
    else
      log_warn "Container ${cname} is not running"
    fi
  done

  if curl -sf "${PLANE_URL}/" >/dev/null 2>&1; then
    log_info "Plane web reachable at ${PLANE_URL}"
  else
    log_warn "Plane web not reachable at ${PLANE_URL}"
  fi

  if [ -f "$MANIFEST_DIR/plane.yaml" ]; then
    log_info "Manifest: $MANIFEST_DIR/plane.yaml"
  else
    log_warn "No install manifest for plane"
  fi

  exit 0
fi

# =============================================================================
# STEP 0: Preflight — Docker required
# =============================================================================
log_header "Plane Self-Hosted Project Management (localhost:4000)"

if ! command -v docker &>/dev/null; then
  log_warn "Docker not found — skipping Plane"
  exit 0
fi

if [ ! -f "$PLANE_COMPOSE" ]; then
  log_warn "Compose file not found: $PLANE_COMPOSE — skipping"
  exit 0
fi

# =============================================================================
# STEP 1: --force: tear down existing containers
# =============================================================================
if [ "$FORCE" -eq 1 ]; then
  log_step "Force mode: tearing down existing Plane containers..."
  # `down -v` alone leaves orphan network/volume references in the daemon's
  # bookkeeping for a few seconds; if `up -d` starts during that window with
  # depends_on { condition: service_healthy }, compose ends up polling stale
  # container IDs and dies with: "dependency failed to start: ... No such
  # container: <hash>". `--remove-orphans` + a brief settle wait avoids it.
  docker compose -f "$PLANE_COMPOSE" down -v --remove-orphans 2>/dev/null || true
  log_info "Existing containers removed (waiting 3 s for daemon to reconcile)"
  sleep 3
fi

# =============================================================================
# STEP 2: Pull images (slow first time)
# =============================================================================
log_step "Pulling Plane images (makeplane/plane-*:stable)..."
docker compose -f "$PLANE_COMPOSE" pull --quiet 2>/dev/null || \
  log_warn "Image pull had warnings — continuing (images may already be cached)"

# =============================================================================
# STEP 3: Start the stack
# =============================================================================
log_step "Starting Plane stack (7 containers)..."

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "oss-plane-proxy$"; then
  log_info "oss-plane-proxy is already running"
else
  if ! docker compose -f "$PLANE_COMPOSE" up -d; then
    log_error "Failed to start Plane"
    exit 1
  fi
fi

# =============================================================================
# STEP 4: Wait for proxy / web (up to 600 s — cold-boot migrations + warmup)
# =============================================================================
# Plane's first-boot path is: postgres init -> django migrations -> minio
# bucket create -> api warmup -> space warmup -> web warmup -> caddy ready.
# In the real world this routinely takes 4-8 minutes on a cold cache, so we
# wait up to 10 minutes. Every 30 s we log which plane containers are healthy
# (or merely Up), and we fail FAST only if the proxy is actually crash-looping.
log_step "Waiting for Plane at ${PLANE_URL} (up to 600 s — first boot can take 4-8 minutes)..."

PLANE_CONTAINERS=(
  oss-plane-proxy
  oss-plane-web
  oss-plane-space
  oss-plane-db
  oss-plane-redis
  oss-plane-api
  oss-plane-worker
  oss-plane-beat
  oss-plane-minio
)

# Returns "healthy" / "up" / "restarting" / "missing" / <docker status> for a name.
plane_container_state() {
  local name="$1"
  local status health
  status=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || echo missing)
  health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$name" 2>/dev/null || true)
  if [ -n "$health" ]; then
    echo "$health"
  else
    echo "$status"
  fi
}

# Count how many plane containers are healthy or running (no healthcheck).
plane_ready_count() {
  local ready=0 name state
  for name in "${PLANE_CONTAINERS[@]}"; do
    state=$(plane_container_state "$name")
    case "$state" in
      healthy|running) ready=$((ready + 1)) ;;
    esac
  done
  echo "$ready"
}

WAIT_DEADLINE=$(( $(date +%s) + 600 ))
LAST_PROGRESS=0
PROXY_CRASHLOOP=0

while [ "$(date +%s)" -lt "$WAIT_DEADLINE" ]; do
  if curl -sf "${PLANE_URL}/" >/dev/null 2>&1; then
    break
  fi

  # Crash-loop short-circuit: if proxy is restarting AND has flapped >2 times,
  # waiting longer won't help — it's a config error, surface it now.
  proxy_state_now=$(docker inspect -f '{{.State.Status}}' oss-plane-proxy 2>/dev/null || echo missing)
  proxy_restarts_now=$(docker inspect -f '{{.RestartCount}}' oss-plane-proxy 2>/dev/null || echo 0)
  if [ "$proxy_state_now" = "restarting" ] && [ "${proxy_restarts_now:-0}" -gt 2 ]; then
    PROXY_CRASHLOOP=1
    break
  fi

  # Log progress every ~30 s (six 5-second sleeps).
  now=$(date +%s)
  if [ $(( now - LAST_PROGRESS )) -ge 30 ]; then
    ready=$(plane_ready_count)
    total=${#PLANE_CONTAINERS[@]}
    elapsed=$(( now - (WAIT_DEADLINE - 600) ))
    log_info "  ... ${elapsed}s elapsed — ${ready}/${total} plane containers healthy/up; proxy=${proxy_state_now} (restarts=${proxy_restarts_now})"
    LAST_PROGRESS=$now
  else
    printf "  . "
  fi
  sleep 5
done
echo ""

if ! curl -sf "${PLANE_URL}/" >/dev/null 2>&1; then
  # Re-inspect at decision time so the report reflects actual final state,
  # not whatever we observed mid-wait.
  proxy_state=$(docker inspect -f '{{.State.Status}}' oss-plane-proxy 2>/dev/null || echo unknown)
  proxy_restarts=$(docker inspect -f '{{.RestartCount}}' oss-plane-proxy 2>/dev/null || echo 0)
  ready_final=$(plane_ready_count)
  total=${#PLANE_CONTAINERS[@]}

  # Three buckets:
  #   (a) crash-loop          -> hard fail, config error
  #   (b) all containers up   -> WARN "still warming, wait longer", exit 1
  #   (c) some containers     -> hard fail, genuine breakage
  #       not up
  if [ "$PROXY_CRASHLOOP" -eq 1 ] || [ "$proxy_state" = "restarting" ] || [ "${proxy_restarts:-0}" -gt 2 ]; then
    log_error "Plane proxy at ${PLANE_URL} is CRASH-LOOPING — broken, not slow"
    log_error "  -> WHAT WAS CHECKED: curl -sf ${PLANE_URL}/  (poll for up to 600 s)"
    log_error "  -> CONTAINER STATE:  oss-plane-proxy = $proxy_state, restarts = $proxy_restarts"
    log_error "  -> CONTAINERS UP:    ${ready_final}/${total} healthy or running"
    log_error "  -> WHY IT FAILS:     proxy keeps exiting and being restarted by docker — config error,"
    log_error "                       not migrations. Waiting longer will not help."
    log_error "  -> COMMON CAUSE:     makeplane/plane-proxy:stable Caddyfile expects SITE_ADDRESS,"
    log_error "                       BUCKET_NAME, FILE_SIZE_LIMIT env vars + bare-name DNS aliases"
    log_error "                       (api/web/space). docker-compose.yml in infra/plane/ should set"
    log_error "                       these — re-pull the latest version of the file."
    log_error "  -> CHECK LOGS:       docker logs oss-plane-proxy"
    exit 1
  elif [ "$ready_final" -eq "$total" ]; then
    log_warn "Plane proxy at ${PLANE_URL} not yet returning 200 after 600 s — but ALL containers are up."
    log_warn "  -> STATUS:           STILL WARMING UP (not broken)"
    log_warn "  -> CONTAINERS UP:    ${ready_final}/${total} healthy or running"
    log_warn "  -> CONTAINER STATE:  oss-plane-proxy = $proxy_state, restarts = $proxy_restarts"
    log_warn "  -> WHY:              first-boot django migrations + asset compile can exceed 10 min"
    log_warn "                       on a cold cache. The install is most likely fine — just slow."
    log_warn "  -> NEXT STEPS:       1) wait another 2-5 minutes, then:"
    log_warn "                          curl -I ${PLANE_URL}/"
    log_warn "                          bash scripts/infra/plane.sh --check"
    log_warn "                       2) if still hanging, inspect the slow container:"
    log_warn "                          docker logs --tail 200 oss-plane-api"
    log_warn "                          docker logs --tail 200 oss-plane-web"
    log_warn "                          docker logs --tail 200 oss-plane-proxy"
    log_warn "  -> EXIT CODE:        1 (we will not falsely claim success while the URL is down)"
    exit 1
  else
    log_error "Plane did not start up correctly — ${ready_final}/${total} containers healthy after 600 s"
    log_error "  -> WHAT WAS CHECKED: curl -sf ${PLANE_URL}/  (poll for up to 600 s)"
    log_error "  -> CONTAINER STATE:  oss-plane-proxy = $proxy_state, restarts = $proxy_restarts"
    log_error "  -> CONTAINERS UP:    ${ready_final}/${total} healthy or running"
    log_error "  -> WHY IT FAILS:     one or more plane containers never reached healthy/running."
    log_error "                       This is a genuine breakage, not slow first-boot."
    log_error "  -> CHECK LOGS:       docker compose -f $PLANE_COMPOSE ps"
    log_error "                       docker logs oss-plane-api"
    log_error "                       docker logs oss-plane-db"
    log_error "                       docker logs oss-plane-proxy"
    log_error "  -> RETRY:            bash scripts/infra/plane.sh --force"
    exit 1
  fi
fi
log_info "Plane ready at ${PLANE_URL}"
log_info "Default login: admin@oss-learn.local / admin1234"

# =============================================================================
# STEP 5: Write install manifest
# =============================================================================
write_manifest plane \
  location=local \
  container=oss-plane-proxy \
  image="makeplane/plane-proxy:stable" \
  web_url="${PLANE_URL}" \
  compose_file="$PLANE_COMPOSE" \
  data_dir="$PLANE_DIR/data"

log_info "Install manifest written: $MANIFEST_DIR/plane.yaml"
log_pass "Plane Self-Hosted (localhost:4000)" \
  "docker compose up -d for 9 Plane containers, then HTTP GET ${PLANE_URL}/ until 200 OK (max 600s for first-boot migrations + warmup)" \
  "oss-plane-proxy/api/web containers started from makeplane/plane-*:stable; proxy responded on ${PLANE_URL}; default login admin@oss-learn.local / admin1234" \
  "compose=$PLANE_COMPOSE, container=oss-plane-proxy, web_url=${PLANE_URL}, data_dir=$PLANE_DIR/data, manifest=$MANIFEST_DIR/plane.yaml" \
  "open ${PLANE_URL} in a browser, or run: bash scripts/infra/plane.sh --check"
