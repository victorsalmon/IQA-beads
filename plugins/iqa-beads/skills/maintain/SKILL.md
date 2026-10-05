---
name: maintain
description: >
  Session-close drift groom for IQA-Beads. Runs stale-first over the session's
  validated-terminal items, then fixes drift (session record, planning docs,
  contracts, skill pointers, indexes/manifests) over the groomed list. Testing
  is explicitly out of scope — pipeline work belongs to the qa skill, which
  consumes this skill's report verbatim. Use on the Close Session command (or
  Catch-up) after the Step-0 Beads export.
version: "0.1.0"
author: "Victor Salmon <https://github.com/victorsalmon>"
license: "MIT"
triggers:
  - model
  - Close
  - Closing
  - Catch-up
---

# Maintain — close drift groom (Close Step 1)

Runs at session close over **every file the session changed**, sequenced
**Export → Maintain → QA → Nightly queue**. The Step-0 Beads export
(`scripts/Export-Iqa2Beads.ps1`, diffed + reconciled against the tracker) is
already done — this skill starts after it. Part of the `iqa-beads` plugin;
normative graph mechanics live in `../iqa-beads/REFERENCE.md`.

## Step 0 — entry conditions

- The export counts (open / awaiting / validated / deferred per list) are
  recorded in the session log header.
- Scope = the session's validated-terminal items (`validated resolved` +
  `closed (operator directive)`) plus every file those items touched. Not a
  whole-codebase sweep: the likely-affected areas below, never widened without
  a recorded session decision.

## Step 1 — stale-first (before any other work)

Mark superseded / moot / not-useful list items stale **first**, with the
superseding commit/item ID, in three places:

1. the markdown tracker,
2. the session log (`<repo>/IQA2/<date>-<iteration>.md`),
3. the bead, as `iqa:operator-closed:<reason>`.

Steps 2–3 must never build tests for dead code. Tests covering superseded code
go with it (flagged here, removed in the `qa` pass).

## Step 2 — drift over the groomed list

| Surface | Target |
| :--- | :--- |
| Session record | `<repo>/IQA2/<date>-<iteration>.md` + tracker tally + active-list row |
| Planning docs | roadmap / implementation plan / human test plan — wherever coverage or blind spots moved |
| Contracts | route/shell contracts, ADRs, glossary |
| Drift | stale runbook copies duplicating a canonical skill, skill pointers that no longer name the canonical skill, moved paths, docs that now contradict shipped code, contracts restated where they already have an owner, stale indexes and manifests (skill indexes, QA matrices, route/contract registries) |

**Scope rule:** the likely-affected areas above — not a whole-codebase sweep.
**Testing is explicitly out of scope here** — pipeline staleness and gap tests
belong to the `qa` skill.

## Step 3 — Maintain report (the handoff)

Write the report with three sections, and pass it **verbatim** into the `qa`
brief (never re-summarized away):

1. **Stale dispositions** — item, verdict, superseding commit/item ID.
2. **Drift fixes** — file, what contradicted code, what changed.
3. **Groomed file list** — the exact set the `qa` pass audits. The `qa` pass
   covers exactly this list: never re-derived, never widened.

## Red lines

- Never flip user validation (user-gated — the session log wins).
- Never author tests or run batteries here — that is the `qa` skill.
- Never touch another lane's active worktree/branch.
- Stage explicit paths only; never mass-add.
