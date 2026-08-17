---
name: delegate_to_openhands
description: Dispatches complex multi-step coding, debugging, file-editing, terminal,
  or browser/design tasks to an autonomous OpenHands subagent running against NVIDIA
  NIM. Use GLM-5.2 for text/code reasoning; use MiniMax-M3 for tasks requiring vision,
  screenshots, or browser use (the main thread model may be text-only).
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
    model:
      type: string
      description: NIM model ID for this run.
      default: z-ai/glm-5.2
      enum: [z-ai/glm-5.2, minimaxai/minimax-m3]
  required: [task_instructions]
---

# Execution

1. Write `task_instructions` to a temporary task file.
2. Run the wrapper from this repo's checkout (never inline-shell the task — quoting
   breaks on quotes/newlines):

   ```bash
   cd <repo> && ./bin/delegate.sh -f <task_file> -d <working_directory> -m <model>
   ```

   `delegate.sh` runs `openhands --headless` with a **sanitized environment**
   (NVIDIA key and routing vars only — no Freebuff credentials are passed to the
   subprocess) and captures the exit code.

3. Return to the user:
   - The exit code (0 = success, 1 = task failed, 2 = invalid args). **Never claim
     success on exit code 1.**
   - A summary of the last observations the subagent produced.
   - For browser/design tasks: the screenshot paths or images captured during the
     run, so the user can verify visual changes.

# Constraints

- **Rate limit:** each agent iteration costs 1+ NIM API calls (~40 RPM free
  baseline). Prefer small, focused delegations; expect 429s under load.
- **Headless = always-approve:** the subagent auto-executes every action. Only
  delegate on explicit user intent; never chain this from an unattended loop.
- **Sandbox:** default is Docker (isolated). If `RUNTIME=process` is set there is
  no container isolation — scope `working_directory` tightly.
- **Do not modify any Freebuff client code, config, or network behavior.** This
  skill is a local subprocess only (see docs/WHY.md §1b/§1c).
- The NVIDIA API key must never appear in chat output or logs.
