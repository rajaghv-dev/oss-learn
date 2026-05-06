#!/bin/bash
# oss-learn setup — step 1 of 3
# Usage: bash setup.sh [options]  →  bash validate.sh  →  bash start.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$REPO_ROOT/scripts/setup/main.sh" "$@"
