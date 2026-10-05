# IQA-Beads Plugin

Beads-backed **Interactive Quality Assurance** (IQA): run a live, conversational
UAT session against a deployed web product (or local full-stack) where the
tracker is a **dependency-aware Beads issue graph** — not a markdown TODO list.

This plugin is standalone: it builds on the `beads` plugin's `bd` CLI and adds
the session discipline, tracker semantics, and close-out runbooks that make
Beads usable for human-driven testing without blocking the user.

Install via the repo root: `install-iqa-beads.ps1` (Windows) or
`scripts/install-iqa-beads.sh` (macOS/Linux) — see the root README.

## Layout (one central skills dir)

```
plugins/iqa-beads/
├── .claude-plugin/plugin.json   # plugin manifest (skills → ./skills/)
├── README.md                    # this file
├── assets/
│   └── no-approvals.json        # unattended-worker approvals config
├── scripts/                     # deterministic helpers (PowerShell 7)
│   ├── Resolve-Iqa2Bd.ps1       # locate the bd CLI (never mutates PATH)
│   ├── Use-Iqa2DbLock.ps1       # per-database OS-mutex single-writer lock
│   ├── Invoke-Iqa2BeadsInit.ps1 # embedded session DB + session epic
│   ├── Get-Iqa2Ready.ps1         # computed ready queue (+ tracker fallback)
│   └── Export-Iqa2Beads.ps1      # graph → tracker tally + log fragment
└── skills/                      # the runbooks (this is the central store)
    ├── iqa-beads/SKILL.md (+ REFERENCE.md)  # live session core
    ├── adapter-template/SKILL.md             # 5-slot repo adapter worksheet
    ├── maintain/SKILL.md                     # Close Step 1 (drift groom)
    ├── qa/SKILL.md                           # Close Step 2 (pipeline audit)
    ├── nightly-stryker/SKILL.md              # Close Step 3 (mutation)
    └── scheduling/SKILL.md                   # nightly live-list + gate
```

## Skills

| Skill | When | Owns |
|---|---|---|
| `iqa-beads` | User says "IQA-Beads" / "IQA2", or wants a live UAT session | Capture → triage → dual-lane fix → merge/deploys → ping |
| `adapter-template` | Before the first session on a new repo | The 5 repo-specific slots every session needs |
| `maintain` | Session close (or `Catch-up`) | Stale-first groom + drift fixes; testing excluded |
| `qa` | After Maintain, same close | Pipeline-staleness audit + gap tests over the groomed list |
| `nightly-stryker` | Close queue + unattended run | Incremental mutation re-proof, branch-only |
| `scheduling` | Unattended batch nights | Live-list protocol, layered order, fail-closed gate |

## Quickstart

1. Fill one `adapter-template` worksheet for the target repo (deploy target,
   focused/full test commands, secrets profile, QA matrices, branch convention).
2. Start the session per `iqa-beads` Phase 0–1 (blocker analysis, tracker +
   Beads graph).
3. Run the live session (Phase 2): capture verbatim, dispatch detached workers,
   merge + deploy from the session, ping `REDEPLOYED` per fix.
4. Close the session: `maintain` → `qa` → queue `nightly-stryker` via
   `scheduling`. Roll the list.

## Requirements

- `bd` CLI in PATH (the `beads` plugin's install path; `scripts/` falls back
  to well-known shim locations on Windows and fails with an actionable message).
- PowerShell 7 for `scripts/` (POSIX-shell ports are a known gap — see
  `skills/iqa-beads/REFERENCE.md` → `## Beads lifecycle`).
- A repo adapter worksheet (`skills/adapter-template`) per target repo.

## Versioning

`0.1.0` — initial extraction: session core + adapter + Maintain/QA/nightly/
scheduling runbooks + 5 helpers. The `iqa:` label taxonomy and `2X-` ID
namespace are stable; script flags are stable; skill prose may tighten.
