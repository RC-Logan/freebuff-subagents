#!/usr/bin/env bash
# Generate the MCP registration file Freebuff loads natively (mcp.json with
# an mcpServers map; see docs/WHY.md and DECISIONS.md #19).
#
# The Freebuff/Codebuff loader (verified present in the shipped 0.0.149
# binary) searches these paths, later paths winning on name collisions:
#   {cwd}/.agents/mcp.json
#   {cwd}/../.agents/mcp.json
#   {homedir}/.agents/mcp.json     (global — any project)
#
# Usage: ./bin/register-mcp.sh [target-dir]
#   Writes <target-dir>/.agents/mcp.json. Default target: the current
#   directory ($PWD) — so run it from the directory you launch Freebuff in.
#   Use "$HOME" for a global registration that works in every project.
#   Idempotent — re-running regenerates the file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE="$SCRIPT_DIR/.agents/mcp.json.example"
TARGET="${1:-$PWD}"
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
echo "  1. Restart Freebuff (it logs 'Loaded MCP servers from mcp.json' at"
echo "     startup when it finds the file)."
echo "  2. Ask for the tool by name: 'delegate-openhands/delegate'."
echo "  3. Fallback if the tool is ever unavailable: the skill lives in git"
echo "     history at tag skill-fallback (see README)."
