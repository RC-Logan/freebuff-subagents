# Why this repo exists

## The problem

The Freebuff CLI used to be able to spawn named subagents — `browser-use`,
`researcher`, `code-editor`, and others — each a cheap, specialized worker
with its own model. In the `base2 → base3` change to the CLI's root agent
(2026-08-11), subagent spawning was removed: the CLI now runs a single loop
with no spawnable agents.

The subagents themselves still exist; they are simply unreachable from the
CLI. The loss is most visible for browser and design work: the `browser-use`
subagent had vision (a multimodal model), and browser work now runs in the
main thread — where a text-only main model (e.g. DeepSeek V4) has **zero
visual feedback**: no way to see a screenshot, verify a layout, or iterate
on a visual change.

## The approach

Run the specialized workers **outside** the harness instead: a local
OpenHands subprocess, sandboxed in Docker, calling your own API key (NVIDIA
NIM by default; any OpenAI-compatible endpoint works). The main model
dispatches the task; the worker does the multi-step, vision-capable work;
results come back as text and screenshots.

This restores the old capabilities — and goes further — without touching the
Freebuff client at all: no client code changes, no server-interaction
changes. The former subagents are recreated as **enforced roles**
([`ROLES.md`](../ROLES.md)) that pin the right model per capability and
guarantee the right operating discipline per task.

## Current status

- **Capabilities:** restored as enforced roles — `browser-use`, `researcher`,
  `code-editor`, `code-reviewer`, `context-pruner` (see
  [`ROLES.md`](../ROLES.md)).
- **Safety:** every delegation runs in a Docker sandbox with a sanitized
  environment; `RUNTIME=process` (no isolation) is refused without an
  explicit opt-in.
- **Freebuff integration:** an MCP server exposing the `delegate` tool,
  registered via `./bin/register-mcp.sh` (see [`DECISIONS.md`](../DECISIONS.md)
  #19–20); invoke it as `delegate-openhands/delegate`. The installed
  desktop client reads the Claude-Code-standard config the script writes
  (project `.mcp.json`, `~/.claude.json`); `.agents/mcp.json` is written
  for clients that implement the Codebuff loader. `./bin/delegate.sh` from
  the terminal always works.
- **Quality:** standards for agents working on this repo:
  [`REPO_HYGIENE.md`](REPO_HYGIENE.md).
