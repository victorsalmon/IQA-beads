---
name: qa
description: >
  Session-close pipeline audit for IQA-Beads. Consumes the maintain skill's
  report verbatim and audits the testing pipeline over exactly the groomed
  list: pipeline-staleness check, gap tests for every touched invariant,
  create-or-refactor where the session proved no pipeline could catch the
  defect class. Full regression green is evidence, never a merge gate. Use on
  the Close Session command (or Catch-up) after Maintain.
version: "0.1.0"
author: "Victor Salmon <https://github.com/victorsalmon>"
license: "MIT"
triggers:
  - model
  - Close
  - Closing
  - Catch-up
---

# QA — close pipeline audit (Close Step 2)

Runs after the `maintain` skill, over **exactly the groomed file list** from
the Maintain report (passed verbatim in the brief — never re-derived, never
widened). Part of the `iqa-beads` plugin. Concrete commands (focused vs full
suite, route/coverage checks) come from the repo's `adapter-template`
worksheet — this skill fixes the procedure, never the command lines.

## Step 1 — pipeline-staleness audit

For every entry on the groomed list, answer: *which pipeline would have caught
this defect class, and did it?*

- Drop or rewrite tests left stale by the groom (superseded code's tests go
  with it — flagged by Maintain, removed here).
- Flag matrices/registries whose rows no longer match shipped code (fix the
  matrix, not just the test).
- Route coverage: any new/changed route, page, or operation without a spec is
  a finding, even at 100% line coverage.

## Step 2 — gap tests (layered)

- **Examples/unit:** named boundaries, validation, error mapping, formatting,
  isolated algorithms.
- **Integration/contract:** real handlers, DB constraints/transactions,
  serialization, queues, storage, service adapters; substitute only external
  boundaries. For third-party sandboxes: run every public function against the
  real sandbox (request mapping, auth round-trip, response shape, error
  mapping), gated behind an env flag so the default suite stays fast.
- **Property/invariant:** every invariant the session touched gets a property
  or model-based test with domain-valid generators, shrinking, and recorded
  seeds — not only examples. Financial math, auth decisions, destructive
  transitions, reconciliation, and idempotency boundaries always qualify.
- **E2E:** changed flows get or extend a journey spec covering the reported
  symptom end-to-end.

**Create or refactor** a pipeline when the session proved none could catch the
defect class — a new property, a new spec, a widened matrix, a corrected
assertion. Deleting a test that cannot fail is in scope.

## Step 3 — adequacy check

Use the repo's documented thresholds when they exist; otherwise require:

- Groomed list: 100% of touched public behaviors mapped to a layer; zero
  unexplained gaps.
- Changed code: every meaningful mutant addressed (see `nightly-stryker`);
  branch coverage ≥90% overall, ≥95% on critical code — never a substitute for
  mutation proof.
- Properties: every touched algebraic, conservation, state, authorization,
  round-trip, idempotency, and isolation invariant implemented or explicitly
  inapplicable with a reason.
- Zero unowned flakes; skips intentional, counted, justified.

A full green regression is reported **as evidence**, never used as a merge
gate. A report that says "green" must name its gate (suite, spec file, seed).

## Step 4 — handoff to nightly

The testing changes for **non-stale items only** go to the `nightly-stryker`
queue (one entry, via `scheduling` — never a duplicate). The report closes
with: deployed ref, maintained surfaces, pipelines created/refactored, and
the queued nightly entry id.

## Red lines

- Never audit outside the groomed list (widening needs a recorded session
  decision).
- Never weaken an assertion to kill a mutant or green a suite.
- Never gate a shipped hotfix on the full battery — pass-1 rule: focused
  green + review passed ships; this pass hardens after.
