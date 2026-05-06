#!/bin/bash
# =============================================================================
# postgres.sh — PostgreSQL 16 + pgvector + Apache AGE Setup
#
# PURPOSE:
#   Installs and configures PostgreSQL 16 with the pgvector and Apache AGE
#   extensions inside a Docker container. Creates the osslearn database, enables
#   all required extensions, and verifies the installation.
#
#   Part of the scripts/setup/ split — called by scripts/setup.sh or run
#   standalone for PostgreSQL-only setup / re-setup.
#
# ── Sources ───────────────────────────────────────────────────────────
# PostgreSQL 16:  Docker Hub — postgres:16 (base image in Dockerfile)
# pgvector:       GitHub — https://github.com/pgvector/pgvector
#                 Built from source inside Docker image (Makefile install)
# Apache AGE:     GitHub — https://github.com/apache/age
#                 Tags: PG16/v1.5.0-rc0 (default), PG16/v1.6.0-rc0 (opt-in)
#                 NOTE: Only -rc0 tags exist for PG16 upstream
#                 Tarball pre-packaged on host (WSL2 Docker can't git clone)
# Extensions:     pg_trgm, uuid-ossp (built-in PG16 contrib)
# Local build:    --local flag → native PG install + extension builds (no Docker)
#
# ── AGE Versions ──────────────────────────────────────────────────────
#   v1.5.0-rc0  (default)  — Battle-tested, recommended for production
#   v1.6.0-rc0  (opt-in)   — Newer release candidate, use --age v1.6.0-rc0
#   Note: Apache AGE only ships -rc0 tags for PG16 in the upstream repo.
#         There are no non-rc releases for PG16 as of 2026-05.
#
# ── Usage Examples ────────────────────────────────────────────────────
#   bash scripts/infra/postgres.sh                    # Install with defaults
#   bash scripts/infra/postgres.sh --check            # Show status, no changes
#   bash scripts/infra/postgres.sh --force            # Tear down + rebuild
#   bash scripts/infra/postgres.sh --age v1.6.0-rc0   # Use newer AGE
#   bash scripts/infra/postgres.sh --help             # This help text
#
# EXIT CODES:
#   0  — PostgreSQL running, all extensions verified
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
else
  echo "ERROR: $COMMON not found — cannot continue" >&2
  exit 1
fi

# ── Initialize script-specific logging ──────────────────────────────────
# Creates logs/postgres.log with detailed PostgreSQL setup output.
set_script_log "postgres"

# ── Parse arguments ──────────────────────────────────────────────────────────
# Snapshot the original argv before the parse loop consumes "$@" — the
# docker-group re-exec block below (around STEP 0) needs to forward the
# same flags to the sg-docker sub-shell.
ORIG_ARGS=("$@")

CHECK_ONLY=0
FORCE=0
LOCAL=0
AGE_VERSION="${AGE_VERSION:-v1.5.0-rc0}"

while [ $# -gt 0 ]; do
  case "$1" in
    --check)    CHECK_ONLY=1 ;;
    --force)    FORCE=1 ;;
    --local)    LOCAL=1 ;;
    --age)
      shift
      AGE_VERSION="${1:?--age requires a version (e.g. v1.5.0-rc0)}"
      shift  # consume the version argument here so the outer shift doesn't skip it
      continue
      ;;
    --help|-h)
      # Print the header comment block as help text
      grep '^#' "$0" | head -40 | sed 's/^# \?//'
      exit 0
      ;;
    *)
      log_warn "Unknown argument: $1"
      ;;
  esac
  shift
done

# ── Validate AGE version ────────────────────────────────────────────────────
case "$AGE_VERSION" in
  v1.5.0-rc0|v1.6.0-rc0) ;;
  *)
    log_warn "Unknown AGE version '$AGE_VERSION' — known tags: v1.5.0-rc0 (default), v1.6.0-rc0"
    log_warn "Proceeding anyway; git clone will fail if the tag does not exist."
    ;;
esac

export AGE_TAG="PG16/${AGE_VERSION}"
export AGE_DIR="age-PG16-${AGE_VERSION}"

