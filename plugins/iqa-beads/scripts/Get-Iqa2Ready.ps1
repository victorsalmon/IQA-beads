#requires -Version 7
<#
.SYNOPSIS
    Compute the IQA2 ready queue — from the Beads graph, or from the markdown
    tracker when the binary is dropped (semantics-only fallback).
.DESCRIPTION
    Default mode runs `bd ready --json` (open, unblocked, non-deferred —
    Beads-native) then applies the IQA2 ordering: severity Blocker → Major →
    Minor, user-block (1–99) before agent-block (100+), then Beads priority.
    Optionally filters to one IQA2 list (e.g. -List 2A).
    Fallback mode (-TrackerFile) parses the `*-iqa2-test-tracker.md` table
    instead: rows with status `open` and no unresolved named blocker, same
    ordering. This is the documented kill-criteria fallback — same command,
    same output shape, no binary required.
    Read-only in both modes: never claims, closes, or labels anything.
    Every invocation serializes on the per-database lock (Use-Iqa2DbLock).
.PARAMETER Workdir
    Session worktree owning the `.beads/` database (or any dir inside it).
.PARAMETER List
    Optional IQA2 list filter, e.g. '2A' (matches label iqa:list=2A, or the
    ID prefix in fallback mode).
.PARAMETER Json
    Emit the ordered queue as JSON instead of grouped text.
.PARAMETER TrackerFile
    Semantics-only fallback: path to the `*-iqa2-test-tracker.md` file.
    Requires the machine-readable columns (ID, severity, status; see
    REFERENCE.md → Phase 1 tracker contract). Ignores -Workdir's database.
.EXAMPLE
    pwsh Get-Iqa2Ready.ps1 -Workdir 'C:\Repos\currents-bookkeeping\.worktrees\dev'
.EXAMPLE
    pwsh Get-Iqa2Ready.ps1 -TrackerFile "$env:SALMON_RUN_HOME/Tasks/00Handoff/2026-09-28-cbk-iqa2-test-tracker.md"
