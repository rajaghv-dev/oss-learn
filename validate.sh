#!/bin/bash
# oss-learn validate — step 2 of 3
# Usage: bash validate.sh [--quick] [--suite <name>]
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$REPO_ROOT/scripts/validate/main.sh" "$@"