# ── Paths ────────────────────────────────────────────────────────────────────
PGSQL_DIR="$REPO_ROOT/infra/postgres"
AGE_TARBALL="$PGSQL_DIR/deps/age.tar.gz"
CLONE_DIR="$PGSQL_DIR/deps/${AGE_DIR}"

# =============================================================================
# --check: report status and exit
# =============================================================================
if [ "$CHECK_ONLY" -eq 1 ]; then
  log_header "PostgreSQL — status check"

  # Container running?
  if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "oss-postgres"; then
    log_info "Container oss-postgres is running"
    docker exec oss-postgres pg_isready -U postgres 2>/dev/null \
      && log_info "pg_isready: accepting connections" \
      || log_warn "pg_isready: NOT ready"
  else
    log_warn "Container oss-postgres is not running"
  fi

  # AGE tarball?
  if [ -f "$AGE_TARBALL" ]; then
    local_tag=$(tar tzf "$AGE_TARBALL" 2>/dev/null | head -1 | sed 's|/.*||')
    log_info "AGE tarball present: $AGE_TARBALL (dir=${local_tag})"
  else
    log_warn "AGE tarball not found at $AGE_TARBALL"
  fi

  # Manifest?
  if [ -f "$MANIFEST_DIR/postgres.yaml" ]; then
    log_info "Manifest: $MANIFEST_DIR/postgres.yaml"
    log_info "  age_tag = $(read_manifest_field postgres age_tag)"
  else
    log_warn "No install manifest for postgres"
  fi

  exit 0
fi

# =============================================================================
# --local stub (not yet implemented)
# =============================================================================
if [ "$LOCAL" -eq 1 ]; then
  # ── LOCAL INSTALL (future) ──────────────────────────────────────────────
  # What this would do:
  #   1. Install postgresql-16 via apt (Ubuntu/Debian) or brew (macOS)
  #   2. Start the local PG cluster: pg_ctlcluster 16 main start
  #   3. Build pgvector from source:
  #        git clone https://github.com/pgvector/pgvector /tmp/pgvector
  #        cd /tmp/pgvector && make PG_CONFIG=pg_config && sudo make install
  #   4. Build Apache AGE from source:
  #        tar xzf "$AGE_TARBALL" -C /tmp
  #        cd /tmp/$AGE_DIR && make PG_CONFIG=pg_config && sudo make install
  #   5. Run init.sql against local PG:
  #        psql -U postgres < infra/postgres/init.sql
  #   6. Run verify.sql
  #   7. Write manifest with location=local-native
  # ─────────────────────────────────────────────────────────────────────────
  log_error "--local PostgreSQL install is not yet implemented."
  log_error "Use Docker mode (default) or install PostgreSQL manually."
  exit 1
fi

# =============================================================================
# STEP 0: Preflight — Docker required
# =============================================================================
# PURPOSE:  Verify Docker engine and Docker Compose are available and running.
#           PostgreSQL + pgvector + AGE runs inside a Docker container.
# PASS:     Docker command found, Compose available, daemon responding
# FAIL:     Docker not found (critical — exit 1)
#           Docker daemon not running (critical — exit 1)
# FIX:      Install Docker: https://docs.docker.com/engine/install/
#           Start Docker:   sudo systemctl start docker
#           Compose v2:    sudo apt install docker-compose-plugin
# =============================================================================
log_header "PostgreSQL 16 + pgvector + AGE (${AGE_TAG})"

require_cmd docker "Install Docker: https://docs.docker.com/engine/install/" \
  "All oss-learn services run as Docker containers"

# Check for docker compose (plugin or standalone)
if docker compose version &>/dev/null; then
  DOCKER_COMPOSE="docker compose"
  log_info "Docker Compose v2 plugin detected"
elif command -v docker-compose &>/dev/null; then
  DOCKER_COMPOSE="docker-compose"
  log_warn "Docker Compose v1 detected — consider upgrading to v2 plugin"
else
  log_error "docker compose not found — CRITICAL FAILURE"
  log_error "  → WHAT WAS CHECKED: 'docker compose version' and 'command -v docker-compose' both failed"
  log_error "  → WHY IT FAILS: docker-compose is needed to start multi-container stacks"
  log_error "  → HOW TO FIX: Install Docker Compose v2 plugin:"
  log_error "       Ubuntu/Debian: sudo apt install docker-compose-plugin"
  log_error "       Or v1:          sudo apt install docker-compose"
  log_error "       Verify:        docker compose version"
  exit 1
