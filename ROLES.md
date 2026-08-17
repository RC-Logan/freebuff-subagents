# Capability roles

The Freebuff CLI used to spawn named subagents. This repo restores the same
*capabilities* — and goes further — as **enforced roles**: each role lives in
`roles/<name>/` and is applied deterministically by the wrapper:

- `roles/<name>/role.conf` — selects the **provider type** (`text` or
  `vision`) and a default model.
- `roles/<name>/prompt.md` — operating rules injected into every delegation
  for that role (the discipline no longer depends on the main model remembering
  to write it).

Invoke with `./bin/delegate.sh -t "<task>" -r <role>`. `-m <model>`
overrides the model for that run.

## Quality & documentation baseline (every delegation)

On top of the role rules, the wrapper injects
`roles/common/quality-and-docs.md` into **every** delegation — with or
without a role. It mandates: docs kept in sync with code, decisions recorded,
no dead code / orphaned TODOs, smallest-change discipline, typecheck + tests
before reporting done, verified (never assumed) results, explicit caveats,
and a required four-part final report (files changed / commands run /
verified / caveats). Role prompts don't need to repeat it — it is guaranteed
by the wrapper, so custom roles inherit it automatically.

| Role | Provider | Default model | Capability |
|---|---|---|---|
| `browser-use` | vision | `minimaxai/minimax-m3` | Vision-capable browser: screenshots, design, visual QA. Screenshot-per-step is enforced by the role prompt; screenshots are saved to the working dir and surfaced in the result. |
| `researcher` | text | `z-ai/glm-5.2` | Multi-page web research; returns claims with sources (URLs). |
| `code-editor` | text | `z-ai/glm-5.2` | Implements changes in a repo, runs typecheck/tests, reports results. |
| `code-reviewer` | text | `z-ai/glm-5.2` | Reviews code/diffs; returns severity-ranked findings with file:line refs. No edits. |
| `context-pruner` | text | `z-ai/glm-5.2` | Condenses large context into a structured, lossless digest. |

## Providers — plug in your own API

Two provider types, configured in `.env`:

- **text** — high-reasoning, non-vision model (coding, research, review):
  `TEXT_MODEL`, `TEXT_API_KEY`, `TEXT_BASE_URL`.
- **vision** — multimodal model (browser, screenshots, design):
  `VISION_MODEL`, `VISION_API_KEY`, `VISION_BASE_URL`.

Resolution per delegation: `-m` flag → provider model env → role default →
`DEFAULT_MODEL`. Keys/base URLs fall back provider → `NVIDIA_API_KEY` /
`BASE_URL`. **Vision falls back to text, and text falls back to the NVIDIA
defaults**, so:

- **Minimal NVIDIA setup:** set only `NVIDIA_API_KEY`.
- **One model for both types** (or a dominant text model): set `TEXT_MODEL`,
  leave `VISION_*` empty — `browser-use` will use the text provider. This is
  the expected future shape: a single strong model may serve both roles.
- **Separate APIs:** set both provider blocks independently.

## Why this surpasses the old subagent structure

- **Deterministic discipline** — operating rules are enforced by the wrapper
  per role, not recalled by the orchestrator.
- **Right provider per capability** — the vision role routes to a multimodal
  provider, and can be repointed to any endpoint without code changes.
- **One safety envelope** — every role runs through the same Docker-sandboxed,
  sanitized-env wrapper; roles cannot opt out of the safety guarantees.
- **Configurable and testable** — roles are plain files; the pre-run suite
  verifies provider routing, model pinning, and prompt injection.

## Adding a role

```bash
mkdir roles/my-role
# roles/my-role/role.conf:
#   name=my-role
#   description=...
#   provider=text          # text | vision
#   model=your-default-model
# roles/my-role/prompt.md:  (operating rules, injected verbatim before the
#                            shared quality/documentation baseline)
```

The shared baseline is added automatically; you only write the role-specific
rules. (Previously roles were also exposed through a Freebuff skill — that
skill was removed in favor of an MCP server, see DECISIONS.md.)

## When NOT to use a role

- Single-shot vision extraction (look at one image) → call the vision API
  directly from Freebuff; don't spawn a full agent session.
- The main thread can do the task comfortably → do it in-thread; every
  delegation costs API calls against the provider's rate budget.
