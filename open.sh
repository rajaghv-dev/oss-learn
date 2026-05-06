#!/bin/bash
# oss-learn open — probe every known service port and open the running ones
# in a browser. Pairs with start.sh.
# Usage: bash open.sh [--list]
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$REPO_ROOT/scripts/open.py" "$@"
