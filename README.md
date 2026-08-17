# Freebuff Subagents

A **Freebuff** extension: safe, reproducible subagent delegation for the
Freebuff harness via an autonomous **OpenHands** subagent running on
**NVIDIA NIM** (GLM-5.2 for text/code, MiniMax-M3 for vision/browser) — as a
pure local subprocess, with zero changes to the Freebuff client. Restores the
subagent capabilities the Freebuff CLI used to have (browser-use, researcher,
code-editor, code-reviewer, context-pruner) as enforced roles.

Why this exists: the Freebuff CLI root agent no longer spawns subagents
(base2 → base3 switch), and the main-thread model can be text-only — so
browser/design work loses visual feedback. Delegation restores a
cheap, specialized worker outside the harness. Full background, audit, and
Why this exists and the problem it solves:
[`docs/WHY.md`](docs/WHY.md); the decision log:
[`DECISIONS.md`](DECISIONS.md).

## Platform support

**Tested on: macOS 27 only** (bash 3.2, BSD coreutils). The scripts are written
as portable POSIX bash with macOS quirks handled explicitly (trailing-`X`
`mktemp` templates, no arrays under bash 3.2), but Linux/GNU and Windows
behavior is **not yet tested** — run `./tests/run-tests.sh` on any new platform
before relying on it.

## Providers & model routing

Two pluggable provider types (configure in `.env`):

| Provider | Purpose | Default (NVIDIA NIM) |
|---|---|---|
| `text` | High-reasoning, non-vision: coding, research, review | GLM-5.2 (`z-ai/glm-5.2`) |
| `vision` | Multimodal: browser, screenshots, design | MiniMax-M3 (`minimaxai/minimax-m3`) |

Each provider can point at **your own API** (`*_MODEL` / `*_API_KEY` /
`*_BASE_URL`). Vision falls back to text; text falls back to the NVIDIA
defaults — so a single-model setup works (set `TEXT_MODEL`, leave `VISION_*`
empty), and the minimal NVIDIA setup is just `NVIDIA_API_KEY`. Model is
resolved per call; `-m` overrides it.

## Configuration: `.env` vs environment variables

Copy `.env.example` → `.env` for persisted per-machine config (gitignored, so
secrets stay local). Explicitly-set environment variables always **override**
`.env` — `lib/env.sh` loads only variables that aren't already set — so you
can override per invocation without editing the file:

```bash
TEXT_MODEL=my-model ./bin/delegate.sh -r code-editor -t "..."
VISION_API_KEY=... ./bin/delegate.sh -r browser-use -t "..."
```

## Capability roles

The Freebuff CLI used to spawn named subagents. Those *capabilities* are
restored — and exceeded — as **enforced roles** in `roles/<name>/`: each role
pins its NIM model (`role.conf`) and carries its own operating rules
(`prompt.md`) that the wrapper injects into every delegation. `-r <role>`
picks the role; every role runs through the same sandboxed, sanitized
wrapper. Quality standards are deliberately **not** imposed on delegated
tasks — that's your project's call. (Repo hygiene for agents working on
*this* repo: [`docs/REPO_HYGIENE.md`](docs/REPO_HYGIENE.md).) See
[`ROLES.md`](ROLES.md) for the table and how to add roles.

## First-time setup (reproduce on a new instance)