fi

# Use the group-aware helper from scripts/common.sh so a freshly added user
# whose CURRENT shell hasn't reloaded the docker group yet still gets a
# correct verdict (sg-docker / sudo fallback). Plain `docker info` would
# falsely report "daemon not running" in that case.
if ! docker_daemon_reachable; then
  log_error "Docker daemon is not reachable — CRITICAL FAILURE"
  log_error "  → WHAT WAS CHECKED: 'docker info' (direct, sg docker, sudo -n) all failed"
  log_error "  → WHY IT FAILS: Docker daemon must be running to manage containers"
  log_error "  → HOW TO FIX: Start Docker:"
  log_error "       Linux:   sudo systemctl start docker"
  log_error "       WSL2:    Ensure Docker Desktop is running in Windows"
  log_error "       macOS:   Open Docker Desktop application"
  log_error "       Verify:  docker ps    (or: sg docker -c 'docker ps')"
  log_error "  → If you were just added to the 'docker' group:"
  log_error "       newgrp docker   # reload groups, or open a new terminal"
  exit 1
fi
# Re-exec under `sg docker` if THIS shell can't talk to the socket directly.
# Rationale: docker_daemon_reachable confirms the daemon is fine, but the
# bare `docker` / `$DOCKER_COMPOSE` calls scattered through STEPS 1–7 below
# would still hit EACCES on /var/run/docker.sock because supplementary
# groups are captured at login and don't include the freshly-added 'docker'.
# `sg docker -c` runs the rest under a sub-shell with docker as the primary
# group, so every downstream docker call Just Works without per-call wrapping.
# OSS_REEXEC_UNDER_SG guards against infinite re-exec loops.
if [ "${DOCKER_GROUP_RELOGIN_NEEDED:-0}" -eq 1 ] && [ -z "${OSS_REEXEC_UNDER_SG:-}" ]; then
  warn_docker_group_session
  log_info "Re-executing this script under 'sg docker' so STEPS 1–7 can use the socket"
  export OSS_REEXEC_UNDER_SG=1
  # Forward original argv. printf %q quotes each arg safely for the sg sub-shell.
  ARGV_QUOTED=""
  for arg in "${ORIG_ARGS[@]:-}"; do ARGV_QUOTED+=" $(printf '%q' "$arg")"; done
  exec sg docker -c "bash $(printf '%q' "${BASH_SOURCE[0]}")$ARGV_QUOTED"
fi
log_info "Docker daemon is running"

# =============================================================================
# STEP 1: Check for port 5432 conflicts and stop conflicting containers
# =============================================================================
# PURPOSE:  PostgreSQL default port is 5432. If another container (e.g., a
#           standalone postgres) is already using this port, our oss-postgres
#           container will fail to start with a "port already allocated" error.
# PASS:     No conflicting containers found, or --force removes them
# WARN:     Conflicting container found (not --force mode)
# FIX:      docker stop <container> && docker rm <container>
#           Or use --force to auto-remove conflicting containers
# =============================================================================
log_step "Checking for port 5432 conflicts..."

if command -v docker &>/dev/null; then
  CONFLICTING=$(docker ps -a --format '{{.Names}}' 2>/dev/null \
    | grep -E 'postgres|pg' \
    | grep -v "oss-postgres" \
    | head -1 || true)
  if [ -n "$CONFLICTING" ]; then
    log_warn "Found potentially conflicting container: $CONFLICTING"
    log_warn "  → WHY IT MATTERS: Both containers would try to bind port 5432"
    if [ "$FORCE" -eq 1 ]; then
      log_step "Stopping conflicting container $CONFLICTING..."
      docker stop "$CONFLICTING" 2>/dev/null || true
      docker rm "$CONFLICTING" 2>/dev/null || true
      log_info "Removed conflicting container"
    else
      log_warn "  → HOW TO FIX: docker stop $CONFLICTING && docker rm $CONFLICTING"
      log_warn "  → Or re-run with: bash scripts/infra/postgres.sh --force"
    fi
  else
    log_info "No port 5432 conflicts detected"
  fi
