---
name: adapter-template
description: >
  Repo-adapter worksheet for IQA-Beads. Resolves the five repo-specific slots
  the session core needs (deploy target, test commands, secrets profile, QA
  matrices, branch convention) plus the Beads DB home, before the first
  session on a new repo. Copy this file per target repo and fill it in — the
  session never guesses these values. Not a session skill; a worksheet.
version: "0.1.0"
author: "Victor Salmon <https://github.com/victorsalmon>"
license: "MIT"
triggers:
  - model
---

# Adapter worksheet — per-repo slots for IQA-Beads

Copy this file to `adapter-<repo>.md`, fill every slot, and point the session
at it before Phase 0. If the repo has no value for a slot, ask the user and
record the answer here — never guess (a wrong deploy target or secrets profile
looks exactly like a provisioning failure).

## Slot 1 — Deploy skill + target

- Redeploy command/runbook for the dev/test site the user tests:
  `_______________________________________________`
- Dev URL the user tests: `_______________________________________________`
- How to verify the deploy fired (log line, endpoint, NOT just exit code):
  `_______________________________________________`
- Rule: hot-lane deploys go to dev/test only — never prod mid-session. The
  session owns the deploy; workers never deploy.

## Slot 2 — Test commands (focused vs full)

- Focused (pass 1, per fix): `_______________________________________________`
- Full battery (pass 2, `qa` skill): `_______________________________________________`
- Route/coverage checks, if any: `_______________________________________________`
- Mutation runner + scope flags (`nightly-stryker`):
  `_______________________________________________`

## Slot 3 — Secrets profile (existence only, never values)

- Secrets universe/profile owning this repo's dev env:
  `_______________________________________________`
- Verify existence only (names/metadata, never bodies):
  `_______________________________________________`

## Slot 4 — QA matrices to import

- Existing human test plans / button matrices (reuse, don't redo):
  `_______________________________________________`
- Reconcile rule: `scan ∖ matrix` = new tracker rows; `matrix ∖ scan` = stale
  flags (flag, don't silently rewrite the source doc).

## Slot 5 — Review branch + trunk convention

- Review branch: `iqa2/scan-<date>` in the target repo (never on a product
  trunk; commits per concern, explicit paths only, never mass-add).
- Trunk + merge: from the trunk worktree `git merge --no-ff <branch>`, then
  push. Trunk name: `___________`
- Lane worktrees live under `<repo>/.worktrees/<lane>`; remove with the
  worktree command (never plain delete), then prune.

## Slot 6 — Beads DB home

- Session trunk worktree owning `.beads/` (created by
  `scripts/Invoke-Iqa2BeadsInit.ps1`; record the `bd` version in the handoff):
  `_______________________________________________`
- Session logs: `<repo>/IQA2/<date>-<iteration>.md` (one file per session,
  per-issue ID + user words + what-was-done + user status + `beads-id`).

## Worked example (shape only — replace with repo values)

| Slot | Example value |
| :--- | :--- |
| Deploy | post-merge hook → deploy script; verify from the deploy *log body* |
| Focused test | single affected spec / frontend suite |
| Full battery | repo-wide suite + journey specs |
| Secrets | repo's own profile (verify existence-only) |
| Matrices | `docs/qa-*` human plans |
| Branch | `iqa2/scan-2026-10-05`, merged from the trunk worktree |
| DB home | session trunk worktree `.beads/` |
