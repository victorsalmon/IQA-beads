# IQA-Beads — Interactive QA with Beads

**Live, conversational user-acceptance testing on a dependency-aware issue
graph.** This fork is Beads plus a standalone plugin that turns it into a
disciplined UAT workflow.

**Platforms:** macOS, Linux, Windows, FreeBSD

[![License](https://img.shields.io/github/license/victorsalmon/IQA-beads)](LICENSE)
[![Go Report Card](https://goreportcard.com/badge/github.com/gastownhall/beads)](https://goreportcard.com/report/github.com/gastownhall/beads)
[![npm version](https://img.shields.io/npm/v/@beads/bd)](https://www.npmjs.com/package/@beads/bd)
[![PyPI](https://img.shields.io/pypi/v/beads-mcp)](https://pypi.org/project/beads-mcp/)

## Foreword: why this fork exists

`bd` (Beads) is an excellent persistent issue graph for coding agents — but it
is a tracker, not a testing discipline. It does not know what a UAT session
is, what "awaiting user validation" means, or how to keep a human tester
unblocked while agents fix things in the background.

**IQA-Beads** adds that workflow as a standalone plugin in
[`plugins/iqa-beads/`](plugins/iqa-beads/) (runbook source:
[`plugins/iqa-beads/skills/`](plugins/iqa-beads/skills/), registered in
[`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json)
alongside `beads`). It works with a stock `bd` binary — no fork-specific
patches required. What it contributes over raw Beads:

- **A live session that never blocks the user** — capture each report in under
  a minute, dispatch detached workers for fixes, merge + deploy from the
  session, ping `REDEPLOYED` per fix. Full rigor moves to later passes, never
  onto the tester's critical path.
- **User status separated from worker status** — Beads `closed` means work
  shipped; validation lives in labels (`iqa:awaiting-validation` →
  `iqa:validated:<date>`) and flips only on the tester's explicit words.
- **Single-writer guardrails** — embedded session DB, OS-mutex serialization,
  workers never run `bd`, export-first close with a tracker fallback if the
  binary is ever dropped.
- **Close-out runbooks** — `maintain` (drift groom, testing excluded) →
  `qa` (pipeline audit over exactly the groomed list) → `nightly-stryker`
  (incremental mutation re-proof) → `scheduling` (live-list + fail-closed
  gate), plus an `adapter-template` worksheet so any repo can adopt it.

Say **"IQA-Beads"** (legacy alias **"IQA2"**) to start a session. Full runbook:
[`plugins/iqa-beads/README.md`](plugins/iqa-beads/README.md).

## 📦 Install

```powershell
# Windows (PowerShell 7)
irm https://raw.githubusercontent.com/victorsalmon/IQA-beads/main/install-iqa-beads.ps1 | iex
```

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/victorsalmon/IQA-beads/main/scripts/install-iqa-beads.sh | bash
```

The installer (1) ensures `bd ≥ 0.60.0` (delegates to this repo's
`install.ps1` / `scripts/install.sh`, else brew/npm — never auto-installs
Go), (2) clones or fast-forward-updates this fork to `~/.iqa-beads`
(`-Dest` / `--dest` overrides; run from a checkout to use it in place),
(3) verifies all 6 runbooks + 5 helpers + marketplace registration, and
(4) prints harness-wiring next steps. Dry run:
`install-iqa-beads.ps1 -VerifyOnly` / `install-iqa-beads.sh --verify-only`.
Touches no secrets and never mutates PATH.

Manual alternative: install `bd` per [Beads in brief](#-beads-upstream-in-brief),
clone this repo, read the adapter worksheet.

## ⚡ Five-minute session

1. Fill one adapter worksheet
   (`plugins/iqa-beads/skills/adapter-template/SKILL.md`) for the target repo.
2. In the target repo: `bd init --stealth` (embedded session DB, no commits).
3. Say **"IQA-Beads"** — blocker check, tracker + graph, live capture/triage.
4. Say **"Close"** — export → `maintain` → `qa` → one queued
   `nightly-stryker` task → roll the list (`2A` → `2B`).

## 🔩 Beads (upstream) in brief

Beads is a **distributed graph issue tracker for AI agents, powered by
[Dolt](https://github.com/dolthub/dolt)** — persistent, structured memory that
replaces markdown plans with a dependency-aware graph so agents survive
long-horizon work and conversation compaction.

| Command | Action |
| --- | --- |
| `bd ready` | List tasks with no open blockers. |
| `bd create "Title" -p 0` | Create a P0 task. |
| `bd update <id> --claim` | Atomically claim a task (assignee + in_progress). |
| `bd dep add <child> <parent>` | Link tasks (blocks, related, parent-child). |
| `bd show <id>` | View task details and audit trail. |
| `bd prime` | Agent workflow context + persistent memories. |
| `bd remember "insight"` | Store project memory that `bd prime` injects later. |

- **Cycle:** `create` → `ready` → `--claim` → `close` → blockers release → `ready`.
- **Storage:** embedded Dolt by default (`.beads/`, single writer); server mode
  for concurrent writers; cross-machine sync via `bd dolt push/pull`.
- **Agent setup:** `bd setup codex|claude|factory|…`, or run `bd onboard` and
  paste the snippet for unsupported agents.

> **Full upstream reference** — the complete Beads README, commands, storage
> modes, schema guard, and git-free usage live at the original repository:
> **[gastownhall/beads README](https://github.com/gastownhall/beads#readme)**.
> Docs site: [beads.gascity.com](https://beads.gascity.com/). Everything below
> the line in this file is a pointer, not a copy — upstream stays canonical.

## 📝 Pointers

- IQA-Beads runbooks: [`plugins/iqa-beads/`](plugins/iqa-beads/)
- Upstream README: [gastownhall/beads](https://github.com/gastownhall/beads#readme)
- Upstream install guide:
  [`docs/getting-started/installation.md`](docs/getting-started/installation.md) |
  Agent workflow: [`AGENT_INSTRUCTIONS.md`](AGENT_INSTRUCTIONS.md) |
  Troubleshooting: [`docs/reference/troubleshooting.md`](docs/reference/troubleshooting.md)
- Contributing to the `bd` core: [`CONTRIBUTING.md`](CONTRIBUTING.md);
  IQA-Beads plugin changes are welcome here on this fork.
