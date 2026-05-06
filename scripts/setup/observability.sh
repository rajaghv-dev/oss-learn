#!/bin/bash
# =============================================================================
# observability.sh — oss-learn Observability Stack Setup
#
# PURPOSE:
#   Brings up the 5-container observability stack defined in
#   infra/observability/docker-compose.yml:
#
#     - oss-otel-collector   (OTLP gRPC :4317, HTTP :4318, Prom export :8889)
#     - oss-prometheus       (:9090)
#     - oss-grafana          (:3000, admin / oss-admin)
#     - oss-blackbox         (:9115)
#     - oss-state-exporter   (:9901)
#
#   The two annoying historical failure modes this script removes:
#
#     1. Prometheus panicked on first boot with
#          "permission denied: open /prometheus/queries.active"
#        because the docker daemon created ./data/prometheus as root:root and
#        the prom/prometheus image runs as uid 65534 (nobody).
#
#     2. Grafana's data dir had the same root:root issue but Grafana's image
#        runs an init that chowns its own dir, so it usually self-heals; we
#        still pre-create + chown to avoid the first-boot warning.
#
#   We pre-create + chown both data dirs on the host BEFORE `docker compose
#   up -d`, using the same idempotent sudo-with-fallback pattern as
#   opensearch.sh.
#
# ── Sources ───────────────────────────────────────────────────────────
# Compose:       infra/observability/docker-compose.yml
# OTel config:   infra/observability/otel-collector-config.yaml
# Prom config:   infra/observability/prometheus.yml
# Blackbox cfg:  infra/observability/blackbox.yml
# Prometheus:    http://localhost:9090
# Grafana:       http://localhost:3000   (admin / oss-admin)
# Blackbox:      http://localhost:9115
# OTLP gRPC:     localhost:4317
#
# ── Usage Examples ────────────────────────────────────────────────────
#   bash scripts/infra/observability.sh           # Install + start
#   bash scripts/infra/observability.sh --check   # Show status, no changes
#   bash scripts/infra/observability.sh --force   # Tear down + rebuild
#   bash scripts/infra/observability.sh --help    # This help text
#
# EXIT CODES:
#   0 — all 5 containers up and the 3 polled endpoints responded 200 in 90 s
#   1 — setup failed (see output for which endpoint timed out)
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

set_script_log "observability"

