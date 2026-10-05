#requires -Version 7
<#
.SYNOPSIS
    Initialize the IQA2 Beads database for one session (embedded, local-only).
.DESCRIPTION
    Creates one embedded-mode Beads DB in the session trunk worktree plus the
    session epic (IQA2-<letter>), and records the session file
    `.iqa2-session.json` (lane metadata — never committed).
    Uses `bd init --stealth` so `.beads/` is excluded via .git/info/exclude
    without touching any tracked repo file. Never runs `bd dolt push` — and
    since `bd init` auto-configures the git origin as a Dolt remote when one
    is present, this script strips any auto-configured remotes immediately
    and refuses to proceed while one exists. Refuses to initialize inside an
    existing `.beads/` unless -Reuse is given.
.PARAMETER Workdir
    Session trunk worktree that will own the `.beads/` database.
.PARAMETER ListLetter
    IQA2 list letter for this session (default 'A' → list IQA2-A, items 2A-*).
.PARAMETER Reuse
    Re-verify an existing `.beads/` database instead of failing.
.EXAMPLE
    pwsh Invoke-Iqa2BeadsInit.ps1 -Workdir 'C:\Repos\currents-bookkeeping\.worktrees\dev'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Workdir,
    [string]$ListLetter = 'A',
    [switch]$Reuse
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Resolve-Iqa2Bd.ps1')
. (Join-Path $PSScriptRoot 'Use-Iqa2DbLock.ps1')
$env:BD_DISABLE_METRICS = '1'

$bd = Resolve-Iqa2Bd
if (-not (Test-Path -LiteralPath $Workdir -PathType Container)) {
    throw "Workdir not found: $Workdir"
}
$beadsDir = Join-Path $Workdir '.beads'
$sessionFile = Join-Path $Workdir '.iqa2-session.json'

if ((Test-Path -LiteralPath $beadsDir) -and -not $Reuse) {
    throw "A .beads/ database already exists in $Workdir. Re-run with -Reuse to adopt it."
}

$lockKey = (Resolve-Path -LiteralPath $Workdir).Path
Use-Iqa2DbLock -DbKey $lockKey -ScriptBlock {
if (-not (Test-Path -LiteralPath $beadsDir)) {
    # NOTE: `bd -C <dir>` requires an existing workspace, so init itself must
    # run with the workdir as the process cwd (chicken-and-egg on a fresh dir).
    Push-Location -LiteralPath $Workdir
    try {
        & $bd init --quiet --stealth
        if ($LASTEXITCODE -ne 0) { throw "bd init failed in $Workdir (exit $LASTEXITCODE)." }
    }
    finally { Pop-Location }
}

# No-push hardening: a non-stealth `bd init` can auto-configure the git
# origin as a Dolt remote. Session DBs stay local-only in v1, so strip every
# configured remote now — a later accidental `dolt push` must have nowhere
# to go. Re-check after stripping; any surviving remote is a hard stop.
# (`dolt remote list` prints `No remotes configured.` when empty, else a
# table — skip the notice, header, and separator lines either way.)
$remoteLines = @(& $bd -C $Workdir dolt remote list 2>$null | Where-Object {
    $_ -match '\S' -and $_ -notmatch '(?i)^no remotes' -and $_ -notmatch '^\s*name\b' -and $_ -notmatch '^[-\s]+$'
})
foreach ($line in $remoteLines) {
    $r = ($line -split '\s+')[0]
    & $bd -C $Workdir dolt remote remove $r 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { "Stripped auto-configured Dolt remote: $r" }
}
$leftover = @(& $bd -C $Workdir dolt remote list 2>$null | Where-Object {
    $_ -match '\S' -and $_ -notmatch '(?i)^no remotes' -and $_ -notmatch '^\s*name\b' -and $_ -notmatch '^[-\s]+$'
})
if ($leftover.Count -gt 0) {
    throw "Dolt remotes still configured in $Workdir ($($leftover -join ', ')) — refusing: IQA2 session DBs stay local-only in v1."
}

$statusJson = & $bd -C $Workdir status --json 2>$null
if ($LASTEXITCODE -ne 0) { throw "bd status failed in $Workdir — database unhealthy." }

$bdVersion = (& $bd version 2>$null | Select-Object -First 1).Trim()
$listName = "IQA2-$ListLetter"

if ($Reuse -and (Test-Path -LiteralPath $sessionFile)) {
    $prior = Get-Content -LiteralPath $sessionFile | ConvertFrom-Json
    if ($prior.epic) {
        "Adopted existing session epic $($prior.epic) ($($prior.list)) [$bdVersion]"
        return
    }
}

$epicJson = & $bd -C $Workdir create "$listName session epic" -t epic -p 2 --json
# NOTE: the epic carries NO labels on purpose — children inherit parent
# labels by default, so any epic label would leak onto every item bead.
if ($LASTEXITCODE -ne 0) { throw 'Failed to create the IQA2 session epic.' }
$epicId = ($epicJson | ConvertFrom-Json | Select-Object -First 1).id
if (-not $epicId) { throw 'Epic creation returned no id.' }

[ordered]@{
    tool       = 'iqa-beads'
    list       = $listName
    itemPrefix = "2$ListLetter-"
    epic       = $epicId
    bdVersion  = $bdVersion
    workdir    = $Workdir
    createdAt  = (Get-Date).ToUniversalTime().ToString('o')
} | ConvertTo-Json | Set-Content -LiteralPath $sessionFile -Encoding utf8

"Epic $epicId ($listName) ready in $Workdir [$bdVersion]"
}
