#!/usr/bin/env bash
# troupely heartbeat hook — run the memory linter and surface drift.
# Call this from your heartbeat playbook (or a Claude Code Stop/heartbeat hook).
# Exits 0 + silent when memory is clean; exits nonzero + prints findings to stderr otherwise.
#
#   framework/heartbeat/memory-check.sh
#   framework/heartbeat/memory-check.sh /path/to/custom-config.json
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")/../.." && pwd)"
LINTER="$ROOT/memory/memory_lint.py"
CONFIG="${1:-$ROOT/memory/memory-lint.config.json}"

[ -f "$LINTER" ] || { echo "✗ memory linter not found at $LINTER" >&2; exit 2; }
[ -f "$CONFIG" ] || { echo "✗ memory-lint config not found at $CONFIG (copy + edit the example)" >&2; exit 2; }

# memory_lint.py exits nonzero on findings; let that propagate so the heartbeat sees it.
# --quiet keeps clean heartbeats silent (only prints when something drifted).
exec python3 "$LINTER" --config "$CONFIG" --quiet
