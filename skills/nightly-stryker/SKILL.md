---
name: nightly-stryker
description: >
  Unattended mutation re-proof for IQA-Beads. Matures the close pass's testing
  changes with incremental mutation runs (branch-only, never CI, never on the
  user's critical path). Survivors are evidence dispositioned next session;
  assertions are never weakened to kill a mutant. Use when queueing the Close
  Step-3 task and when running the queued nightly mutation batch.
version: "0.1.0"
author: "Victor Salmon <https://github.com/victorsalmon>"
license: "MIT"
triggers:
  - model
  - nightly
  - mutation
---

# Nightly-Stryker — mutation re-proof (Close Step 3 + nightly run)

Proves the `qa` pass's pipeline changes can detect real defects. Part of the
`iqa-beads` plugin; queued via the `scheduling` skill, run unattended on a
branch. Concrete runner commands come from the repo's `adapter-template`
worksheet — this skill fixes the discipline, never the command lines.

## The incremental rule (non-negotiable)

Every mutation invocation runs with **incremental mode enabled** (carry mutant
state across runs; re-run only mutants whose covering tests or source
changed). Rationale: full sweeps re-run every mutant on every pass, which is
how a 40-minute package becomes an all-night one.

- The first run after enabling — or after a deliberate state reset — is a cold
  warm-up (runs all mutants) and is allowed.
- A deliberate full re-run requires explicit operator approval, recorded on
  the schedule entry and logged in the run. No silent full runs.

## Queueing (Close Step 3)

- Queue **exactly one** re-proof task for the changed testing infra of
  **non-stale items only**, on that evening's batch (see `scheduling`).
- Never duplicate an existing queued task. Scope the entry to the ports /
  packages the diff touched so the runner can run the minimal set.
- Branch-only, never CI; never on the user's critical path.

## Running (unattended batch)

1. Run the scoped incremental set first; expand to the full portfolio only if
   the scoped run is green and the batch window allows.
2. Capture killed / survived / no-coverage / timeout / compile-error /
   equivalent-candidate counts with the evidence path.
3. Inspect every survivor. Strengthen tests **only** when the mutant represents
   observable incorrect behavior — never assert implementation trivia merely
   to kill a mutant.

## Survivor disposition (next session, test-only)

- Below-threshold scores and survivors are **evidence**: record them against
  the shipped commits and repair test-only next session (max 2 iterations).
- Never weaken an assertion to kill a mutant. An equivalent-mutant claim needs
  exact location + transformation + proof; a threshold waiver needs owner +
  expiry + compensating evidence + queued remediation.
- Do not hide `NoCoverage`, timeout, or compile-error mutants inside a score.

## Red lines

- No full runs without recorded operator approval.
- No mutation runs inline with day work — unattended batch only.
- Failures fail only the nightly job — never gate day work.