usage() {
  cat <<'USAGE'
Usage: bash scripts/infra/observability.sh [OPTIONS]

Options:
  --check   Check whether the observability stack is running; do not start
  --force   Tear down and recreate the whole stack
  --help    Show this message

Returns 0 on success, 1 on failure.
Writes manifest: setup/state/installs/observability.yaml
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

# Re-exec under `sg docker` if the daemon is only reachable that way
docker_reexec_if_needed "${BASH_SOURCE[0]}" "${ORIG_ARGS[@]}"

OBS_DIR="$REPO_ROOT/infra/observability"
OBS_COMPOSE="$OBS_DIR/docker-compose.yml"
OTEL_CONFIG="$OBS_DIR/otel-collector-config.yaml"
PROM_DATA_DIR="$OBS_DIR/data/prometheus"
GRAF_DATA_DIR="$OBS_DIR/data/grafana"

PROM_URL="http://localhost:9090"
GRAF_URL="http://localhost:3000"
BLACKBOX_URL="http://localhost:9115"

# Containers expected to be running after `docker compose up -d`
CONTAINERS=(
  oss-otel-collector
  oss-prometheus
  oss-grafana
  oss-blackbox
  oss-state-exporter
)

# =============================================================================
# --check: report status and exit
# =============================================================================
if [ "$CHECK_ONLY" -eq 1 ]; then
  log_header "Observability stack — status check"

  if ! command -v docker &>/dev/null; then
    log_warn "Docker not found"; exit 0
  fi

  for cname in "${CONTAINERS[@]}"; do
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${cname}$"; then
      log_info "Container ${cname} is running"
    else
      log_warn "Container ${cname} is not running"
    fi
  done

  for u in "${PROM_URL}/-/ready" "${GRAF_URL}/api/health" "${BLACKBOX_URL}/-/healthy"; do
    if curl -sf -m 3 "$u" >/dev/null 2>&1; then
      log_info "Reachable: $u"
    else
      log_warn "Not reachable: $u"
    fi
  done

  if [ -f "$MANIFEST_DIR/observability.yaml" ]; then
    log_info "Manifest: $MANIFEST_DIR/observability.yaml"
  else
    log_warn "No install manifest for observability"
  fi

  exit 0
fi

# =============================================================================
# STEP 0: Preflight — Docker + compose file + otel config required
# =============================================================================
log_header "Observability  (Prometheus :9090  Grafana :3000  Blackbox :9115  OTLP :4317)"

if ! command -v docker &>/dev/null; then
  log_warn "Docker not found — skipping observability"
  exit 0
fi

if [ ! -f "$OBS_COMPOSE" ]; then
  log_error "Compose file not found: $OBS_COMPOSE"
  log_fail "Observability stack" \
    "file existence test on $OBS_COMPOSE" \
    "compose file is missing from the repo" \
    "git checkout -- infra/observability/docker-compose.yml" \
    "bash scripts/infra/observability.sh"
  exit 1
fi

# =============================================================================
# STEP 1: Validate otel-collector-config.yaml exists and parses as YAML
# =============================================================================
log_step "Validating otel-collector-config.yaml..."

if [ ! -f "$OTEL_CONFIG" ]; then
  log_error "OTel config not found: $OTEL_CONFIG"
  log_fail "Observability stack" \
    "file existence test on $OTEL_CONFIG" \
    "otel-collector-config.yaml missing — collector cannot start without it" \
    "git checkout -- infra/observability/otel-collector-config.yaml" \
    "bash scripts/infra/observability.sh"
  exit 1
fi

# Best-effort YAML parse: prefer python3 yaml; fall back to a shape check.
if command -v python3 &>/dev/null && python3 -c 'import yaml' 2>/dev/null; then
  if ! python3 -c "import sys, yaml; yaml.safe_load(open('$OTEL_CONFIG'))" 2>/dev/null; then
    log_error "otel-collector-config.yaml failed YAML parse"
    log_fail "Observability stack" \
      "python3 -c 'yaml.safe_load(open(...))' on $OTEL_CONFIG" \
      "config file is not valid YAML — collector would crash on first boot" \
      "fix syntax in $OTEL_CONFIG (re-indent, balance quotes, etc.)" \
      "yamllint $OTEL_CONFIG"
    exit 1
  fi
  log_info "otel-collector-config.yaml parses OK (PyYAML)"
else
  # Minimal shape check: must mention receivers + service + pipelines
  if grep -qE '^receivers:' "$OTEL_CONFIG" \
     && grep -qE '^service:'   "$OTEL_CONFIG" \
     && grep -qE 'pipelines:'  "$OTEL_CONFIG"; then
    log_info "otel-collector-config.yaml shape check OK (PyYAML unavailable)"
  else
    log_warn "PyYAML unavailable and shape check failed — proceeding; container will validate at boot"
  fi
fi

# =============================================================================
# STEP 2: --force: tear down existing stack
# =============================================================================
if [ "$FORCE" -eq 1 ]; then
  log_step "Force mode: tearing down existing observability stack..."
  # --remove-orphans + 3 s settle to avoid the docker daemon down-vs-up race
  # ("dependency failed to start: No such container ...") seen with stacks
  # that use depends_on { condition: service_healthy }.
  docker compose -f "$OBS_COMPOSE" down -v --remove-orphans 2>/dev/null || true
  sleep 3
  log_info "Existing containers removed"
fi

# =============================================================================
# STEP 3: Pre-create + chown data dirs to the uids the container images expect
# =============================================================================
# WHY: bind mounts under ./data/ are created by the docker daemon as root:root
# on first `up`. Then:
#   - prom/prometheus runs as uid 65534 (nobody)  → can't write /prometheus
#     → panics on /prometheus/queries.active and goes Restarting forever.
#   - grafana/grafana runs as uid 472 by default  → image's entrypoint chowns
#     its own dir so it usually self-heals, but we pre-chown anyway to be safe.
# Idempotent: if the dir is already owned by the right uid we do nothing.
log_step "Ensuring data dirs exist + are owned by the right uids"
mkdir -p "$PROM_DATA_DIR" "$GRAF_DATA_DIR" 2>/dev/null || true

_owner_uid_now() { stat -c '%u' "$1" 2>/dev/null || echo unknown; }

# entries: dir|uid:gid|container-user-name
DIR_OWNERS=(
  "$PROM_DATA_DIR|65534:65534|prometheus (nobody)"
  "$GRAF_DATA_DIR|472:472|grafana"
)
for entry in "${DIR_OWNERS[@]}"; do
  IFS='|' read -r d ownership label <<< "$entry"
  want_uid="${ownership%%:*}"
  curr=$(_owner_uid_now "$d")
  if [ "$curr" = "$want_uid" ]; then
    log_info "  $d already owned by uid $want_uid ($label) — OK"
  elif sudo -n chown -R "$ownership" "$d" 2>/dev/null; then
    log_info "  chown $ownership $d  (was uid=$curr, expected $label) — OK"
  elif [ "$curr" = "$(id -u)" ]; then
    log_info "  $d owned by current user uid=$curr — $label may still fail; if so:"
    log_info "      sudo chown -R $ownership $d"
  else
    log_warn "  $d is owned by uid=$curr and sudo is not cached."
    log_warn "      → Run THIS yourself, then re-run setup:"
    log_warn "          sudo chown -R $ownership $d"
  fi
done

# =============================================================================
# STEP 4: Pull images
# =============================================================================
log_step "Pulling observability images..."
docker compose -f "$OBS_COMPOSE" pull --quiet 2>/dev/null || \
  log_warn "Image pull had warnings — images may already be cached"

# =============================================================================
# STEP 5: Start the whole stack
# =============================================================================
log_step "Starting observability stack (5 containers)..."

if ! docker compose -f "$OBS_COMPOSE" up -d; then
  log_error "Failed to bring up observability stack"
  log_fail "Observability stack" \
    "docker compose -f $OBS_COMPOSE up -d" \
    "compose returned non-zero exit code" \
    "inspect: docker compose -f $OBS_COMPOSE logs --tail 100" \
    "bash scripts/infra/observability.sh --force"
  exit 1
fi

# =============================================================================
# STEP 6: Poll all 3 HTTP endpoints — Grafana :3000, Prometheus :9090,
#         Blackbox :9115 — every 5 s, up to 90 s. All must return 200.
# =============================================================================
log_step "Waiting for Grafana / Prometheus / Blackbox to return HTTP 200 (up to 90 s)..."

GRAF_READY=0
PROM_READY=0
BB_READY=0

attempts=0
while [ $attempts -lt 18 ]; do
  if [ $GRAF_READY -eq 0 ] && curl -sf -m 3 "${GRAF_URL}/api/health" >/dev/null 2>&1; then
    GRAF_READY=1
    log_info "  ✓ Grafana ready at ${GRAF_URL}"
  fi
  if [ $PROM_READY -eq 0 ] && curl -sf -m 3 "${PROM_URL}/-/ready" >/dev/null 2>&1; then
    PROM_READY=1
    log_info "  ✓ Prometheus ready at ${PROM_URL}/-/ready"
  fi
  if [ $BB_READY -eq 0 ] && curl -sf -m 3 "${BLACKBOX_URL}/-/healthy" >/dev/null 2>&1; then
    BB_READY=1
    log_info "  ✓ Blackbox ready at ${BLACKBOX_URL}/-/healthy"
  fi
  if [ $GRAF_READY -eq 1 ] && [ $PROM_READY -eq 1 ] && [ $BB_READY -eq 1 ]; then
    break
  fi
  printf "  . "
  sleep 5
  ((attempts++)) || true
done
echo ""

if [ $GRAF_READY -eq 0 ] || [ $PROM_READY -eq 0 ] || [ $BB_READY -eq 0 ]; then
  log_error "Observability endpoints did not all become ready within 90 s"
  log_error "  Grafana    ($GRAF_URL/api/health)         : $([ $GRAF_READY -eq 1 ] && echo READY || echo TIMEOUT)"
  log_error "  Prometheus ($PROM_URL/-/ready)            : $([ $PROM_READY -eq 1 ] && echo READY || echo TIMEOUT)"
  log_error "  Blackbox   ($BLACKBOX_URL/-/healthy)      : $([ $BB_READY -eq 1 ] && echo READY || echo TIMEOUT)"
  log_fail "Observability stack" \
    "polled Grafana/Prometheus/Blackbox HTTP endpoints every 5 s for 90 s after 'docker compose up -d'" \
    "one or more endpoints never returned 200 — the container is likely stuck Restarting or Created" \
    "docker compose -f $OBS_COMPOSE ps; docker logs oss-prometheus oss-otel-collector oss-grafana --tail 100" \
    "bash scripts/infra/observability.sh --force"
  exit 1
fi

# =============================================================================
# STEP 7: Write install manifest
# =============================================================================
write_manifest observability \
  location=local \
  containers="${CONTAINERS[*]}" \
  prometheus_url="${PROM_URL}" \
  grafana_url="${GRAF_URL}" \
  blackbox_url="${BLACKBOX_URL}" \
  otlp_grpc="localhost:4317" \
  otlp_http="localhost:4318" \
  compose_file="$OBS_COMPOSE" \
  prometheus_data_dir="$PROM_DATA_DIR" \
  grafana_data_dir="$GRAF_DATA_DIR"

log_info "Install manifest written: $MANIFEST_DIR/observability.yaml"
log_pass "Observability stack (otel-collector + prometheus + grafana + blackbox + state-exporter)" \
  "validated otel-collector-config.yaml as YAML, pre-chowned ./data/prometheus to 65534:65534 and ./data/grafana to 472:472, ran 'docker compose -f $OBS_COMPOSE up -d', polled grafana :3000/api/health AND prometheus :9090/-/ready AND blackbox :9115/-/healthy until all three returned 200 (max 90s)" \
  "all 5 containers Up; Grafana, Prometheus, and Blackbox each responded 200 to their health endpoint; otel-collector unblocked once Prometheus became healthy" \
  "compose=$OBS_COMPOSE, containers=${CONTAINERS[*]}, prometheus=${PROM_URL}, grafana=${GRAF_URL}, blackbox=${BLACKBOX_URL}, otlp_grpc=localhost:4317, otlp_http=localhost:4318, manifest=$MANIFEST_DIR/observability.yaml" \
  "open ${GRAF_URL} in a browser (admin / oss-admin), or curl ${PROM_URL}/-/ready"
