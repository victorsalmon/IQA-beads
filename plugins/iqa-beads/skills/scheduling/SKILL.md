---
name: scheduling
description: >
  Unattended-batch protocol for IQA-Beads. Owns the live-list convention
  (Pending checklist + Run log), the layered run order (groom first, then QA
  restoration, then mutation, then close-out), the preflight, the house rules,
  and the fail-closed acceptance gate. The nightly-stryker queue and any Catch-up
  re-proof enter through this skill. Use when queueing overnight work or when
  running the batch as the orchestrator lead.
version: "0.1.0"
author: "Victor Salmon <https://github.com/victorsalmon>"
license: "MIT"
triggers:
  - model
  - Goodnight
  - good night
  - nightly
---

# Scheduling — unattended-batch protocol

"Goodnight" is a **command**, not a farewell. It triggers the batch of heavy
work — mutation runs, QA batteries, requeues — that must never run inline with
day work. Part of the `iqa-beads` plugin. Never dispatched standalone as a
worker task — it is the protocol the orchestrator lead follows.

## Live-list convention

Each cadence owns one mutable state file (example default:
`<state-dir>/scheduled/nightly.md`). The file holds three sections; **the file
decides the work, this skill fixes the protocol**:

- **Pending** — `[ ]` todo, `[~]` in-flight/blocked with inline notes.
- **House rules** — a pointer back here plus repo-specific deltas.
- **Run log** — newest first, `YYYY-MM-DD HH:mm — items — outcome — evidence`.

Queueing rules: one entry per task, never a duplicate; a day agent that
notices smell mid-task appends a Pending line instead of fixing inline; heavy
batteries never run inline with day work.

## Layered run order

| # | Layer | What it does |
| :- | :--- | :--- |
| 0 | **Groom (FIRST)** | Clean temp/auxiliary worktrees and branches *before* any heavy run. Merge the still-useful ones into the integration trunk; cherry-pick anything worth keeping out of a stale one, then delete it. |
| 1 | **QA restoration** | Refactor or extend the QA pipeline so coverage is restored to full; record what the run learned. |
| 2 | **Mutation** | Incremental runs (`nightly-stryker`) that mature the layer-1 changes. |
| 3 | **Close-out** | Commit, push, build, trunk-merge, deploy; record SHAs and refs. |

A night that hardens tests but leaves the repo littered with dead branches has
not finished the job.

## Preflight (before dispatching anything)

For every target repo:

1. Confirm the canonical checkout is **clean and trunk-current**; run the
   repo's generated-dirt gate where one exists and **commit or route** any
   tracked generated artifact before dispatching. (Generated evidence —
   mutation/coverage aggregates — is runtime state, never committed.)
2. **Skip or defer** any repo with an active lane — in-flight task markers,
   worktree leases, live heartbeats, or a lane worktree with uncommitted edits.

## House rules (binding on every batch)

- **One writer per repo; one heavy battery per repo at a time.** Serialize
  heavy jobs per-repo, parallelize only across repos.
- **Mutation runs incrementally, always** (see `nightly-stryker`). A deliberate
  full/fresh run needs explicit operator approval recorded on the entry.
- **Failures fail only the batch job** — never gate day work. Record every
  item's evidence path.
- **Never mutate another agent's active task, lock, or leased worktree.**

## Protocol for the orchestrator lead

1. Read the live list fully. Pending `[ ]` items are tonight's work; `[~]`
   items resume from their inline notes. Run layers in order.
2. Preflight every target repo; groom (layer 0) finishes before that repo's
   layers 1–2 start.
3. Dispatch one background worker per workstream; wait on completion
   notifications rather than polling (poll state at least every 15 minutes
   while workers are in flight regardless).
4. Verify each dispatch against the acceptance gate below — the lead, not the
   worker, decides.
5. Append a Run log entry and post a short morning report: per item the
   verdict, the trunk SHA, and the deploy ref.

## Acceptance gate (fail-closed)

Per dispatch: `accepted (<trunk-sha>)`, `blocked (<reason>)`, `deferred`, or
`no-op`. A dispatch that produced artifacts but could not land is **blocked,
never done** — it keeps its `[ ]`/`[~]` marker so the next run resumes it. The
run is `accepted` only when every dispatch is accepted or operator-deferred;
otherwise `accepted with N blocked`. Never self-declare `[x]` without the merge
evidence behind it.
