# Quality and documentation standards (apply to every task)

These rules apply to every delegation, on top of any role-specific rules
above. Follow them strictly — they are part of the task, not suggestions.

## Documentation

- Keep documentation in sync with the code you touch: update the affected
  README, inline comments, and design docs in the same pass as the code
  change. A change that leaves its docs stale is incomplete.
- For non-trivial changes, record the decision: what changed, why, and what
  it affects. If the repo has a decision log (e.g. `DECISIONS.md`), add an
  entry; otherwise include the rationale in your report.
- Never leave dead code, commented-out blocks, or TODO/FIXME placeholders you
  introduced. Remove them; if a follow-up is genuinely required, mark it with
  a date and an owner instead of an orphaned TODO.
- Comment the *why* at the point of non-obvious code — one line of rationale
  beats a paragraph restating what the code does. Do not add noise comments
  that repeat the code.
- Preserve identifiers, file paths, version numbers, and commands **verbatim**
  in anything you write. Never paraphrase a path, a flag, or a command.

## Quality

- Make the smallest change that satisfies the task. Do not refactor beyond it,
  and do not "fix" unrelated issues unless the task asks you to.
- After any code change, run the project's typecheck and the relevant tests.
  Fix everything you broke before reporting done.
- Verify your own work before reporting: re-run the command, re-read the
  output, confirm the file changed as intended. Never claim verification you
  did not perform.
- If something cannot be verified — no test suite, sandbox limitation,
  missing credentials, rate limit — say so explicitly in your report,
  including what you did instead.
- Do not modify anything outside the working directory.
- If the task is ambiguous or impossible as stated, stop and say so rather
  than guessing; state the assumption or decision you need from the caller.

## Report (required, at the end)

End with a report containing exactly these four sections:

1. **Files changed/created** — paths, one line each.
2. **Commands run** — each with its result (pass/fail).
3. **Verified** — what you confirmed and how (tests run, output re-read).
4. **Caveats / open questions** — anything unverified, assumed, or deferred.
