# Decision Log

A dated record of the decisions that shaped this repo, and why. Companion to
[README.md](README.md) (current state) and
[docs/WHY.md](docs/WHY.md) (research + audit).

---

## 2026-08-16

### 1. External delegation via OpenHands + NVIDIA NIM — ACCEPTED
Evaluated the premise of delegating complex multi-step work from the Freebuff
harness to an autonomous OpenHands subagent running on NVIDIA NIM.
- Verified live NIM model IDs: `z-ai/glm-5.2` (agentic/coding flagship),
  `minimaxai/minimax-m3` (multimodal vision-language, strong tool calling).
- Verified current OpenHands CLI reality: config scheme migrated V0
  (`config.toml`) → V1 (`agent_settings.json` + `--override-with-envs`);
  headless mode always auto-approves and `--llm-approve` is unavailable;
  Docker sandbox is default/recommended, `process` has no isolation.
- Known NIM constraints: ~40 RPM free baseline + daily caps; hosted GLM-5.2
  context capped ~202K tokens despite 1M marketing; streaming + tool calls can
  hit a ~300 s idle timeout.

### 2. Why delegation exists at all — CONFIRMED (user-verified)
Freebuff CLI root agent switched base2 → base3 on 2026-08-11: no subagents
(subagent spawning was removed). The subagents still exist
but are unreachable from the CLI. The `browser-use` agent previously had
vision (gemini lite); now browser work runs in the main thread, and with a
text-only main model (DeepSeek V4) there is **zero visual feedback for
design work**. This is a capability regression, not a cost problem — the
decisive driver for the whole project.

### 3. Account-safety boundary — DECIDED (hard constraint)
Freebuff monetization is ad-supported; client-side behavior changes that
interact with their servers risk account limits. Therefore:
- **External delegation is the only safe path** — a local subprocess; the
  client's server interaction is unchanged.
- **Never modify the Freebuff client** (no `agents/base3.ts` patch, no
  `base3.test.ts` changes, no harness overrides).
- **Never use `client-side overrides`** — undocumented override,
  unknown server observability.
- Normal usage is fine (e.g., selecting a shipped model root).

### 4. Repo structure — ACCEPTED
`install.sh` (version-aware bootstrap) + `delegate.sh` (sanitized-env
wrapper) + smoke test + docs, built for reproducibility on new instances.
Reconsidered later: `delegate.sh` is self-contained (env-var routing), so
`install.sh` is bootstrap-only, not a runtime requirement.

### 5. Pre-run test suite — ADOPTED
Mock-based tests (`tests/run-tests.sh`) validate env sanitization, role
routing, sandbox enforcement, config generation, and exit codes with zero
side effects. **This caught real bugs before any live run**:
- macOS `mktemp` requires trailing `X` characters — templates like
  `/tmp/oh-task-XXXX.md` failed intermittently with "File exists".
- Mock `--help` output raced SIGPIPE against `grep -q` (single `printf` fix).
- A `****` mask pattern was being interpreted as grep regex (fixed-string
  matching now).

### 6. Sandbox enforcement — DECIDED (safety-critical)
- **Docker by default and enforced**; agent commands run inside a container.
- `RUNTIME=process` (commands run directly on the host) is **refused** unless
  `ALLOW_PROCESS_SANDBOX=1` — an explicit opt-in.
- `RUNTIME` and `SANDBOX_VOLUMES` are passed through `env -i` (previously
  silently stripped — OpenHands would have ignored the sandbox choice).
- Residual risks documented honestly: network egress (never put secrets in
  the workspace), read-write mounts, and no approval layer in headless.

### 7. Capability roles — ADOPTED, then EVOLVED
Restored the former subagent capabilities (browser-use, researcher,
code-editor, code-reviewer, context-pruner) as **enforced roles**:
`roles/<name>/role.conf` selects the provider type + default model, and
`prompt.md` carries operating rules the wrapper injects into every task —
deterministic discipline, not orchestrator memory.

### 8. Pluggable providers — DECIDED
Two provider types: **text** (high-reasoning, non-vision) and **vision**
(multimodal). Each resolves `*_MODEL` / `*_API_KEY` / `*_BASE_URL` from
`.env`. **Vision falls back to text; text falls back to the NVIDIA
defaults.** Consequences:
- Minimal setup is still just `NVIDIA_API_KEY`.
- A single model serving both provider types works by setting only
  `TEXT_MODEL` (expected future shape: one strong model dominates).
- Any OpenAI-compatible endpoint can be plugged in without code changes.

