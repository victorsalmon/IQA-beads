#requires -Version 7
<#
.SYNOPSIS
    Serialize IQA2 Beads access per database (single-writer enforcement).
.DESCRIPTION
    IQA2 runs embedded-mode Beads (single writer). Only the interactive
    session may mutate the graph, but concurrent script invocations from
    lanes could still race. This helper serializes every IQA2 script
    invocation holding the same database behind a named OS mutex keyed by
    the SHA1 of the normalized database path (Global namespace, Local
    fallback). Abandoned locks (crashed holder) are adopted, not feared:
    the new holder owns the mutex and proceeds. On timeout the invocation
    fails with an actionable message instead of racing the database.
.EXAMPLE
    . (Join-Path $PSScriptRoot 'Use-Iqa2DbLock.ps1')
    Use-Iqa2DbLock -DbKey $lockKey -ScriptBlock { & $bd -C $Workdir ready --json }
#>
function Use-Iqa2DbLock {
    [CmdletBinding()]
    param(
        # NOTE: this parameter is deliberately NOT named $BeadsDir —
        # PowerShell variables are case-insensitive, and callers use
        # $beadsDir for the database path. A $BeadsDir parameter would
        # shadow it inside the invoked scriptblock and silently break
        # path tests (observed: init branch skipped, status failed).
        [Parameter(Mandatory)]
        [string]$DbKey,
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        [int]$TimeoutSec = 120
    )

    $norm = $DbKey.TrimEnd('\', '/').ToLowerInvariant()
    $digest = [BitConverter]::ToString(
        [Security.Cryptography.SHA1]::Create().ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($norm))) -replace '-', ''

    $mutex = $null
    foreach ($ns in @('Global', 'Local')) {
        try { $mutex = [Threading.Mutex]::new($false, "$ns\IQA2_$digest"); break }
        catch { $mutex = $null }
    }
    if (-not $mutex) { throw "Could not create the IQA2 DB lock for $DbKey." }

    try {
        $acquired = $false
        try { $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSec)) }
        catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) {
            throw "Timed out waiting ${TimeoutSec}s for the IQA2 DB lock on $DbKey. " +
                'Another writer holds it — lanes must never run bd concurrently; only the session mutates the graph.'
        }
        try { & $ScriptBlock }
        finally { $mutex.ReleaseMutex() }
    }
    finally { $mutex.Dispose() }
}
