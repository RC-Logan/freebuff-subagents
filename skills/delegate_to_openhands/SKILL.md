---
name: delegate_to_openhands
description: Dispatches complex multi-step coding, debugging, file-editing, terminal,
  or browser/design tasks to an autonomous OpenHands subagent running against NVIDIA
  NIM. Restores the former Freebuff base2 subagent roles (browser-use, researcher,
  code-editor, code-reviewer, context-pruner) safely: the role selects the model
  (MiniMax-M3 for vision/browser, GLM-5.2 for text/code), and every delegation runs
  in a Docker sandbox with a sanitized environment.
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
      description: Subagent role, like the former Freebuff base2 subagents. Picks the
        model and task discipline; see ROLES.md in the repo. Overridable via model.
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

1. Resolve the model for the requested `role` from ROLES.md (browser-use →
   minimaxai/minimax-m3; all others → z-ai/glm-5.2) unless `model` is given
   explicitly. Bake the role's task discipline into `task_instructions`.
2. Write `task_instructions` to a temporary task file.
3. Run the wrapper from this repo's checkout (never inline-shell the task — quoting
   breaks on quotes/newlines):

   ```bash
   cd <repo> && ./bin/delegate.sh -f <task_file> -d <working_directory> -m <model>
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
