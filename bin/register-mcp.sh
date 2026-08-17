#!/usr/bin/env bash
# Register the delegate MCP server with the Freebuff desktop client.
#
# The integration is an MCP server (bin/mcp-server.py), NOT a skill. The
# desktop app (0.0.63 at last check) does not call the Codebuff
# `.agents/mcp.json` loader (DECISIONS.md #20) — that loader is implemented
# in the `freebuff` CLI (0.0.149), so the file is read in CLI sessions only.
# The desktop runtime DOES read the Claude-Code-standard MCP config (it
# spawns Claude Code subprocesses with strictMcpConfig off):
#   {project}/.mcp.json       — project-local, read per session in that dir
#   ~/.claude.json mcpServers — global, every project
# This script writes those, and ALSO writes `.agents/mcp.json` for CLI
# sessions and other clients that implement the Codebuff loader.
# See DECISIONS.md #19–20.
#
# Usage:
#   ./bin/register-mcp.sh                 # project-local: ./.mcp.json + ./.agents/mcp.json
#   ./bin/register-mcp.sh <target-dir>    # project-local at <target-dir>
#   ./bin/register-mcp.sh --global        # merge into ~/.claude.json + write ~/.agents/mcp.json
#   ./bin/register-mcp.sh "$HOME"         # same as --global
#   Idempotent — re-running regenerates the files / re-merges the key.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE="$SCRIPT_DIR/.agents/mcp.json.example"

GLOBAL=0
TARGET=""
case "${1:-}" in
  --global|-g) GLOBAL=1 ;;
  "") TARGET="$PWD" ;;
  *) TARGET="$1" ;;
esac
if [[ "$TARGET" == "$HOME" ]]; then GLOBAL=1; fi

[[ -f "$EXAMPLE" ]] || { echo "ERROR: missing $EXAMPLE" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required (it runs the MCP server)" >&2; exit 1; }

write_from_example() { # write_from_example <out-path>
  python3 - "$EXAMPLE" "$1" "$SCRIPT_DIR" <<'PY'
import json
import sys
example, out, root = sys.argv[1], sys.argv[2], sys.argv[3]
with open(example) as fh:
    data = json.loads(fh.read().replace("__REPO_ROOT__", root))
with open(out, "w") as fh:
    fh.write(json.dumps(data, indent=2) + "\n")
PY
}

if [[ "$GLOBAL" == "1" ]]; then
  # ---- global: merge into ~/.claude.json (read by the installed client) ----
  CLAUDE_JSON="$HOME/.claude.json"
  python3 - "$CLAUDE_JSON" "$EXAMPLE" "$SCRIPT_DIR" <<'PY'
import json
import os
import shutil
import sys
import time

path, example, root = sys.argv[1], sys.argv[2], sys.argv[3]
with open(example) as fh:
    server = json.loads(fh.read().replace("__REPO_ROOT__", root))["mcpServers"]["delegate-openhands"]

original = None
if os.path.exists(path):
    with open(path) as fh:
        original = fh.read()
    try:
        data = json.loads(original)
    except json.JSONDecodeError:
        print(f"ERROR: {path} is not valid JSON — refusing to touch it")
        sys.exit(1)
else:
    data = {}

if not isinstance(data.get("mcpServers"), dict):
    data["mcpServers"] = {}
data["mcpServers"]["delegate-openhands"] = server

merged = json.dumps(data, indent=2) + "\n"
if original is not None and merged != original:
    shutil.copy2(path, f"{path}.freebuff-bak-{int(time.time())}")
with open(path, "w") as fh:
    fh.write(merged)
PY
  echo "==> merged 'delegate-openhands' into $CLAUDE_JSON (global — every project)"
  mkdir -p "$HOME/.agents"
  write_from_example "$HOME/.agents/mcp.json"
  echo "==> wrote $HOME/.agents/mcp.json (Codebuff .agents loader — clients that implement it)"
  echo "    server: python3 $SCRIPT_DIR/bin/mcp-server.py"
else
  # ---- project-local: .mcp.json (live) + .agents/mcp.json (loader compat) ----
  [[ -d "$TARGET" ]] || { echo "ERROR: target directory does not exist: $TARGET" >&2; exit 1; }
  write_from_example "$TARGET/.mcp.json"
  echo "==> wrote $TARGET/.mcp.json (Claude-Code project config — read by the installed client)"
  mkdir -p "$TARGET/.agents"
  write_from_example "$TARGET/.agents/mcp.json"
  echo "==> wrote $TARGET/.agents/mcp.json (Codebuff .agents loader — clients that implement it)"
  echo "    server: python3 $SCRIPT_DIR/bin/mcp-server.py"
fi

cat <<'NEXT'

Next:
  1. Restart Freebuff (or start a new session in the project you registered).
  2. Ask for the tool by name: 'delegate-openhands/delegate'.
  (No skill involved — this is an MCP server; see DECISIONS.md #19–20.)
NEXT
