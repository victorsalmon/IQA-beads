# IQA-Beads — reference (normative Beads mechanics)

Adjacent reference for [SKILL.md](SKILL.md). This file owns the Beads tracker
mechanics; sibling skills (`maintain`, `qa`, `nightly-stryker`, `scheduling`)
and the `adapter-template` worksheet profile against it by reference — never
restate it. Where this file seems to disagree with `SKILL.md`, `SKILL.md` wins
on session discipline; this file wins on graph mechanics.

Artifact names keep their `IQA2` / `2X-` / `iqa2/` shapes below (list IDs, log
dirs, branches, tracker filenames, script filenames) — those are namespaces,
not the skill name. Primary token `IQA-Beads`; `IQA2` is the permanent legacy
alias.

## Beads field mapping

### Identity

| IQA-Beads concept | Beads target | Rule |
|---|---|---|
| IQA2 list (`IQA2-A`) | One `epic` per list | Epic is identity only; never carries fix work. Roll = new epic (`2A` → `2B`), never rename. |
| User item (`2A-1`) | `bug` bead, `--parent <epic>` | Human key stays `2A-1` (title prefix + `iqa:id` label). Beads hash id is the stable machine key recorded as `beads-id`. Never renumber user items. |
| Agent item (`2A-100+`) | `bug`/`task` bead, `--parent <epic>` | Same 100+ rule; always carries a `discovered-from` edge + parent reference. |
| Tracker row | The bead itself | One symptom = one bead; splits mint new beads. |
| Session log `<repo>/IQA2/*.md` | Export target, not a bead | Close renders beads → the 4-field contract + `beads-id`. |

### Status mapping (normative)

Beads `status` tracks worker state; the IQA-Beads user status lives in labels.
**Beads `closed` never means validated.**

| IQA-Beads user status | Beads `status` | Required labels |
|---|---|---|
| `open` | `open` | `iqa:list=2A`, `iqa:id=2A-12`, `origin:user\|agent`, `severity:blocker\|major\|minor` |
| worker running | `in_progress` + atomic `--claim` | `assignee=<agent-id>`, `lane=<branch>` |
| `fix live, awaiting validation` | `closed` (work shipped) | `iqa:awaiting-validation` present; no `iqa:validated:*` |
| `validated resolved` | `closed` | `iqa:awaiting-validation` removed, `iqa:validated:<YYYY-MM-DD>` added + validation note. Session flips this only on the user's explicit words. |
| `deferred` | `open` + `bd defer` | `iqa:deferred:<reason>`; excluded from ready and Validate List |
| `closed (operator directive)` | `closed` | `iqa:operator-closed:<reason>`; excluded from both |

### Priority / type

Blocker → `p0`, Major → `p1`, Minor → `p2` (trivial copy/CSS may take `p3`);
user reports are `bug`; sibling-hunt hardening and property/mutation
follow-ups are `task` with a `discovered-from` edge. Question/operator/external
items are Manual tasks — never beads.

### Edges

- `blocks` — hard ordering only. Affects `bd ready`. Use sparingly; most items
  are parallel. Only between otherwise-unrelated items — never between a split
  and its parent (the `discovered-from` edge already occupies that pair, and
  Beads holds one typed edge per pair; splits are parallel work anyway).
- `discovered-from` — every 100+ item (splits, sibling finds, blocker-scan
  finds, retest regressions). Non-blocking annotation.
- `parent-child` — list-epic → item only. Never for split relationships.
- `related` — combined-fix Validate bullets (`2A-5 + 2A-108` share one fix).
- `caused-by` — shared root cause links from the sibling hunt.
- `validates` — recon report bead → fix bead link.

### Labels (closed taxonomy)

