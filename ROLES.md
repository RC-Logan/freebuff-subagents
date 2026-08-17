# Capability roles

The Freebuff CLI used to spawn named subagents. This repo restores the same
*capabilities* — and goes further — as **enforced roles**: each role lives in
`roles/<name>/` and is applied deterministically by the wrapper:

- `roles/<name>/role.conf` — pins the NIM model and describes the role.
- `roles/<name>/prompt.md` — operating rules injected into every delegation
  for that role (the discipline no longer depends on the main model remembering
  to write it).

Invoke with `./bin/delegate.sh -t "<task>" -r <role>` (or via the skill's
`role` parameter). `-m <model>` overrides the role's pinned model.

| Role | Model | Capability |
|---|---|---|
| `browser-use` | `minimaxai/minimax-m3` | Vision-capable browser: screenshots, design, visual QA. Screenshot-per-step is enforced by the role prompt; screenshots are saved to the working dir and surfaced in the result. |
| `researcher` | `z-ai/glm-5.2` | Multi-page web research; returns claims with sources (URLs). |
| `code-editor` | `z-ai/glm-5.2` | Implements changes in a repo, runs typecheck/tests, reports results. |
| `code-reviewer` | `z-ai/glm-5.2` | Reviews code/diffs; returns severity-ranked findings with file:line refs. No edits. |
| `context-pruner` | `z-ai/glm-5.2` | Condenses large context into a structured, lossless digest. |

## Why this surpasses the old subagent structure

- **Deterministic discipline** — operating rules are enforced by the wrapper
  per role, not recalled by the orchestrator.
- **Right model per capability** — the vision role runs on a genuinely
  multimodal model (MiniMax-M3), not a text-first lite model.
- **One safety envelope** — every role runs through the same Docker-sandboxed,
  sanitized-env wrapper; roles cannot opt out of the safety guarantees.
- **Configurable and testable** — roles are plain files; the pre-run suite
  verifies model pinning and prompt injection.

## Adding a role

```bash
mkdir roles/my-role
# roles/my-role/role.conf:
#   name=my-role
#   description=...
#   model=z-ai/glm-5.2
# roles/my-role/prompt.md:  (operating rules, injected verbatim)
```

The skill's `role` enum should list it too (SKILL.md frontmatter).

## When NOT to use a role

- Single-shot vision extraction (look at one image) → call NIM directly from
  Freebuff; don't spawn a full agent session.
- The main thread can do the task comfortably → do it in-thread; every
  delegation costs 1+ NIM calls against the ~40 RPM budget.
