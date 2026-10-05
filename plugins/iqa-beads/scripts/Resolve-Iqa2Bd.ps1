#requires -Version 7
<#
.SYNOPSIS
    Resolve the bd (Beads) CLI for IQA2 scripts.
.DESCRIPTION
    Shared resolver: prefers `bd` on PATH, then the well-known npm-global
    shim locations on this Windows box. Never mutates PATH; callers fail
    with an actionable message when bd is missing.
#>
function Resolve-Iqa2Bd {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $cmd = Get-Command 'bd' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        (Join-Path ${env:LOCALAPPDATA} 'npm-global\bd.cmd'),
        (Join-Path ${env:APPDATA} 'npm\bd.cmd'),
        (Join-Path ${env:ProgramFiles} 'beads\bd.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    throw 'bd CLI not found. Install it (npm install -g @beads/bd) or add it to PATH, then retry.'
}
