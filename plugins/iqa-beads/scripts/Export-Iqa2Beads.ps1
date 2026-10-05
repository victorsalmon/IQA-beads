#requires -Version 7
<#
.SYNOPSIS
    Export the IQA2 Beads graph into the tracker tally + session-log fragment.
.DESCRIPTION
    Read-only against Beads (`bd list --all --json`); writes only the -OutFile
    markdown fragment: per-list counts (open / awaiting validation / validated /
    deferred / operator-closed) plus one bullet per non-epic bead with its IQA2
    id, user status (derived from labels), title, and beads-id. The session
    reconciles this export against the markdown tracker before Maintain runs
    (log wins on user status, graph wins on edges/refs) — the script itself
    reconciles nothing.
.PARAMETER Workdir
    Session worktree owning the `.beads/` database (or any dir inside it).
.PARAMETER OutFile
    Destination markdown fragment path.
.PARAMETER List
    Optional IQA2 list filter, e.g. '2A'.
.EXAMPLE
    pwsh Export-Iqa2Beads.ps1 -Workdir <worktree> -OutFile "$env:SALMON_RUN_HOME/Tasks/00Handoff/<date>-<repo>-iqa2-beads-export.md"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Workdir,
    [Parameter(Mandatory)]
    [string]$OutFile,
    [string]$List = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Resolve-Iqa2Bd.ps1')
. (Join-Path $PSScriptRoot 'Use-Iqa2DbLock.ps1')
$env:BD_DISABLE_METRICS = '1'

$bd = Resolve-Iqa2Bd
$lockKey = (Resolve-Path -LiteralPath $Workdir).Path
Use-Iqa2DbLock -DbKey $lockKey -ScriptBlock {
$raw = & $bd -C $Workdir list --all --json
if ($LASTEXITCODE -ne 0) { throw "bd list failed in $Workdir (exit $LASTEXITCODE)." }
$items = @($raw | ConvertFrom-Json | Where-Object {
    ($_.type -ne 'epic') -and
    (@($_.labels | Where-Object { $_ -match '^iqa:list=' }).Count -gt 0)
})

if ($List) {
    $items = @($items | Where-Object { $_.labels -contains "iqa:list=$List" })
}

function Get-UserStatus($it) {
    if ($it.labels -contains 'iqa:awaiting-validation') { return 'fix live, awaiting validation' }
    if (@($it.labels | Where-Object { $_ -match '^iqa:validated:' }).Count -gt 0) { return 'validated resolved' }
    if (@($it.labels | Where-Object { $_ -match '^iqa:deferred' }).Count -gt 0) { return 'deferred' }
    if (@($it.labels | Where-Object { $_ -match '^iqa:operator-closed' }).Count -gt 0) { return 'closed (operator directive)' }
    return 'open'
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# IQA2 Beads export')
$lines.Add('')
$lines.Add("Exported: $((Get-Date).ToUniversalTime().ToString('o')) | beads: $($items.Count)")

$groups = $items | Group-Object {
    ($_.labels | Where-Object { $_ -match '^iqa:list=' } | Select-Object -First 1) -replace '^iqa:list=', ''
}
foreach ($g in ($groups | Sort-Object Name)) {
    $name = if ($g.Name) { $g.Name } else { '(unlabeled)' }
    $counts = $g.Group | Group-Object { Get-UserStatus $_ }
    $tally = ($counts | Sort-Object Name | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ' · '
    $lines.Add('')
    $lines.Add("## $name-list ($($g.Group.Count)) — $tally")
    foreach ($it in ($g.Group | Sort-Object id)) {
        $iid = ($it.labels | Where-Object { $_ -match '^iqa:id=' } | Select-Object -First 1) -replace '^iqa:id=', ''
        if (-not $iid) { $iid = $it.id }
        $lines.Add("* $iid — [$((Get-UserStatus $it))] $($it.title) [beads: $($it.id)]")
    }
}

$parent = Split-Path -Parent $OutFile
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent | Out-Null
}
$lines | Set-Content -LiteralPath $OutFile -Encoding utf8
"Exported $($items.Count) beads to $OutFile"
}
