#!/bin/bash
# oss-learn cleanup — removes containers, data, state stamps, and venv
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

echo "Stopping and removing oss-learn containers..."
docker compose -f infra/postgres/docker-compose.yml down -v 2>/dev/null || true
docker compose -f infra/observability/docker-compose.yml down -v 2>/dev/null || true
docker compose -f infra/opensearch/docker-compose.yml down -v 2>/dev/null || true

echo "Removing state stamps..."
rm -rf setup/state logs

echo "Removing Python venv..."
rm -rf venv

echo "Done. Run 'bash setup.sh' to start fresh."
