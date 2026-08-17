#!/usr/bin/env python3
"""MCP stdio server exposing the `delegate` tool for Freebuff/Codebuff.

Zero-dependency stdio JSON-RPC server (Python 3 stdlib only). It wraps the
existing `bin/delegate.sh` engine — all safety (Docker sandbox enforcement,
sanitized environment, role routing, exit codes) lives there and is
inherited unchanged.

Registration is project-local, per the Freebuff/Codebuff source loader:
`.agents/mcp.json` -> {"mcpServers": {"delegate-openhands": {"command":
"python3", "args": ["<repo>/bin/mcp-server.py"], "env": {}}}}. Generate it
with `./bin/register-mcp.sh`, restart the client, and invoke the tool as
`delegate-openhands/delegate`.

Client support: the installed desktop client (0.0.63 at last check) does not
implement the Codebuff `.agents/mcp.json` loader at runtime (DECISIONS.md
#20) — register with `./bin/register-mcp.sh`, which writes the project
`.mcp.json` / `~/.claude.json` entries the client's Claude-Code runtime
reads. `.agents/mcp.json` is still written for clients that implement that
loader, and `bin/delegate.sh` from the terminal always works.

Tested on macOS 27 only.
"""
import json
import subprocess
import sys
from pathlib import Path

SERVER_NAME = "delegate-openhands"
SERVER_VERSION = "1.0.0"
PROTOCOL_VERSION = "2025-03-26"

ROOT = Path(__file__).resolve().parent.parent
DELEGATE = ROOT / "bin" / "delegate.sh"
ROLES_DIR = ROOT / "roles"


def role_names():
    if not ROLES_DIR.is_dir():
        return []
    return sorted(
        d.name for d in ROLES_DIR.iterdir()
        if d.is_dir() and (d / "role.conf").is_file()
    )


def delegate_tool():
    return {
        "name": "delegate",
        "description": (
            "Run a task in an isolated, sandboxed worker (OpenHands via NVIDIA "
            "NIM) using your own API key. Use it for heavy multi-step coding, "
            "debugging, research, or vision-heavy work (browser use) instead of "
            "doing everything in the main thread. Returns the worker exit code, "
            "changed files, and last observations."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "task_instructions": {
                    "type": "string",
                    "description": "The task for the worker agent to execute.",
                },
                "role": {
                    "type": "string",
                    "enum": role_names(),
                    "description": "Optional role preset: pins the provider model and injects the role's operating rules (see ROLES.md).",
                },
                "working_directory": {
                    "type": "string",
                    "description": "Directory (relative to this repo) the worker operates in; created if missing. Defaults to the repo root.",
                },
                "model": {
                    "type": "string",
                    "description": "Optional explicit NIM model id, overriding the role or default.",
                },
            },
            "required": ["task_instructions"],
        },
    }


def send(msg):
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def send_error(rid, code, message):
    send({"jsonrpc": "2.0", "id": rid, "error": {"code": code, "message": message}})


def run_delegate(arguments):
    task = arguments.get("task_instructions", "")
    role = arguments.get("role")
    work_dir = arguments.get("working_directory")
    model = arguments.get("model")

    if not isinstance(task, str) or not task.strip():
        raise ValueError("task_instructions is required and must be a non-empty string")
    if role is not None and role not in role_names():
        raise ValueError("unknown role '%s' (known: %s)" % (role, ", ".join(role_names())))
    if work_dir is not None and not isinstance(work_dir, str):
        raise ValueError("working_directory must be a string")
    if model is not None and not isinstance(model, str):
        raise ValueError("model must be a string")

    cmd = ["bash", str(DELEGATE), "-t", task]
    if role:
        cmd += ["-r", role]
    if model:
        cmd += ["-m", model]
    if work_dir:
        cmd += ["-d", work_dir]

    proc = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True)
    output = (proc.stdout or "") + (proc.stderr or "")
    return _parse(proc.returncode, output)


def _parse(exit_code, output):
    lines = output.splitlines()
    changed, observations = [], []
    in_files = in_obs = False
    for line in lines:
        s = line.strip()
        if s.startswith("==> files changed/created by the agent:"):
            in_files, in_obs = True, False
            continue
        if s.startswith("==> last observations:"):
            in_files, in_obs = False, True
            continue
        if s.startswith("==>"):
            in_files = in_obs = False
        if in_files and s:
            changed.append(s)
        if in_obs and s:
            try:
                observations.append(json.loads(s))
            except json.JSONDecodeError:
                observations.append(s)
    return {
        "exit_code": exit_code,
        "changed_files": changed,
        "observations": observations[-5:],
        "output_tail": "\n".join(lines[-25:]),
    }


def handle_call(params):
    name = (params or {}).get("name")
    if name != "delegate":
        raise KeyError("unknown tool '%s'" % name)
    arguments = (params or {}).get("arguments") or {}
    try:
        result = run_delegate(arguments)
    except ValueError as exc:
        return {"isError": True, "content": [{"type": "text", "text": str(exc)}]}
    except Exception as exc:  # engine-level failure surfaces as a tool error
        return {"isError": True, "content": [{"type": "text", "text": "delegation failed: %s" % exc}]}
    return {"content": [{"type": "text", "text": json.dumps(result, indent=2)}]}


def handle(request):
    method = request.get("method")
    rid = request.get("id")

    if rid is None:  # notification — never respond
        return

    if method == "initialize":
        params = request.get("params") or {}
        client_version = params.get("protocolVersion")
        send({
            "jsonrpc": "2.0",
            "id": rid,
            "result": {
                "protocolVersion": client_version if isinstance(client_version, str) else PROTOCOL_VERSION,
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
            },
        })
    elif method == "ping":
        send({"jsonrpc": "2.0", "id": rid, "result": {}})
    elif method == "tools/list":
        send({"jsonrpc": "2.0", "id": rid, "result": {"tools": [delegate_tool()]}})
    elif method == "tools/call":
        try:
            send({"jsonrpc": "2.0", "id": rid, "result": handle_call(request.get("params"))})
        except KeyError as exc:
            send_error(rid, -32602, str(exc))
        except Exception as exc:
            send_error(rid, -32602, "invalid params: %s" % exc)
    elif method == "resources/list":
        send({"jsonrpc": "2.0", "id": rid, "result": {"resources": []}})
    elif method == "prompts/list":
        send({"jsonrpc": "2.0", "id": rid, "result": {"prompts": []}})
    else:
        send_error(rid, -32601, "method not found: %s" % method)


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError:
            send_error(None, -32700, "parse error")
            continue
        try:
            handle(request)
        except Exception:
            send_error(request.get("id"), -32603, "internal error")


if __name__ == "__main__":
    main()
