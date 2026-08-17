# Repo hygiene (for agents working on this repository)

These are the standards for anyone — human or agent — making changes to
**this** repo. They apply to work *on this repo*, not to delegated tasks:
delegations are the caller's project, and quality there is the caller's call.

They keep the repo self-consistent and its decision history readable, and
they are enforced by the pre-run test suite.

## Before changing anything

- Read the current state first: `README.md` (what it is, how to use it),
  `ROLES.md` (capability roles), `DECISIONS.md` (why things are the way they
  are), and `docs/WHY.md` (why this repo exists).
- Respect the **safe boundary** in the README: never modify Freebuff client
  behavior or interact with Freebuff's servers differently than the client
  already does.

## When making changes

- Keep documentation in sync with the change **in the same pass**: README,
  inline comments, ROLES, and the decision log. A change that leaves its docs
  stale is incomplete.
- Record decisions in `DECISIONS.md` with a dated entry: what changed, why,
  and what it affects. The "why" matters as much as the change.
- Make the smallest change that satisfies the task; do not refactor beyond
  it.
- Never leave dead code, commented-out blocks, or orphaned TODO/FIXME
  placeholders. If a follow-up is genuinely required, date it and name an
  owner.
- Comment the *why* at non-obvious code — one line of rationale beats a
  paragraph restating the code. Do not add noise comments.
- Preserve identifiers, file paths, version numbers, and commands **verbatim**
  in anything you write.

## Before committing

- Run `./tests/run-tests.sh` — the suite must pass (65 assertions, macOS 27).
- Verify your own work: re-read the diff, re-run what you changed.
- If something cannot be verified, say so in the commit message or report —
  never claim verification you did not perform.
- Commit messages explain the *why*, not just the *what*.

## Reporting

End your work with: files changed, commands run + results, what you verified,
and any caveats or open questions.
