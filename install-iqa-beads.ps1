# IQA-Beads installer (Windows / PowerShell 7)
# Usage (remote):
#   irm https://raw.githubusercontent.com/victorsalmon/IQA-beads/main/install-iqa-beads.ps1 | iex
# Usage (local checkout):
#   pwsh ./install-iqa-beads.ps1 [-Dest ~/.iqa-beads] [-Branch main] [-SkipBd] [-FromSource] [-VerifyOnly]
#
# What it does:
#   1. Ensures the `bd` CLI is installed (delegates to this repo's install.ps1,
#      else npm, else fails with manual instructions — never auto-installs Go).
#   2. Clones (or fast-forward-updates) this fork to -Dest (default ~/.iqa-beads).
#      When run from inside a fork checkout, that checkout IS the source (no clone).
#   3. Verifies: bd version floor, all 6 runbooks + REFERENCE + 5 helpers present,
#      marketplace registration names iqa-beads.
#   4. Prints harness-wiring next steps. Touches no secrets, no PATH mutation.

#requires -Version 7

[CmdletBinding()]
param(
    [string]$Dest = (Join-Path $HOME '.iqa-beads'),
    [string]$Branch = 'main',
    [switch]$SkipBd,
    [switch]$FromSource,
    [switch]$VerifyOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:RepoUrl = 'https://github.com/victorsalmon/IQA-beads'
$Script:MinBd = [version]'0.60.0'
$Script:Failures = 0

function Write-Step($Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok($Message)   { Write-Host "    ok: $Message" -ForegroundColor Green }
function Write-Bad($Message)  { Write-Host "    MISSING: $Message" -ForegroundColor Red; $Script:Failures++ }

function Get-BdVersion {
    # PATH first (the running bd), then well-known install locations — a fresh
    # install lands on disk before any shell picks it up on PATH (PATH freeze),
    # so PATH-only probing reports a healthy install as missing.
    $cands = @()
    $cmd = Get-Command 'bd' -ErrorAction SilentlyContinue
    if ($cmd) { $cands += $cmd.Source }
    $cands += @(
        (Join-Path ${env:LOCALAPPDATA} 'Programs\bd\bd.exe'),
        (Join-Path ${env:LOCALAPPDATA} 'npm-global\bd.cmd'),
        (Join-Path ${env:APPDATA} 'npm\bd.cmd'),
        (Join-Path ${env:ProgramFiles} 'beads\bd.exe')
    )
    foreach ($c in $cands) {
        if (-not $c -or -not (Test-Path -LiteralPath $c)) { continue }
        $out = (& $c version 2>$null | Select-Object -First 1)
        $m = [regex]::Match("$out", '(?<v>\d+\.\d+\.\d+)')
        if ($m.Success) { return [pscustomobject]@{ Path = $c; Version = [version]$m.Groups['v'].Value } }
    }
    return $null
}

function Test-Checkout($Dir) {
    return ($Dir -and (Test-Path -LiteralPath (Join-Path $Dir 'plugins/iqa-beads/skills/iqa-beads/SKILL.md')))
}

function Ensure-Bd($RepoRoot) {
    $bd = Get-BdVersion
    if ($bd -and $bd.Version -and $bd.Version -ge $Script:MinBd) {
        Write-Ok "bd $($bd.Version) at $($bd.Path)"
        return
    }
    if ($bd) { Write-Step "bd $($bd.Version) is below floor $($Script:MinBd) — upgrading" }
    elseif ($SkipBd) { Write-Bad 'bd not found and -SkipBd was passed (refusing to continue without bd)'; return }
    if ($VerifyOnly) { Write-Bad 'bd not found (verify-only)'; return }

    if ($FromSource) {
        if (-not (Test-Checkout $RepoRoot)) { throw '-FromSource needs a fork checkout (clone first, or run from inside one).' }
        if (-not (Get-Command 'go' -ErrorAction SilentlyContinue)) { throw 'Go 1.24+ is required for -FromSource and was not found.' }
        Write-Step 'Building bd from fork source...'
        Push-Location -LiteralPath $RepoRoot
        try { & go build -o (Join-Path $HOME 'go/bin/bd.exe') ./cmd/bd } finally { Pop-Location }
    } elseif (Test-Checkout $RepoRoot) {
        Write-Step 'Installing bd via this repo install.ps1 (release + checksum, go fallback)...'
        & (Join-Path $RepoRoot 'install.ps1')
    } elseif (Get-Command 'npm' -ErrorAction SilentlyContinue) {
        Write-Step 'Installing bd via npm (@beads/bd)...'
        & npm install -g '@beads/bd'
    } else {
        throw 'bd not found. Install it first: npm install -g @beads/bd, or run this installer from inside a fork checkout (delegates to install.ps1).'
    }
    $bd = Get-BdVersion
    if (-not $bd) { throw 'bd install did not land anywhere expected. Restart the shell (PATH freeze) and re-run with -SkipBd.' }
    Write-Ok "bd $($bd.Version) at $($bd.Path)"
    if (-not (Get-Command 'bd' -ErrorAction SilentlyContinue)) {
        Write-Warning "bd is on disk but not on this shell's PATH yet — restart the shell (or add $(Split-Path $bd.Path) to PATH) so later shells resolve it."
    }
}

function Sync-Plugin($RepoRoot) {
    if (Test-Checkout $RepoRoot) {
        Write-Ok "using current checkout as plugin source: $RepoRoot"
        return $RepoRoot
    }
    if ($VerifyOnly) { Write-Bad "plugin destination not ready: $Dest"; return $Dest }
    if (-not (Get-Command 'git' -ErrorAction SilentlyContinue)) { throw 'git is required to fetch the plugin and was not found.' }
    if (Test-Path -LiteralPath (Join-Path $Dest '.git')) {
        Write-Step "Updating plugin checkout at $Dest (fast-forward only)..."
        $dirty = git -C $Dest status --porcelain
        if ($dirty) { throw "Refusing: $Dest has uncommitted changes. Commit or stash them first." }
        git -C $Dest fetch origin | Out-Null
        git -C $Dest checkout $Branch | Out-Null
        git -C $Dest pull --ff-only origin $Branch | Out-Null
    } else {
        Write-Step "Cloning fork ($Branch) to $Dest..."
        git clone --branch $Branch "$Script:RepoUrl" $Dest | Out-Null
    }
    return $Dest
}

function Verify-Plugin($Root) {
    $expected = @(
        'plugins/iqa-beads/skills/iqa-beads/SKILL.md',
        'plugins/iqa-beads/skills/iqa-beads/REFERENCE.md',
        'plugins/iqa-beads/skills/adapter-template/SKILL.md',
        'plugins/iqa-beads/skills/maintain/SKILL.md',
        'plugins/iqa-beads/skills/qa/SKILL.md',
        'plugins/iqa-beads/skills/nightly-stryker/SKILL.md',
        'plugins/iqa-beads/skills/scheduling/SKILL.md',
        'plugins/iqa-beads/scripts/Resolve-Iqa2Bd.ps1',
        'plugins/iqa-beads/scripts/Use-Iqa2DbLock.ps1',
        'plugins/iqa-beads/scripts/Invoke-Iqa2BeadsInit.ps1',
        'plugins/iqa-beads/scripts/Get-Iqa2Ready.ps1',
        'plugins/iqa-beads/scripts/Export-Iqa2Beads.ps1',
        'plugins/iqa-beads/.claude-plugin/plugin.json',
        '.claude-plugin/marketplace.json'
    )
    foreach ($rel in $expected) {
        $p = Join-Path $Root ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $p) { Write-Ok $rel } else { Write-Bad $rel }
    }
    $mp = Get-Content -LiteralPath (Join-Path $Root '.claude-plugin/marketplace.json') -Raw | ConvertFrom-Json
    if (@($mp.plugins | Where-Object { $_.name -eq 'iqa-beads' }).Count -eq 1) { Write-Ok 'marketplace registers iqa-beads' }
    else { Write-Bad 'marketplace registration for iqa-beads' }
}

$here = $PSScriptRoot
if (-not $VerifyOnly) { Write-Step "IQA-Beads install → $Dest" }
Ensure-Bd -RepoRoot $here
$root = Sync-Plugin -RepoRoot $here
Write-Step 'Verifying plugin files...'
Verify-Plugin -Root $root

if ($Script:Failures -gt 0) { throw "Verification failed with $($Script:Failures) missing item(s)." }
Write-Host ''
Write-Host 'Done. Next steps:' -ForegroundColor Green
Write-Host "  1. Fill one adapter worksheet: $root/plugins/iqa-beads/skills/adapter-template/SKILL.md"
Write-Host '  2. In the target repo: bd init --stealth  (embedded session DB, no commits)'
Write-Host '  3. Claude Code: /plugin marketplace add <dest>  (dest = the path above)'
Write-Host '  4. Other harnesses: point a skill pointer at <dest>/plugins/iqa-beads/skills/<skill>/SKILL.md'
Write-Host '  5. Say "IQA-Beads" to start a live UAT session.'
