---
name: iqa-beads
description: >
  Beads-backed Interactive Quality Assurance. Answers "what's stopping me from
  user-testing this product today?", builds a live tracker that is a Beads issue
  graph dual-written with a markdown tracker, then runs a conversational UAT
  session where the user reports bugs and the agent triages each one. Work runs
  in three passes: interactive (code - review - commit - push - merge to the
  trunk - deploy - retest ping, on the user's critical path), close (Maintain
  drift-groom + QA pipeline audit, over every file the session changed), and
  nightly (mutation re-proof). Use whenever the user says "IQA-Beads" or the
  legacy alias "IQA2". Never fires on bare "IQA" alone.
version: "0.1.0"
author: "Victor Salmon <https://github.com/victorsalmon>"
license: "MIT"
triggers:
  - user
  - model
  - IQA-Beads
  - IQA2
---

# IQA-Beads — Beads-backed Interactive Quality Assurance (session core)

Run an interactive QA session against a deployed web product (or local
full-stack) in four phases — **blocker analysis → populate tracker → live
dual-lane session → summary** — across three passes
(**interactive → close → nightly**). The live tracker is a **Beads issue graph
dual-written with the markdown tracker**.

## The one rule

**The user never waits on the agent.** The interactive agent stays with the
user, captures each report in under a minute, and dispatches detached worker
subagents for fixes, plans, and batteries. Full rigor, full-suite runs, and
mutation proof happen in the later passes — never on the user's critical path.

**The interactive agent is an orchestrator, not a worker.** During a session it
MUST NOT perform execution work inline: no product-code edits, no skill/runbook
edits, no test authoring or test-battery runs, no long investigation passes.
Anything execution-shaped is **dispatched to a background worker**. Inline work
freezes the chat while the user waits — the failure this skill exists to
prevent.

**Detached only.** Workers are always background/detached agents with a brief
file in, `.iqa-report.md` out. A harness whose subagents are foreground-only is
not a dispatch target for IQA lanes.

## What is genuinely Beads-specific (everything else is session discipline)

- **Graph shape.** One Beads `epic` per IQA-Beads list, one bead per item
  (`blocks` for ordering, `discovered-from` for every agent-created
  split/find, `related` for combined fixes); user status lives in labels
  (`iqa:awaiting-validation` → `iqa:validated:<date>`), never in Beads
  `closed`. Full mapping: [REFERENCE.md](REFERENCE.md) → `## Beads field mapping`.
- **Computed ready queue.** `bd ready` (via `scripts/Get-Iqa2Ready.ps1`)
  computes the unblocked queue instead of eyeballing tracker rows; the
  tracker-table fallback keeps the same queue shape without the binary.
- **Bead-claim dispatch.** At dispatch the session applies the atomic claim
  (`bd update <bead> --claim`) with agent id + lane label; every brief carries
  the bead identity block (epic id, bead id, edge list). Workers never run
  `bd` — all Beads mutations go through the session.
- **Lifecycle guardrails.** Embedded-mode DB per session
  (`scripts/Invoke-Iqa2BeadsInit.ps1`, `.beads/` gitignored, never committed),
  orchestrator-serialized writes on a named OS mutex, no shared-remote sync,
  version pin + skew rule, `closed` ≠ validated, kill criteria with
  semantics-only fallback.
- **Export-first close.** Pass 2 runs Maintain → QA → Nightly queue **plus a
  Step-0 Beads export** (`scripts/Export-Iqa2Beads.ps1` → tracker tally + log
  fragment) before Maintain starts.
- **Lists, branches, logs.** IQA-Beads lists are `IQA2-A…` (items `2A-1…`,
  agent block `2A-100+`); trackers are `<date>-<repo>-iqa2-test-tracker.md`;
  logs live in `<repo>/IQA2/`; review branches are `iqa2/scan-<date>`.
- **Session = one list + its tracker + its epic.** Identity, not calendar time:
  a session MAY span days; nothing auto-rolls. The USER decides when to open a
  new session and when to Close.

## The three passes