Reserved `iqa:` prefix: `iqa:list`, `iqa:id`, `origin:user|agent`,
`severity:blocker|major|minor`, `iqa:awaiting-validation`,
`iqa:validated:<date>`, `iqa:deferred:<reason>`,
`iqa:operator-closed:<reason>`, `iqa:carried-into:<next>`,
`lane:<branch>`, plus workflow `needs-review`, `needs-tests`. Component labels
(`backend`, `auth`, …) only if already in use. No spaces in labels
(comma-separate). The session epic carries no labels, so there is nothing to
inherit; if an epic ever gains release/size labels, create children with
`--no-inherit-labels`.

### Metadata / notes

Bead notes carry: verbatim + expected/actual + repro steps; recon scope
answers; brief/report paths; agent-id + lane worktree + branch; hotfix/deep
decision; hotfix commit + deploy ref + deep-plan path; retest ping text;
validation note.

### Ready vs Validate definitions

- **Ready** = `bd ready` (open, no open `blocks` deps) minus
  `iqa:deferred:*`, ordered Blocker → Major → Minor, user-block before 100+
  within a list. Computed by `scripts/Get-Iqa2Ready.ps1`. Proposes; never
  dispatches on its own.
- **Validate List** = every bead with `iqa:awaiting-validation` across open
  lists, grouped by list, footer collapsing fully-validated closed lists.
  Implemented as a label query + log reconcile; reconcile rule: the session
  log wins on user status; Beads wins on graph.

### Carry-over at roll

Carried items keep their `2A-` IDs and gain `iqa:carried-into=2B`; only new
reports mint `2B-` numbers. The new `IQA2-B` epic links `related` to the
closed `IQA2-A` epic for history.

## Beads lifecycle

- **PATH bootstrap.** `bd` lives wherever the installer put it — but shells
  spawned before that change (including long-lived agent hosts) still resolve
  the old PATH. If `bd` is not recognized, refresh the shell or restart the
  host; the plugin scripts fall back to well-known shim paths automatically.
- **Init.** `scripts/Invoke-Iqa2BeadsInit.ps1 -Workdir <session-trunk-worktree>`
  creates one embedded-mode DB (`.beads/`, gitignored, never committed) and
  the session epic (`-Reuse` adopts the recorded epic instead of minting a
  duplicate). Refuses missing workdirs; records the `bd` version in the
  session handoff. Strips any auto-configured Dolt remotes and refuses to
  proceed while one survives.
- **Single writer, enforced.** Only the interactive session runs `bd`
  mutations, one call per lifecycle event (create at capture, claim at
  dispatch, edge/label at merge/deploy/validation). Lanes never run `bd`.
  Enforcement is mechanical: every plugin script serializes on a named OS
  mutex keyed by the database path (`scripts/Use-Iqa2DbLock.ps1`; abandoned
  locks are adopted, timeouts fail loudly instead of racing). A timeout means
  a lane is touching `bd` — find it, stop it, re-run.
- **No shared-remote sync.** No push of the session DB — portability via
  `bd export` only.
- **Skew rule.** On a schema-version-mismatch error: stop, report, upgrade
  the binary — never bypass the guard.
- **Fallback (kill criteria).** Any lost item, any unexplained ready/Validate
  divergence, or lane contention from embedded mode → drop the binary and
  continue semantics-only: the label/edge vocabulary becomes tracker columns
  per the table contract below, and `Get-Iqa2Ready.ps1 -TrackerFile <tracker>`
  produces the same queue shape with a `[tracker fallback]` banner. The mapping
  above is designed so the fallback loses the query engine but keeps every
  semantic. (PowerShell 7 is required for the scripts; POSIX-shell ports are an
  open contribution — the fallback contract is specified precisely so a port
  can be verified against it.)

## Tracker table contract (machine-readable columns)

The semantics-only fallback parses the tracker without Beads. For it to work,
the tracker's item table MUST carry these columns (header names matched
case-insensitively by substring; extra columns free):

