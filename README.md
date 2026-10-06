# IQA-Beads — Interactive QA with Beads

**Live, conversational user-acceptance testing on a dependency-aware issue
graph.** A standalone plugin that turns stock `bd` (Beads) into a disciplined
UAT workflow. `bd` itself is consumed as an upstream release binary — this
repo vendors no `bd` core.

> Previously a full fork of `gastownhall/beads`; slimmed to plugin-only on
> 2026-10-06 (full pre-slim history is retained in git). Provenance:
> [`FORK.yaml`](FORK.yaml).

**Platforms:** macOS, Linux, Windows, FreeBSD

[![License](https://img.shields.io/github/license/victorsalmon/IQA-beads)](LICENSE)
[![npm version](https://img.shields.io/npm/v/@beads/bd)](https://www.npmjs.com/package/@beads/bd)

## Layout (one central skills dir)

```
.
├── .claude-plugin/plugin.json + marketplace.json
├── README.md                    # this file
├── assets/no-approvals.json     # unattended-worker approvals config
├── install-iqa-beads.ps1        # Windows installer / verifier
├── scripts/
│   ├── install-iqa-beads.sh     # macOS/Linux installer / verifier
│   ├── Resolve-Iqa2Bd.ps1       # locate the bd CLI (never mutates PATH)
│   ├── Use-Iqa2DbLock.ps1       # per-database OS-mutex single-writer lock
│   ├── Invoke-Iqa2BeadsInit.ps1 # embedded session DB + session epic
│   ├── Get-Iqa2Ready.ps1        # computed ready queue (+ tracker fallback)
│   └── Export-Iqa2Beads.ps1     # graph → tracker tally + log fragment
└── skills/                      # the runbooks (this is the central store)
    ├── iqa-beads/SKILL.md (+ REFERENCE.md)  # live session core
    ├── adapter-template/SKILL.md             # 5-slot repo adapter worksheet
    ├── maintain/SKILL.md                     # Close Step 1 (drift groom)
    ├── qa/SKILL.md                           # Close Step 2 (pipeline audit)
    ├── nightly-stryker/SKILL.md              # Close Step 3 (mutation)
    └── scheduling/SKILL.md                   # nightly live-list + gate
```

## 📦 Install

```powershell
# Windows (PowerShell 7)
irm https://raw.githubusercontent.com/victorsalmon/IQA-beads/main/install-iqa-beads.ps1 | iex
```

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/victorsalmon/IQA-beads/main/scripts/install-iqa-beads.sh | bash
```

The installer (1) ensures `bd ≥ 0.60.0` via brew/npm (never auto-installs
Go), (2) clones or fast-forward-updates this repo to `~/.iqa-beads`
(`-Dest` / `--dest` overrides; run from a checkout to use it in place),
(3) verifies all 6 runbooks + REFERENCE + 5 helpers + marketplace
registration, and (4) prints harness-wiring next steps. Dry run:
`install-iqa-beads.ps1 -VerifyOnly` / `install-iqa-beads.sh --verify-only`.
Touches no secrets and never mutates PATH.

## ⚡ Five-minute session

1. Fill one adapter worksheet
   (`skills/adapter-template/SKILL.md`) for the target repo.
2. In the target repo: `bd init --stealth` (embedded session DB, no commits).
3. Say **"IQA-Beads"** (legacy alias **"IQA2"**) — blocker check, tracker +
   graph, live capture/triage.
4. Say **"Close"** — export → `maintain` → `qa` → one queued
   `nightly-stryker` task → roll the list (`2A` → `2B`).

## Why this exists

`bd` (Beads) is an excellent persistent issue graph for coding agents — but
it is a tracker, not a testing discipline. It does not know what a UAT
session is, what "awaiting user validation" means, or how to keep a human
tester unblocked while agents fix things in the background. **IQA-Beads**
adds that workflow:

- **A live session that never blocks the user** — capture each report in
  under a minute, dispatch detached workers for fixes, merge + deploy from
  the session, ping `REDEPLOYED` per fix.
- **User status separated from worker status** — Beads `closed` means work
  shipped; validation lives in labels (`iqa:awaiting-validation` →
  `iqa:validated:<date>`) and flips only on the tester's explicit words.
- **Single-writer guardrails** — embedded session DB, OS-mutex
  serialization, workers never run `bd`, export-first close with a tracker
  fallback if the binary is ever dropped.
- **Close-out runbooks** — `maintain` → `qa` → `nightly-stryker` →
  `scheduling`, plus an `adapter-template` worksheet so any repo can adopt
  it.

## Attribution

- **Upstream:** [Beads](https://github.com/gastownhall/beads) by
  [Steve Yegge](https://github.com/steveyegge) and contributors —
  "a memory upgrade for your coding agent" (MIT). `bd` is consumed here
  purely as an upstream release binary (`npm install -g @beads/bd`,
  `brew install beads`); nothing of upstream is vendored. `bd` core bugs
  belong upstream — please file them at
  [gastownhall/beads](https://github.com/gastownhall/beads/issues).
  IQA-Beads plugin, installer, and README issues belong here.
- **This repo** is unofficial and community-maintained — not affiliated
  with or endorsed by upstream. Maintainer:
  [Victor Salmon](https://github.com/victorsalmon).
  Machine-readable provenance: [`FORK.yaml`](FORK.yaml).