| Pass | When | Owns | Must never block |
|---|---|---|---|
| **1 — Interactive** | live, this session | capture → code → review → commit → push → `merge --no-ff` into trunk → deploy → retest ping | the user's next test |
| **2 — Close** | session end, on the **Close Session** command | sequenced **Export → Maintain → QA → Nightly queue** (sibling skills `maintain`, `qa`; queue via `scheduling`) | nothing live |
| **3 — Nightly** | queued, unattended | **mutation** re-proof (`nightly-stryker`); survivors dispositioned next session | anything |

Pass-1 rule: a fix that is coded, reviewed, and green on its *focused* suite
**merges and deploys** — it does not wait for the heavy battery. The
outstanding rigor is carried by the close pass and recorded as a task.

## Phase 0 — Blocker analysis (+ Beads DB health)

Identical QA-reachability checks as any interactive-QA front door (deployment
reachable, secrets exist, build in a worktree, branch/worktree state; verdict
READY / DEGRADED / BLOCKED), plus:

- `bd status` in the session worktree answers with the session epic present.
  Any schema-skew error = BLOCKED for the graph (session may proceed
  semantics-only on explicit user approval, recorded in the handoff).
- Bugs found *during* the blocker scan are triaged immediately per Phase 2.

## Phase 1 — Populate the tracker

1. Inventory real surfaces — pages/routes, backend routes, API endpoints.
2. Import existing QA docs — prior matrices are reused, not redone.
3. Reconcile — `scan ∖ matrix` = new rows; `matrix ∖ scan` = stale flags.
4. Write the tracker: one row per testable workflow with surface, coverage
   status, test status (`untested` initially), bug-ref, notes, **plus a
   `beads-id` column** (machine-readable contract: [REFERENCE.md](REFERENCE.md)
   → `## Tracker table contract`).
5. Create the graph — session epic `IQA2-A` via `bd create -t epic`, one bead
   per pre-existing known issue.

## Phase 2 — Live dual-lane session

- **Capture (≤1 min).** Verbatim + expected vs actual + repro steps. Create the
  bead in the same step (`bug`, parent epic, `iqa:list,iqa:id,origin:user,
  severity:*` labels, verbatim note). One symptom = one item; splits mint new
  beads with `discovered-from` + `split from 2A-3` notes.
- **Severity.** Blocker → `p0` / Major → `p1` / Minor → `p2`. Question /
  operator action / external dependency → Manual task file (never the graph).
- **Triage.** Hotfix-whitelist (typo, obvious guard, unambiguous selector,
  dead import, obvious a11y) → hotfix lane; business logic, multi-file,
  schema, ambiguity, deps/infra, security-adjacent → deep-only Printed plan
  with mandatory sibling hunt. When in doubt, deep plan, skip the hotfix.
- **Dispatch.** Write the brief, apply the bead `--claim` (+ agent id + lane
  label), launch the background worker, alert the user with the item ID. Max 6
  concurrent workers; overflow waits as unclaimed open beads + tracker rows.
- **Review → merge → deploy → ping.** Read-only review against acceptance
  criteria; session merges (`git merge --no-ff`) and deploys; ping
  `REDEPLOYED <sha> → <url> — hard-reload and re-test: "<verbatim>" [<id>]`;
  then `bd close <bead>` + `iqa:awaiting-validation` — never `validated` on
  anyone's behalf.

## Validate / Close / Catch-up

- **Validate List** = every bead with `iqa:awaiting-validation` across open
  lists (label query + log reconcile; log wins on status, graph wins on
  edges/refs). Only the user's explicit words flip to `iqa:validated:<date>`.
- **Close Session** (`Close`, `Closing`, `to Close a Session`,
  `Close IQA-Beads session`): Step-0 export, then the `maintain` skill, then
  the `qa` skill fed by the Maintain report verbatim, then queue exactly one
  `nightly-stryker` task via `scheduling`, then roll the list (`2A` → `2B`).
- **Catch-up** (half of Close): session-owned deploy-verify first, then Tidy,
  then one detached Maintain+QA worker over validated-terminal items only —
  no nightly queue, no list roll, no validation flips. The worker's goal is
  leaving the codebase better than found (Tidy: RW-safe hygiene first;
  everything except testing; QA: test accuracy rebuild); a better-direction
  verdict escalates as a Trade-Offs Tipping Point — relayed to the user, new
  lane only with permission. Normative scope: [REFERENCE.md](REFERENCE.md) →
  `## Catch-up (Beads delta)`.