| Column | Header match | Values |
| :--- | :--- | :--- |
| ID | `id`, `item` | `2A-12` (rows with any other shape are skipped) |
| Status | `status` | `open` = claimable; `validated resolved`, `closed (operator directive)` = done; `deferred` = parked; anything else = not ready |
| Severity | `severity` | `blocker` / `major` / `minor` (missing = minor) |
| Blocker | `blocker`, `blocked`, `depends` | Zero or more `2A-<n>` IDs (a named blocker counts as blocking unless its own row is done) |
| Symptom | `symptom`, `title`, `description` | One-line text (defaults to the ID) |

Ready = status `open` with no unresolved named blocker, ordered
Blocker → Major → Minor, user-block before 100+, numeric. Keep this table
current on every capture/dispatch/merge/deploy/validation step — in Beads
mode it is the human-readable mirror the export reconciles against; in
fallback mode it IS the queue.

## Pass deltas (Beads additions, in order)

- **Capture dual-writes.** The session creates the bead in the same capture
  step as the markdown tracker row (create + labels + edges + `beads-id`
  column).
- **Ping closes the bead.** After the `REDEPLOYED` ping, the session closes
  the bead (work done) and adds `iqa:awaiting-validation` — never
  `iqa:validated:*` on anyone's behalf.
- **Export-first close.** Pass 2 runs a **Step 0 before Maintain**: run
  `scripts/Export-Iqa2Beads.ps1`, diff the export against the markdown tracker
  and reconcile now (log wins on status, graph wins on edges/refs) — never
  carry divergence silently into Maintain.
- **Stale-first touches beads too.** Stale dispositions land in the tracker
  **and** as `iqa:operator-closed:<reason>` on the bead.
- **Roll mints an epic.** The next session takes the next identity
  (`2A` → `2B`); the new epic links `related` to the closed one.
- **Roll-up adds export counts.** The pass roll-up carries the Beads export
  checksum (counts: open / awaiting / validated / deferred per list).

## Catch-up (Beads delta)

- **Export-first (Step 0, session-side).** Run `scripts/Export-Iqa2Beads.ps1`
  before the worker starts; reconcile now — never carried silently into the
  worker.
- **Worker never runs `bd`.** The single Maintain+QA worker reads bead
  ids/edges from the brief but never mutates the graph; claim/label updates
  stay session-side.
- **Port-forward keeps bead ids.** Carried beads keep their `2X-` IDs and gain
  `iqa:carried-into=<next>`; only new reports mint numbers in the open epic.

## Delegation (Beads additions)

The session-discipline delegation contract (`SKILL.md` → `## The one rule`)
applies unchanged; the bullets below are the Beads deltas:

- **No `bd` writes from workers.** All Beads mutations go through the session
  (single writer).
- **Capture creates the bead** (tracker row **plus** bead create/labels/edges).
- **Dispatch claims the bead** (`--claim` + agent id + lane label); the brief
  carries the bead identity block.
- **Merge + deploy flip labels** (session closes the bead at deploy with
  `iqa:awaiting-validation`; only the session flips to `iqa:validated:<date>`,
  only on the user's explicit words).
- **Ready is a session-side read.** Workers never consume the queue directly.
- **Briefs carry the bead identity block** (epic id, bead id, edge list) so the
  worker's report can name the exact bead without touching `bd`.
- **Overflow queues as unclaimed beads** (tracker `open/queued` with blocker
  named + unclaimed open beads until a lane frees).
- **Three phases, three different agents (dispatcher mode).** Recon plans,
  code implements the recon plan, review re-proves against acceptance — the
  reviewer is never the author. The session gates each handoff and merges /
  deploys / closes only on review ACCEPT.
- **Visible proof is part of acceptance.** Review checks route + renders +
  gone in a browser (signed-in where auth-gated); green suites alone never
  close a UI bead.
- **Awaiting means deployed.** `iqa:awaiting-validation` asserts the merge is
  inside the deployed artifact, proven by the reviewer — not merely on trunk.
