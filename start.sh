#!/bin/bash
# oss-learn start — step 3 of 3
# Usage: bash start.sh [--ai] [--opensearch] [--no-obs]
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$REPO_ROOT/scripts/start/main.sh" "$@"