#>
[CmdletBinding()]
param(
    [string]$Workdir = '',
    [string]$List = '',
    [switch]$Json,
    [string]$TrackerFile = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Resolve-Iqa2Bd.ps1')
. (Join-Path $PSScriptRoot 'Use-Iqa2DbLock.ps1')
$env:BD_DISABLE_METRICS = '1'

function Get-SeverityRank($labels) {
    if ($labels -contains 'severity:blocker') { return 0 }
    if ($labels -contains 'severity:major') { return 1 }
    return 2
}
function Get-ItemNumber($labels) {
    $m = @($labels | Where-Object { $_ -match '^iqa:id=2[A-Z]-(\d+)$' } | Select-Object -First 1)
    if ($m.Count -eq 0) { return [int]::MaxValue }
    return [int][regex]::Match($m[0], '(\d+)$').Groups[1].Value
}
function Format-BeadLine($it) {
    $iid = ($it.labels | Where-Object { $_ -match '^iqa:id=' } | Select-Object -First 1) -replace '^iqa:id=', ''
    # Titles carry the "<ID> — <symptom>" prefix by convention; don't double it.
    if ($iid -and ($it.title -like "$iid*")) { return $it.title }
    if ($iid) { return "$iid — $($it.title)" }
    return $it.title
}

function Get-ReadyFromTracker {
    param([string]$Path, [string]$ListFilter)

    if (-not (Test-Path -LiteralPath $Path)) { throw "Tracker file not found: $Path" }
    $lines = Get-Content -LiteralPath $Path
    $hi = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $cells = @($lines[$i] -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        $joined = ($cells -join ' ').ToLowerInvariant()
        if ($lines[$i] -match '\|' -and $joined -match '\bid\b|\bitem\b' -and $joined -match 'status') { $hi = $i; break }
    }
    if ($hi -lt 0 -or $hi + 1 -ge $lines.Count) {
        throw "No machine-readable table (ID + status columns) in $Path. See REFERENCE.md → Phase 1 tracker contract."
    }
    $headers = @($lines[$hi] -split '\|' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ -ne '' })
    $col = { param($names) foreach ($n in $names) { for ($k = 0; $k -lt $headers.Count; $k++) { if ($headers[$k] -match $n) { return $k } } }; return -1 }
    $cId = &$col @('^id$', '^item')
    $cStatus = &$col @('status')
    $cSev = &$col @('severity')
    $cBlock = &$col @('blocker', 'blocked', 'depends')
    $cTitle = &$col @('symptom', 'title', 'description')
    if ($cId -lt 0 -or $cStatus -lt 0) {
        throw "Tracker table in $Path needs ID and status columns. See REFERENCE.md → Phase 1 tracker contract."
    }
    $rows = [System.Collections.Generic.List[object]]::new()
    for ($i = $hi + 2; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '\|') { break }
        $cells = @($lines[$i] -split '\|' | ForEach-Object { $_.Trim() })
        if ($cells.Count -gt 0 -and $cells[0] -eq '') { $cells = $cells[1..($cells.Count - 1)] }
        if ($cells.Count -gt 0 -and $cells[-1] -eq '') { $cells = $cells[0..($cells.Count - 2)] }
        if ($cells.Count -le [Math]::Max($cId, $cStatus)) { continue }
        $id = ($cells[$cId] -replace '\*', '').Trim()
        if ($id -notmatch '^2[A-Z]-\d+$') { continue }
        if ($ListFilter -and -not ($id -like "$ListFilter-*")) { continue }
        $rows.Add([pscustomobject]@{
                id       = $id
                status   = $cells[$cStatus].Trim().ToLowerInvariant()
                severity = if ($cSev -ge 0 -and $cSev -lt $cells.Count) { $cells[$cSev].Trim().ToLowerInvariant() } else { '' }
                blocker  = if ($cBlock -ge 0 -and $cBlock -lt $cells.Count) { $cells[$cBlock].Trim() } else { '' }
                title    = if ($cTitle -ge 0 -and $cTitle -lt $cells.Count -and $cells[$cTitle].Trim()) { $cells[$cTitle].Trim() } else { $id }
            })
    }
    $byId = @{}
    foreach ($r in $rows) { $byId[$r.id] = $r.status }
    $ready = foreach ($r in $rows) {
        if ($r.status -ne 'open') { continue }
        $blocked = $false
        foreach ($m in [regex]::Matches($r.blocker, '2[A-Z]-\d+')) {
            $bs = $byId[$m.Value]
            if ($bs -and $bs -notin @('validated resolved', 'closed (operator directive)')) { $blocked = $true; break }
        }
        if (-not $blocked) { $r }
    }
    return @($ready | Sort-Object `
        @{ Expression = { switch -Wildcard ($_.severity) { '*blocker*' { 0 } '*major*' { 1 } default { 2 } } } }, `
        @{ Expression = { $n = [int]($_.id -replace '^2[A-Z]-', ''); if ($n -lt 100) { 0 } else { 1 } } }, `
        @{ Expression = { [int]($_.id -replace '^2[A-Z]-', '') } })
}

if ($TrackerFile) {
    $readyRows = Get-ReadyFromTracker -Path $TrackerFile -ListFilter $List
    if ($Json) { $readyRows | ConvertTo-Json -Depth 4; return }
    if ($readyRows.Count -eq 0) {
        'No ready work — every open item is blocked or non-open (tracker fallback).'
        return
    }
    $groups = $readyRows | Group-Object { ($_.id -split '-')[0] }
    foreach ($g in ($groups | Sort-Object Name)) {
        "$($g.Name)-list ($($g.Count)) [tracker fallback]:"
        foreach ($r in $g.Group) {
            $line = if ($r.title -like "$($r.id)*") { $r.title } else { "$($r.id) — $($r.title)" }
            " * $line"
        }
        ''
    }
    return
}

if (-not $Workdir) { throw 'Pass -Workdir (Beads mode) or -TrackerFile (semantics-only fallback).' }

$bd = Resolve-Iqa2Bd
$lockKey = (Resolve-Path -LiteralPath $Workdir).Path
Use-Iqa2DbLock -DbKey $lockKey -ScriptBlock {
    $raw = & $bd -C $Workdir ready --json
    if ($LASTEXITCODE -ne 0) { throw "bd ready failed in $Workdir (exit $LASTEXITCODE)." }
    # `bd ready --json` omits `type`, so the session epic (which deliberately
    # carries no iqa: labels — see Invoke-Iqa2BeadsInit.ps1) is excluded by
    # requiring the `iqa:list=` membership label every session bead carries.
    $items = @($raw | ConvertFrom-Json | Where-Object {
            @($_.labels | Where-Object { $_ -match '^iqa:list=' }).Count -gt 0
        })

    if ($List) {
        $items = @($items | Where-Object { $_.labels -contains "iqa:list=$List" })
    }

    $ordered = @($items | Sort-Object `
        @{ Expression = { Get-SeverityRank $_.labels } }, `
        @{ Expression = { if ((Get-ItemNumber $_.labels) -lt 100) { 0 } else { 1 } } }, `
        @{ Expression = { Get-ItemNumber $_.labels } }, `
        @{ Expression = { [int]$_.priority } })

    if ($Json) {
        $ordered | ConvertTo-Json -Depth 6
        return
    }

    if ($ordered.Count -eq 0) {
        'No ready work — every open item is blocked, claimed, or deferred.'
        return
    }

    $groups = $ordered | Group-Object {
        ($_.labels | Where-Object { $_ -match '^iqa:list=' } | Select-Object -First 1) -replace '^iqa:list=', ''
    }
    foreach ($g in ($groups | Sort-Object Name)) {
        "$($g.Name)-list ($($g.Count)):"
        foreach ($it in $g.Group) { " * $(Format-BeadLine $it)" }
        ''
    }
}