## Dispatcher mode

An alternative to the interactive dual-lane session for clearing a whole
list: the session acts as a **dispatcher** — it mints beads, dispatches
detached lane agents per unblocked bead, reviews their work, and lands it
(session merges, deploys, closes). The session itself does no build work
except merges, gates, secrets handling, and host operations lanes cannot own.

- **Session owns beads/merge/deploy/close.** Lanes never merge to trunk,
  never deploy, never run `bd` (create/claim/close/label all session-side),
  never self-certify. Claim (`bd update <id> --claim`) + comment (lane
  agent id, branch, scope) at dispatch.
- **One lane per bead, cap 6 concurrent.** Overflow stays queued with
  blockers named. One lane may cover several beads with separate commits
  per bead; keep hunks tight.
- **Lane briefs carry:** bead IDs + `bd show` instruction, exact file
  pointers from recon, what NEVER to do (merge/deploy/close, prod writes,
  secrets in repo/chat), test requirements, and the terse final-report
  format (results with numbers, commit SHAs, unfinished items).
- **Three-phase separation — one bead, three different agents.** The
  dispatcher runs every bead through recon (read-only: symptom → root
  cause → blast radius → file pointers + test plan, no product code),
  then code/build (implements the recon plan only; focused tests; never
  merges/deploys/closes), then review (a different agent than the first
  two: verifies against acceptance + visible proof, re-runs gates,
  ACCEPT/REJECT with reasons; max 2 build iterations, then escalate).
  Exception: typo/config-tweak-class changes may combine recon+code with
  dispatcher-recorded justification — review is always separate.
- **Visible-proof acceptance.** Every bead's acceptance names the
  user-visible proof: route + what renders + what disappears, verified in
  a browser (signed-in where auth-gated) by someone other than the lane
  author. Test-shaped criteria alone ("suite X green") never close a UI
  bead. (Learned the hard way: a lane once built a new rail component,
  tested it in isolation, passed gates, and closed — while the page kept
  rendering the old rail, because no criterion required the wiring.)
- **Deployed-before-awaiting.** A bead takes `iqa:awaiting-validation` only
  when its merge is proven inside the deployed artifact, never on "merged
  to trunk" alone.
- **Completion is the default.** Lanes satisfice ("mostly done" + follow-ups).
  The brief carries the definition of done as a mechanical checklist (code +
  tests, named suites green, typecheck clean, owning docs diffed, branch
  pushed, evidence pasted), ends with a built-in second pass ("re-read each acceptance
  criterion, verify every box with evidence, complete anything unverified
  NOW"), and reserves NOT Finished for external blockers only (operator
  input, another bead, missing secret — with owner and what's needed).
  Leftovers completable inside the lane get re-prompted to the same agent
  once before partial is accepted.
- **Lanes rebase onto trunk before finishing.** A lane that branched hours
  ago discovers conflicts in-lane (author context lives there), not in the
  session merge queue: every brief carries "rebase onto origin/trunk (or
  merge it in) before the final test run and push."
- **Concurrent sessions.** Check the live site + trunk log before host-level
  work (a gate window fits a whole parallel lane); never touch another
  session's lanes/branches/worktrees/bead content; renumber on ID collision
  with notes on both beads; clean up host orphans you created.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/Resolve-Iqa2Bd.ps1` | locate `bd` (PATH, then well-known shims) |
| `scripts/Use-Iqa2DbLock.ps1` | per-database mutex (single-writer enforcement) |
| `scripts/Invoke-Iqa2BeadsInit.ps1` | embedded session DB + epic, no-push hardening |
| `scripts/Get-Iqa2Ready.ps1` | ordered ready queue; `-TrackerFile` fallback without `bd` |
| `scripts/Export-Iqa2Beads.ps1` | graph → tally + log fragment (read-only vs Beads) |

Normative Beads mechanics continue in [REFERENCE.md](REFERENCE.md). Repo-specific
slots (deploy, test commands, secrets, matrices, branches) come from the
`adapter-template` worksheet — this core never guesses them.
