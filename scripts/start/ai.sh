#!/bin/bash
# Start ai (Start Phase - Deployment)
# PURPOSE: Starts ai services/containers.
# USAGE: bash scripts/start/ai.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$REPO_ROOT/scripts/common.sh"
set_script_log "start_ai"

log_info "Starting ai..."
log_info "  Log: $SCRIPT_LOG"

case "ai" in
  docker)
    if ! command -v docker &>/dev/null; then
      log_error "Docker not found"
      exit 1
    fi
    if ! docker info &>/dev/null; then
      log_step "Starting Docker daemon..."
      sudo systemctl start docker 2>/dev/null || true
    fi
    log_info "Docker is running"
    ;;
  database)
    log_step "Starting PostgreSQL container..."
    bash "$REPO_ROOT/scripts/start/database.sh" "$@" 2>&1 | tee -a "$LOG_FILE" "$SCRIPT_LOG"
    ;;
  registry)
    log_step "Starting Docker Registry..."
    if ! docker ps -a --format '{{.Names}}' | grep -q "oss-registry"; then
      log_info "Registry not found, running setup..."
      bash "$REPO_ROOT/scripts/setup/registry.sh"
    else
      docker start oss-registry 2>/dev/null || true
    fi
    log_info "Registry started"
    ;;
  ai)
    log_info "Starting AI services..."
    for svc in ollama llama_cpp; do
      log_step "Starting $svc..."
      bash "$REPO_ROOT/scripts/start/ai_${svc}.sh" "$@" 2>&1 | tee -a "$LOG_FILE" "$SCRIPT_LOG" || true
    done
    ;;
  observability)
    log_step "Starting Netdata..."
    bash "$REPO_ROOT/scripts/start/observability.sh" "$@" 2>&1 | tee -a "$LOG_FILE" "$SCRIPT_LOG" || true
    ;;
esac

log_info "RESULT: ai started"
exit 0