### 9. `.env` vs environment variables — DECIDED
`.env` is the persisted per-machine config (gitignored). **Explicitly-set
environment variables always win over `.env`** (`lib/env.sh` loads only
unset variables, expanding `${VAR}` references) — per-invocation overrides
and CI injection without editing files.

### 10. Newcomer flow — ADOPTED
`check-env.sh` dry-run prints the resolved configuration (models, base URLs,
masked keys, sandbox, Docker status) with no side effects, and README
walks through: key → `.env` → verify → install → smoke test.

### 11. Skills discovery — DECIDED, then CORRECTED
Per the Codebuff docs, skills are discovered natively from the project's
`.agents/skills` (highest priority; global fallbacks exist). The skill was
renamed `delegate_to_openhands` → **`delegate-openhands`** to satisfy the
documented name validation (lowercase, hyphens, no underscores).
**Correction:** after initially adding a project-relative default for the
skills dir, we reverted — **no default skills directory is imposed at all**.
Native project discovery is the behavior; `FREE_BUFF_SKILLS_DIR` is an
opt-in override for copying the skill elsewhere.

### 12. Platform boundary — DECIDED
**Tested on macOS 27 only** (bash 3.2, BSD coreutils). Portability quirks
handled (trailing-`X` mktemp, no arrays under bash 3.2), but Linux/GNU and
Windows are untested; the suite must pass on a platform before it is claimed.

### 13. Skill vs MCP — RESOLVED (MCP, with the skill as a git-history fallback)
The capability is transport-agnostic (`delegate.sh` is the engine). A skill
is prose instructions the model must execute correctly; an **MCP server
exposing a `delegate` tool** gives typed parameters, structured results
(exit code, changed files, summary), and hard enforcement before the model
acts. Native MCP support was verified as active in the current Freebuff
source (project-local MCP registration exists; version-dependent in the
shipped binaries). Decision: MCP is the integrated path; the skill is not
kept as a living fallback — it is preserved in git history (decision 16).

### 14. Quality & documentation baseline — ADOPTED
Every delegation now carries an injected shared baseline
(`prompts/quality-and-docs.md`) — **repo hygiene, not a role**: it lives
outside the role system and applies to every task, on top of any role rules.
It mandates: docs kept in sync with code, decisions recorded, no dead
code/orphaned TODOs, smallest change, typecheck + tests before done, verified
(never assumed) results, explicit caveats, and a required four-part final
report. The wrapper injects it deterministically into every task (with or
without a role), so the discipline survives new and custom roles without
being re-written.

### 15. Published to GitHub — DONE
Repo `freebuff-subagents` (private) created on the `RC-Logan` account and
pushed. Commit authorship was rewritten (pre-push, recoverable via
`refs/original/`) to `RC-Logan <RC-Logan@users.noreply.github.com>` so
GitHub attributes the work to the account. The skill ships in this first
push as the fallback snapshot.

### 16. Skill removed — MCP route; fallback in git history
After the first push, `.agents/skills/delegate-openhands/` was intentionally
deleted (`git rm`) so the repo stops shipping a mechanism the MCP route
supersedes. The skill is NOT lost — it is preserved in git history at the
first push commit (recoverable via `git show <sha>:...` or `git checkout
<sha> -- .agents/skills/delegate-openhands`). install.sh/check-env.sh/README
no longer reference a skills dir; `FREE_BUFF_SKILLS_DIR` was removed with the
feature. If the MCP route fails, restore the skill from history and re-add
the copy hooks.

---

## Current status (2026-08-16)

- Repo published: **`github.com/RC-Logan/freebuff-subagents`** (private).
- Self-tested: **64/64 assertions green** in `tests/run-tests.sh` (macOS 27).
- The Freebuff skill was removed from the tree (fallback in git history);
  the MCP server is the planned integrated path, not yet built.
- **Not yet live:** no API key in `.env`, no Docker installed, no real NIM
  call, no smoke test run.

## Open items

- [ ] Build the MCP server exposing the `delegate` tool (research Freebuff's
      MCP registration mechanism first — config file/format on the
      installed client).
- [ ] If the MCP route fails: restore the skill from git history and re-add
      the install hooks.
- [ ] Set `NVIDIA_API_KEY` in `.env` and run `./bin/check-env.sh`.
- [ ] Install Docker (OrbStack recommended) and run `./bin/install.sh`.
- [ ] Run `./bin/smoke-test.sh` on both models; add a vision smoke test
      (assert screenshots returned) for the browser-use role.
- [ ] Optional: GitHub Actions CI running the pre-run suite.
