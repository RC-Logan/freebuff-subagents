# OpenHands ↔ NVIDIA NIM delegation for Freebuff

Reproducible setup for delegating complex multi-step work from a Freebuff
harness to an autonomous **OpenHands** subagent running on **NVIDIA NIM**
(GLMs and MiniMax-M3) — as a pure local subprocess, with zero changes to the
Freebuff client.

Why this exists: the Freebuff CLI root agent no longer spawns subagents
(base2 → base3 switch), and the main-thread model can be text-only — so
browser/design work loses visual feedback. Delegation restores a
cheap, specialized worker outside the harness. Full background, audit, and
constraints: [`docs/WHY.md`](docs/WHY.md).

## Model routing

| Workload | Model | NIM ID |
|---|---|---|
| Text/code reasoning, agent loop | GLM-5.2 | `z-ai/glm-5.2` |
| Vision, screenshots, browser/design | MiniMax-M3 | `minimaxai/minimax-m3` |

Model is chosen **per call** (`-m`), so the main thread can stay on your
coding model while delegated vision work runs on M3.

## Quickstart (reproduce on a new instance)

```bash
git clone <this-repo> && cd openhands-nim-delegation

cp .env.example .env        # then edit: NVIDIA_API_KEY, model IDs, skills dir
./bin/install.sh            # installs openhands-ai, writes config, pings NIM,
                            # installs the Freebuff skill
./bin/smoke-test.sh         # one end-to-end delegation (text model)
./bin/smoke-test.sh -m minimaxai/minimax-m3   # same task on the vision model
```

`install.sh` is idempotent and **version-aware**: it detects whether your
installed OpenHands CLI uses the V1 (`agent_settings.json`) or legacy V0
(`config.toml`) config scheme and writes the right one.

## Manual delegation

```bash
# From the terminal
./bin/delegate.sh -t "Fix the failing test in ./src" -d ./src
./bin/delegate.sh -f /tmp/task.md -m minimaxai/minimax-m3 -d ./design

# From Freebuff: invoke the delegate_to_openhands skill
# (skills/delegate_to_openhands/SKILL.md — installed by install.sh)
```

Exit codes: `0` success · `1` task failed · `2` invalid args.

## Layout

```
bin/install.sh        # bootstrap: uv, openhands-ai, config, NIM ping, skill install
bin/delegate.sh       # sanitized-env headless wrapper (per-call model routing)
bin/smoke-test.sh     # end-to-end validation
config/               # config templates (V1 JSON + V0 TOML fallback)
skills/delegate_to_openhands/SKILL.md   # the Freebuff skill definition
tasks/smoke-task.md   # minimal task used by the smoke test
docs/WHY.md            # research, concerns, safe-boundary audit
```

## Safe boundary (read before changing anything)

- **Never modify Freebuff client code, config, env, or network behavior.**
  The only safe path is this external subprocess (audit: docs §1c).
- `delegate.sh` runs OpenHands with a **sanitized environment** — NVIDIA key and
  routing vars only. Freebuff credentials never cross into the subprocess, and
  the key never appears in output.
- Headless mode **always auto-approves** every action. Delegate only on explicit
  user intent.
- NIM free tier is ~40 RPM with daily caps. Keep delegations small; expect 429s.

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
| Skill doesn't appear in Freebuff | The skills path is wrong for your install — verify `FREE_BUFF_SKILLS_DIR` (audit §1c #4). |
| Model name rejected | NIM needs the **bare** ID in `.env`; only OpenHands config gets the `openai/` prefix. |
