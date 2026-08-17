# Subagent roles (base2-style)

The Freebuff CLI used to spawn named subagents (`browser-use`, `researcher-web`,
`researcher-docs`, `editor`, `code-reviewer`, `context-pruner`, ...). That
mechanism no longer exists in the client, and we must not modify the client.
These roles restore the same *capabilities* through the safe delegation skill:
each role selects a NIM model and a task discipline, and every role runs through
the same sandboxed, sanitized wrapper (`bin/delegate.sh`).

| Role | Model | Purpose |
|---|---|---|
| `browser-use` | `minimaxai/minimax-m3` | Browser, screenshots, visual/design work. Multimodal — this is the vision role. |
| `researcher` | `z-ai/glm-5.2` | Multi-page web research; return sources with URLs. |
| `code-editor` | `z-ai/glm-5.2` | Implement changes in a repo, run the relevant tests. |
| `code-reviewer` | `z-ai/glm-5.2` | Review a diff/repo; return findings with severity and line refs. |
| `context-pruner` | `z-ai/glm-5.2` | Condense/summarize a large context or transcript into a structured digest. |

## Per-role task discipline (the main model should bake this into
`task_instructions`)

- **browser-use** — mandate screenshot-per-step: "after every action, take a
  screenshot and describe what you see before deciding the next step." Require
  the agent to return the captured images/paths so the user can verify visuals.
- **researcher** — require a sources list at the end: URL + one-line claim for
  each source. Ask for explicit "not found" statements instead of guessing.
- **code-editor** — require: implement, then run the project's typecheck/tests,
  then report what changed and the results. Scope edits to the working directory.
- **code-reviewer** — require findings as a severity-ranked list with file/line
  references; no code edits.
- **context-pruner** — require a structured digest (decisions, open questions,
  artifacts, next steps); preserve concrete identifiers and paths verbatim.

## How it maps to the safe wrapper

The skill's `role` parameter picks the model (per the table above); the wrapper
enforces Docker sandbox, sanitizes the environment, and returns the exit code.
Nothing here modifies the Freebuff client — these are local files only.

## When NOT to use a role

- Single-shot vision extraction (look at one image) → call NIM directly from
  Freebuff; don't spawn a full agent session.
- The main thread can already do the task comfortably → do it in-thread; every
  delegation costs 1+ NIM calls against the ~40 RPM budget.