**Prerequisites:** macOS, an API key, [Docker](#sandboxing--safety) running
(required for the safe default sandbox), and git + curl (both ship with
macOS). The first smoke test pulls OpenHands' agent-server Docker image, so
it is slow on a fresh machine.

1. **Get an API key.** For NVIDIA NIM: sign in at `https://build.nvidia.com`,
   open **API Keys** (Settings → API Keys), and generate a key. (Any other
   OpenAI-compatible provider works too — see Providers below.)
2. **Create `.env` from the template:**
   ```bash
   git clone <this-repo> && cd freebuff-subagents
   cp .env.example .env
   ```
3. **Set the minimum** — everything else is optional:
   ```bash
   NVIDIA_API_KEY=nvapi-YOUR-KEY-HERE
   ```
   `.env` is gitignored, so your key is never committed.
4. **Verify your setup without doing anything:**
   ```bash
   ./bin/check-env.sh
   ```
   It prints the resolved models, base URLs, masked keys, and sandbox, and
   fails loudly if a key is missing — no install, no API call.
5. **Install and smoke test:**
   ```bash
   ./bin/install.sh         # installs openhands-ai, writes config, pings NIM
   ./bin/smoke-test.sh      # one end-to-end delegation (text model)
   ./bin/smoke-test.sh -m minimaxai/minimax-m3   # same task on the vision model
   ```

Notes for step 3:
- Model IDs in `.env` are **bare** (`z-ai/glm-5.2`); the `openai/` prefix is
  added automatically for OpenHands — never put it in `.env`.
- **Your own API?** Set `TEXT_MODEL`, `TEXT_API_KEY`, `TEXT_BASE_URL` (and
  `VISION_*` for the vision provider) instead — see Providers & ROLES.md.
- **One model for both provider types?** Set only `TEXT_MODEL` and leave
  `VISION_*` empty — vision falls back to text.

`install.sh` is idempotent and **version-aware**: it detects whether your
installed OpenHands CLI uses the V1 (`agent_settings.json`) or legacy V0
(`config.toml`) config scheme and writes the right one.

## Freebuff integration (MCP)

The Freebuff skill that originally shipped with this repo was **intentionally
removed** (2026-08-16): the integrated path is an **MCP server** exposing the
`delegate` tool — typed `task` + `role` + `working_directory` in, structured
JSON out — which is strictly stronger than a prose skill. The server is
`bin/mcp-server.py` (zero-dependency stdio JSON-RPC, Python stdlib only),
wrapping `delegate.sh`, so every safety guarantee carries over.

**Register it.** Freebuff loads `mcp.json` (standard `mcpServers` shape)
from `.agents/` near where it runs: `{cwd}/.agents/mcp.json`, then
`{cwd}/../.agents/mcp.json`, then `~/.agents/mcp.json` (later paths win on
name collisions). Generate the file with:

```bash
./bin/register-mcp.sh                  # writes $PWD/.agents/mcp.json
./bin/register-mcp.sh /path/to/project # or a specific project root
./bin/register-mcp.sh "$HOME"          # global: ~/.agents/mcp.json, any project
```

Run it from the directory you launch Freebuff in (or pass that path); use
`"$HOME"` for a global registration that works in every project. Then
**restart Freebuff** — it logs `Loaded MCP servers from mcp.json` at startup
when it finds the file — and ask for the tool by name:
`delegate-openhands/delegate`.

MCP support is native and **verified in the installed client** (0.0.149):
its own browser-use agent ships an MCP server config, and the loader code is
present in the shipped binary.

**Fallback:** the skill is preserved in git history at tag `skill-fallback`
(the first push). Restore it with:

```bash
git show skill-fallback:.agents/skills/delegate-openhands/SKILL.md > SKILL.md
# or restore the whole tree:
git checkout skill-fallback -- .agents/skills/delegate-openhands
```

## Day-to-day (after the one-time setup)

Once the prerequisites exist — `openhands` installed, `.env` configured,
Docker running — **you do not need `install.sh` again.** Delegation is
self-contained:

```bash
./bin/delegate.sh -r code-editor -t "..."   # uses .env / env vars directly
./bin/delegate.sh -r browser-use -t "..."
```

`delegate.sh` passes model, key, and base URL to OpenHands via environment
variables, so **no persisted OpenHands config file is required for
delegation**. `install.sh` only does the one-time bootstrap — install
openhands, write the persisted config (for *interactive* OpenHands use), ping
the API — and re-running it overwrites the config from `.env` (which is the
source of truth).

## Manual delegation

```bash
# From the terminal
./bin/delegate.sh -t "Fix the failing test in ./src" -d ./src
./bin/delegate.sh -f /tmp/task.md -m minimaxai/minimax-m3 -d ./design

# From Freebuff: use the 'delegate-openhands/delegate' MCP tool (see the
# Freebuff integration section)
```

Exit codes: `0` success · `1` task failed · `2` invalid args · `3` unsafe local config (e.g. `RUNTIME=process` without opt-in).

## Layout

```
bin/install.sh        # bootstrap: uv, openhands-ai, config, NIM ping
bin/check-env.sh      # dry-run: prints resolved config, no side effects
bin/delegate.sh       # sanitized-env headless wrapper (roles, per-call model routing)
bin/mcp-server.py     # stdio MCP server exposing the delegate tool (stdlib only)
bin/register-mcp.sh   # writes .agents/mcp.json for Freebuff
bin/smoke-test.sh     # end-to-end validation
lib/env.sh            # .env loader (env vars win over the file)
config/               # config templates (V1 JSON + V0 TOML fallback)
roles/<name>/         # capability roles: role.conf (model) + prompt.md (rules)
.agents/              # project-local MCP registration (mcp.json.example tracked)
tasks/smoke-task.md   # minimal task used by the smoke test
tests/                # pre-run mock test suite (run-tests.sh)
docs/WHY.md                            # why this repo exists and the problem it solves
docs/REPO_HYGIENE.md                    # standards for agents working on this repo
```

## Safe boundary (read before changing anything)

- **Never modify Freebuff client code, config, env, or network behavior.**
  The only safe path is this external subprocess.
- `delegate.sh` runs OpenHands with a **sanitized environment** — NVIDIA key and
  routing vars only. Freebuff credentials never cross into the subprocess, and
  the key never appears in output.
- Headless mode **always auto-approves** every action. Delegate only on explicit
  user intent.
- NIM free tier is ~40 RPM with daily caps. Keep delegations small; expect 429s.

## Sandboxing & safety

- **Docker by default, enforced.** Agent commands run inside a Docker container,
  never directly on your machine. Only the delegated working directory (plus
  anything in `SANDBOX_VOLUMES`) is shared with the host. On macOS with Docker
  Desktop, containers run inside a Linux VM — double isolation.
- **`RUNTIME=process` is refused** unless `ALLOW_PROCESS_SANDBOX=1` is set
  explicitly; it runs commands with your user permissions and no isolation.
- **What the sandbox protects:** host filesystem, SSH keys, and credentials are
  not reachable unless explicitly mounted. Never mount `~/.ssh`, `~/.aws`, or
  similar.
- **What the sandbox does NOT protect:** network egress. The agent can reach the
  internet (it must, to call NIM and browse). Don't put secrets in the delegated
  workspace, and assume anything you mount read-write can be modified.
- **No approval layer:** headless mode auto-approves every action and
  `--llm-approve` is unavailable in headless mode. Isolation is the safeguard.
- **Known trade-off:** with the default bridge network, the sandbox cannot reach
  host-local services (dev servers, databases). Tasks that must hit `localhost`
  services need explicit network setup — don't silently switch to `process` to
  work around this.

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `NVIDIA_API_KEY is required` | Copy `.env.example` → `.env` and fill it in. |
| NIM ping returns non-200 | Wrong key, stale model ID (verify at build.nvidia.com/models), or rate limited (429). |
| `openhands: command not found` | Run `./bin/install.sh`, or add `$HOME/.local/bin` to PATH. |
| Delegation exits 1 | The task itself failed — check the last observations printed by `delegate.sh`. |
| 429 Too Many Requests | ~40 RPM baseline; wait, reduce `num_retries` backpressure, or split the task. |
| Stream stalls ~300 s during tool calls | Known NIM streaming quirk with tool calls; retry or re-run the delegation. |
| Context-limit error around 200K | Hosted GLM-5.2 caps context at ~202K tokens despite 1M marketing — split the task. |
| MCP tool not appearing in Freebuff | Restart Freebuff after `./bin/register-mcp.sh`; if it still won't load, the installed client may not expose MCP yet (version-dependent). Delegate from the terminal via `./bin/delegate.sh` meanwhile; the skill fallback lives at tag `skill-fallback`. |
| Model name rejected | The API needs the **bare** model ID in `.env`; only OpenHands config gets the `openai/` prefix. |
| Use my own model/API? | Set `TEXT_MODEL`/`TEXT_API_KEY`/`TEXT_BASE_URL` (and `VISION_*` for vision roles) in `.env`; see ROLES.md. |
