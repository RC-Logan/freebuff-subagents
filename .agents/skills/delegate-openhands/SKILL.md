---
name: delegate-openhands
description: Dispatches complex multi-step coding, debugging, file-editing, terminal,
  or browser/design tasks to an autonomous OpenHands subagent running against NVIDIA
  NIM. Provides the former Freebuff subagent capabilities (browser-use, researcher,
  code-editor, code-reviewer, context-pruner) as enforced roles: the wrapper pins
  the model (MiniMax-M3 for vision/browser, GLM-5.2 for text/code) and injects each
  role's operating rules. Every delegation runs in a Docker sandbox with a
  sanitized environment.
parameters:
  type: object
  properties:
    task_instructions:
      type: string
      description: Exhaustive step-by-step instructions for the subagent. For browser
        or design work, mandate screenshot-per-step: "after every action, take a
        screenshot and describe what you see before deciding the next step."
    working_directory:
      type: string
      description: Directory where OpenHands should execute. Defaults to current directory.
      default: "."
    role:
      type: string
      description: Capability role (see roles/ and ROLES.md in the repo). The wrapper
        enforces the role's provider (text/vision), model, and operating rules.
        Overridable via model.
      default: code-editor
      enum: [browser-use, researcher, code-editor, code-reviewer, context-pruner]
    model:
      type: string
      description: NIM model ID for this run.
      default: z-ai/glm-5.2
      enum: [z-ai/glm-5.2, minimaxai/minimax-m3]
  required: [task_instructions]
---

# Execution

1. For a `role`, pass `-r <role>`: delegate.sh reads `roles/<role>/role.conf`
   (provider type + default model) and `prompt.md` (operating rules), resolves
   model/key/base URL from the provider env (`.env`), and composes the task
   file automatically. `-m <model>` overrides the model. The role's discipline
   is enforced by the wrapper, not by memory.
2. Write `task_instructions` to a temporary task file (or pass via `-t`).
3. Run the wrapper from this repo's checkout (never inline-shell the task — quoting
   breaks on quotes/newlines):

   ```bash
   cd <repo> && ./bin/delegate.sh -r <role> -t "<task_instructions>" -d <working_directory>
   ```

   `delegate.sh` runs `openhands --headless` with a **sanitized environment**
   (NVIDIA key and routing vars only — no Freebuff credentials are passed to the
   subprocess) and captures the exit code. It enforces the Docker sandbox and
   refuses `RUNTIME=process` unless explicitly allowed.

4. Return to the user:
   - The exit code (0 = success, 1 = task failed, 2 = invalid args, 3 = unsafe
     local config). **Never claim success on exit code 1.**
   - A summary of the last observations the subagent produced.
   - For browser/design tasks: the screenshot paths or images captured during the
     run, so the user can verify visual changes.

# Constraints

- **Rate limit:** each agent iteration costs 1+ NIM API calls (~40 RPM free
  baseline). Prefer small, focused delegations; expect 429s under load.
- **Headless = always-approve:** the subagent auto-executes every action. Only
  delegate on explicit user intent; never chain this from an unattended loop.
- **Sandbox (enforced):** Docker by default — agent commands run inside a
  container; only the delegated directory and any `SANDBOX_VOLUMES` are shared
  with the host. `RUNTIME=process` (no isolation) is **refused** unless
  `ALLOW_PROCESS_SANDBOX=1` is set. Never mount credential directories.
- **Isolation limits:** the sandbox has network egress — the agent can reach the
  internet. Keep secrets out of the delegated workspace. Headless auto-approves
  every action and `--llm-approve` is unavailable in headless, so isolation,
  not approval, is the safeguard.
- **Do not modify any Freebuff client code, config, or network behavior.** This
  skill is a local subprocess only (see docs/WHY.md §1b/§1c).
- The NVIDIA API key must never appear in chat output or logs.
