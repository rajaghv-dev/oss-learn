#!/bin/bash
# =============================================================================
# scripts/start/ports.sh — Show parking microservice URLs (start-phase)
#
# Thin wrapper around scripts/ports.sh that filters to the workloads brought
# up by start.sh: the 12 parking microservices and the stub pods. Setup-phase
# infrastructure (postgres, AI servers, observability, tools) is NOT shown
# here — use `bash scripts/ports.sh` for that.
#
# USAGE:
#   bash scripts/start/ports.sh                # parking microservices table
#   bash scripts/start/ports.sh --all-open     # open every healthy URL
#   bash scripts/start/ports.sh --open oss-learn-app
#   bash scripts/start/ports.sh --json
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/../ports.sh" --phase start "$@"