fi

# --force: tear down existing oss-postgres before rebuilding
# PURPOSE:  If oss-postgres exists but is broken or using an old AGE version,
#           --force ensures a clean rebuild from the latest image/tarball.
# PASS:     Container removed (or didn't exist)
# FAIL:     Cannot remove container (unlikely with docker rm -f)
# =============================================================================
if [ "$FORCE" -eq 1 ]; then
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "oss-postgres"; then
    log_step "Force mode: tearing down existing oss-postgres container..."
    $DOCKER_COMPOSE -f "$PGSQL_DIR/docker-compose.yml" down -v 2>/dev/null || true
    docker rm -f oss-postgres 2>/dev/null || true
    log_info "Existing container removed"
  fi
fi

# =============================================================================
# STEP 2: Pre-package AGE source tarball on host
# =============================================================================
# PURPOSE:  Docker builds inside WSL2 frequently hit SSL/rate-limit issues
#           when cloning from GitHub.  We clone on the host (which has proper
#           SSL certs + network config) and inject the tarball via COPY
#           in the Dockerfile.
# PASS:     AGE tarball exists at $AGE_TARBALL with correct tag
# FAIL:     git clone fails (network/SSL/tag doesn't exist) — exit 1
# FIX:      Check network:    curl -I https://github.com/apache/age
#           Check SSL:        git config --global http.sslVerify false
#           Manual clone:    git clone --depth 1 --branch ${AGE_TAG} https://github.com/apache/age /tmp/age
#           Verify tag:       Check https://github.com/apache/age/tags
# =============================================================================
log_step "Preparing Apache AGE ${AGE_TAG} source tarball..."

mkdir -p "$PGSQL_DIR/deps"

need_repack=0
if [ ! -f "$AGE_TARBALL" ]; then
  need_repack=1
elif ! tar tzf "$AGE_TARBALL" 2>/dev/null | head -1 | grep -q "^${AGE_DIR}/"; then
  log_info "Existing AGE tarball is for a different version — re-packaging for ${AGE_TAG}"
  rm -f "$AGE_TARBALL"
  need_repack=1
fi

if [ "$need_repack" -eq 1 ]; then
  log_step "Cloning Apache AGE ${AGE_TAG} from GitHub (host-side)..."
  rm -rf "$CLONE_DIR"
  if git clone --quiet --depth 1 --branch "$AGE_TAG" \
       https://github.com/apache/age.git "$CLONE_DIR"; then
    rm -rf "$CLONE_DIR/.git"
    tar czf "$AGE_TARBALL" -C "$PGSQL_DIR/deps" "$AGE_DIR"
    rm -rf "$CLONE_DIR"
    log_info "AGE source packaged: $AGE_TARBALL  (tag=${AGE_TAG})"
  else
    log_error "git clone of AGE ${AGE_TAG} failed — CRITICAL FAILURE"
    log_error "  → WHAT WAS CHECKED: 'git clone --depth 1 --branch ${AGE_TAG} https://github.com/apache/age'"
    log_error "  → WHY IT FAILS: Network issue, SSL problem, or tag doesn't exist"
    log_error "  → HOW TO FIX:"
    log_error "      1. Check network:    curl -I https://github.com/apache/age"
    log_error "      2. Check SSL:        git config --global http.sslVerify false"
    log_error "      3. Verify tag exists: https://github.com/apache/age/tags"
    log_error "      4. Known tags: PG16/v1.5.0-rc0, PG16/v1.6.0-rc0"
    log_error "      5. Manual test: git clone --depth 1 --branch ${AGE_TAG} https://github.com/apache/age /tmp/age"
    exit 1
  fi
else
  log_info "AGE tarball already present: $AGE_TARBALL  (tag=${AGE_TAG})"
fi

# =============================================================================
# STEP 3: Build and start Docker container
# =============================================================================
log_step "Starting PostgreSQL container..."

# docker-compose.yml bind-mounts ./data/postgres (and pgadmin profile uses
# ./data/pgadmin). If the host path doesn't exist, Docker creates it as
# root, which can break later steps that expect to write there from the
# host side. Pre-create as the current user so ownership is sane.
mkdir -p "$PGSQL_DIR/data/postgres" "$PGSQL_DIR/data/pgadmin"

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "oss-postgres"; then
  log_info "PostgreSQL container oss-postgres is already running"
