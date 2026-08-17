#!/usr/bin/env bash
# Generate the project-local MCP registration file that Freebuff/Codebuff
# loads natively (`.agents/mcp.json`; see docs/WHY.md and DECISIONS.md #19).
#
# Usage: ./bin/register-mcp.sh [target-dir]
#   Writes <target-dir>/.agents/mcp.json (default: this repo's root).
#   Idempotent — re-running regenerates the file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE="$SCRIPT_DIR/.agents/mcp.json.example"
TARGET="${1:-$SCRIPT_DIR}"
OUT="$TARGET/.agents/mcp.json"

[[ -f "$EXAMPLE" ]] || { echo "ERROR: missing $EXAMPLE" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required (it runs the MCP server)" >&2; exit 1; }

mkdir -p "$TARGET/.agents"
python3 - "$EXAMPLE" "$OUT" "$SCRIPT_DIR" <<'PY'
import json
import sys

example, out, root = sys.argv[1], sys.argv[2], sys.argv[3]
with open(example) as fh:
    data = json.loads(fh.read().replace("__REPO_ROOT__", root))
with open(out, "w") as fh:
    fh.write(json.dumps(data, indent=2) + "\n")
PY

echo "==> wrote $OUT"
echo "    server: python3 $SCRIPT_DIR/bin/mcp-server.py"
echo
echo "Next:"
echo "  1. Restart Freebuff so it loads the new MCP server."
echo "  2. Ask for the tool by name: 'delegate-openhands/delegate'."
echo "  3. If the tool does not appear, the installed client may not expose"
echo "     MCP yet (support is version-dependent) — see docs/WHY.md."