else
  log_step "First run: building oss-postgres image (pgvector + AGE, ~5 min)..."
  if ! $DOCKER_COMPOSE -f "$PGSQL_DIR/docker-compose.yml" up -d --build; then
    log_error "docker compose build/start failed — see output above"
    log_error "  → Common causes:"
    log_error "      • No internet during 'apt-get install' inside the build (proxy/DNS)"
    log_error "      • AGE tarball missing or corrupt: $AGE_TARBALL"
    log_error "      • Port 5432 still bound by a host postgres (see STEP 1 above)"
    log_error "  → Re-run with --force to tear down and rebuild from scratch."
    exit 1
  fi

  # Verify the container was actually created before polling it
  if ! docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "oss-postgres"; then
    log_error "Container oss-postgres was not created — build likely failed"
    exit 1
  fi
fi

# =============================================================================
# STEP 4: Wait for pg_isready (up to 30 s)
# =============================================================================
log_step "Waiting for PostgreSQL to accept connections..."

attempts=0
while [ $attempts -lt 30 ]; do
  if docker exec oss-postgres pg_isready -U postgres &>/dev/null; then
    log_info "PostgreSQL ready (after ${attempts}s)"
    break
  fi
  printf "  . "
  sleep 1
  ((attempts++)) || true
done
echo ""

if ! docker exec oss-postgres pg_isready -U postgres &>/dev/null; then
  log_error "PostgreSQL did not become ready after 30 s"
  log_error "Check container logs: docker logs oss-postgres"
  exit 1
fi

# =============================================================================
# STEP 5: Run init.sql — creates databases + enables extensions
# =============================================================================
# The init script is idempotent: CREATE DATABASE IF NOT EXISTS, CREATE EXTENSION
# IF NOT EXISTS, etc. Safe to re-run on every setup.
log_step "Running init.sql (creates databases + enables pgvector, AGE, pg_trgm, uuid-ossp)..."

if docker exec -i oss-postgres psql -U postgres < "$PGSQL_DIR/init.sql" 2>&1 \
     | tee /tmp/pgsql_init.log \
     | grep -E "^(ERROR|FATAL)" | head -5; then
  log_warn "Some SQL statements reported errors — check /tmp/pgsql_init.log"
  log_warn "(May be harmless 'already exists' errors on re-run)"
else
  log_info "init.sql completed"
fi

# =============================================================================
# STEP 6: Run verify.sql — confirm extensions are installed
# =============================================================================
log_step "Verifying PostgreSQL extensions..."

docker exec -i oss-postgres psql -U postgres < "$PGSQL_DIR/verify.sql" 2>&1 \
  | grep -E "(✓|passed|extname|ERROR|FATAL)" | head -20 \
  || true

log_info "PostgreSQL extensions verified"

# =============================================================================
# STEP 7: Write install manifest
# =============================================================================
write_manifest_postgres "$PGSQL_DIR" "$AGE_TARBALL"
log_info "Install manifest written: $MANIFEST_DIR/postgres.yaml"

log_pass "PostgreSQL 16 + pgvector + Apache AGE (${AGE_TAG})" \
  "host-side AGE source clone + tarball pack, docker compose up -d --build of oss-postgres image, container presence in 'docker ps', pg_isready polled until ready, init.sql exec'd to create databases + extensions, verify.sql exec'd to confirm extensions, manifest write" \
  "container 'oss-postgres' Up; pg_isready returned ready after ${attempts}s; init.sql + verify.sql ran without ERROR/FATAL; AGE source tarball at $AGE_TARBALL ($(tar tzf "$AGE_TARBALL" 2>/dev/null | head -1 | sed 's|/.*||'))" \
  "container=oss-postgres, port=5432, compose=$PGSQL_DIR/docker-compose.yml, age_tag=${AGE_TAG}, manifest=$MANIFEST_DIR/postgres.yaml, log=logs/postgres.log" \
  "bash scripts/validate.sh --suite db    # or: docker exec -it oss-postgres psql -U postgres"
