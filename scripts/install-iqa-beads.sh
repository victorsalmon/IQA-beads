#!/usr/bin/env bash
#
# IQA-Beads installer (macOS / Linux)
# Usage (remote):
#   curl -fsSL https://raw.githubusercontent.com/victorsalmon/IQA-beads/main/scripts/install-iqa-beads.sh | bash
#   curl -fsSL ... | bash -s -- --dest ~/.iqa-beads --verify-only
#
# IMPORTANT: This script must be EXECUTED, never SOURCED.
#
# What it does:
#   1. Ensures the `bd` CLI is installed (upstream release via brew/npm —
#      this repo vendors no bd core and never auto-installs Go).
#   2. Clones (or fast-forward-updates) this repo to --dest (default ~/.iqa-beads).
#      When run from inside a repo checkout, that checkout IS the source.
#   3. Verifies: bd version floor, all runbooks + helpers present, marketplace
#      registration names iqa-beads.
#   4. Prints harness-wiring next steps. Touches no secrets, no PATH mutation.

set -euo pipefail

REPO_URL="https://github.com/victorsalmon/IQA-beads"
MIN_BD="0.60.0"
DEST="${HOME}/.iqa-beads"
BRANCH="main"
SKIP_BD=0
VERIFY_ONLY=0
FAILURES=0

log_info()    { echo -e "\033[0;34m==>\033[0m $1" >&2; }
log_ok()      { echo -e "    \033[0;32mok:\033[0m $1" >&2; }
log_missing() { echo -e "    \033[0;31mMISSING:\033[0m $1" >&2; FAILURES=$((FAILURES + 1)); }
die()         { echo -e "\033[0;31mError:\033[0m $1" >&2; exit 1; }

usage() {
    echo "Usage: install-iqa-beads.sh [--dest DIR] [--branch NAME] [--skip-bd] [--verify-only]"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dest)        DEST="$2"; shift 2 ;;
        --branch)      BRANCH="$2"; shift 2 ;;
        --skip-bd)     SKIP_BD=1; shift ;;
        --verify-only) VERIFY_ONLY=1; shift ;;
        -h|--help)     usage; exit 0 ;;
        *)             die "Unknown flag: $1 (see --help)" ;;
    esac
done

ver_ge() { # ver_ge HAVE NEED → true if HAVE >= NEED
    [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

is_checkout() { [ -f "$1/skills/iqa-beads/SKILL.md" ]; }

resolve_bd() {
    # PATH first, then well-known locations: a fresh install lands on disk
    # before any shell picks it up on PATH (PATH freeze).
    command -v bd 2>/dev/null && return 0
    local shim
    for shim in "${HOME}/.local/bin/bd" "/usr/local/bin/bd" "/opt/homebrew/bin/bd"; do
        if [ -x "${shim}" ]; then echo "${shim}"; return 0; fi
    done
    return 1
}

bd_version_of() { "$1" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true; }

ensure_bd() {
    local root="$1" bin="" have=""
    bin="$(resolve_bd || true)"
    if [ -n "${bin}" ]; then
        have="$(bd_version_of "${bin}")"
        if [ -n "${have}" ] && ver_ge "${have}" "${MIN_BD}"; then
            log_ok "bd ${have} at ${bin}"
            return 0
        fi
    fi
    if [ "${SKIP_BD}" = "1" ]; then
        log_missing "bd not found (and --skip-bd was passed)"
        return 0
    fi
    if [ "${VERIFY_ONLY}" = "1" ]; then
        log_missing "bd not found (verify-only)"
        return 0
    fi
    if command -v brew >/dev/null 2>&1; then
        log_info "Installing bd via Homebrew..."
        brew install beads
    elif command -v npm >/dev/null 2>&1; then
        log_info "Installing bd via npm (@beads/bd)..."
        npm install -g "@beads/bd"
    else
        die "bd not found. Install it first: brew install beads or npm install -g @beads/bd."
    fi
    bin="$(resolve_bd || true)"
    [ -n "${bin}" ] || die "bd install did not land anywhere expected. Restart the shell and re-run with --skip-bd."
    log_ok "bd $(bd_version_of "${bin}") at ${bin}"
    if ! command -v bd >/dev/null 2>&1; then
        log_info "NOTE: bd is on disk but not on this shell's PATH yet — restart the shell so later shells resolve it."
    fi
}

sync_plugin() {
    local root="$1"
    if is_checkout "${root}"; then
        log_ok "using current checkout as plugin source: ${root}"
        echo "${root}"
        return 0
    fi
    if [ "${VERIFY_ONLY}" = "1" ]; then
        log_missing "plugin destination not ready: ${DEST}"
        echo "${DEST}"
        return 0
    fi
    command -v git >/dev/null 2>&1 || die "git is required to fetch the plugin and was not found."
    if [ -d "${DEST}/.git" ]; then
        log_info "Updating plugin checkout at ${DEST} (fast-forward only)..."
        [ -z "$(git -C "${DEST}" status --porcelain)" ] || die "Refusing: ${DEST} has uncommitted changes."
        git -C "${DEST}" fetch origin >/dev/null
        git -C "${DEST}" checkout "${BRANCH}" >/dev/null
        git -C "${DEST}" pull --ff-only origin "${BRANCH}" >/dev/null
    else
        log_info "Cloning plugin repo (${BRANCH}) to ${DEST}..."
        git clone --branch "${BRANCH}" "${REPO_URL}" "${DEST}" >/dev/null
    fi
    echo "${DEST}"
}

verify_plugin() {
    local root="$1" rel
    for rel in \
        "skills/iqa-beads/SKILL.md" \
        "skills/iqa-beads/REFERENCE.md" \
        "skills/adapter-template/SKILL.md" \
        "skills/maintain/SKILL.md" \
        "skills/qa/SKILL.md" \
        "skills/nightly-stryker/SKILL.md" \
        "skills/scheduling/SKILL.md" \
        "scripts/Resolve-Iqa2Bd.ps1" \
        "scripts/Use-Iqa2DbLock.ps1" \
        "scripts/Invoke-Iqa2BeadsInit.ps1" \
        "scripts/Get-Iqa2Ready.ps1" \
        "scripts/Export-Iqa2Beads.ps1" \
        ".claude-plugin/plugin.json" \
        ".claude-plugin/marketplace.json" \
    ; do
        if [ -f "${root}/${rel}" ]; then log_ok "${rel}"; else log_missing "${rel}"; fi
    done
    if grep -q '"name": "iqa-beads"' "${root}/.claude-plugin/marketplace.json" 2>/dev/null; then
        log_ok "marketplace registers iqa-beads"
    else
        log_missing "marketplace registration for iqa-beads"
    fi
}

HERE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || pwd)"
if [ "${VERIFY_ONLY}" = "0" ]; then log_info "IQA-Beads install → ${DEST}"; fi
ensure_bd "${HERE}"
ROOT="$(sync_plugin "${HERE}")"
log_info "Verifying plugin files..."
verify_plugin "${ROOT}"

if [ "${FAILURES}" -gt 0 ]; then die "Verification failed with ${FAILURES} missing item(s)."; fi
echo ""
echo -e "\033[0;32mDone. Next steps:\033[0m"
echo "  1. Fill one adapter worksheet: ${ROOT}/skills/adapter-template/SKILL.md"
echo "  2. In the target repo: bd init --stealth  (embedded session DB, no commits)"
echo "  3. Claude Code: /plugin marketplace add <dest>  (dest = the path above)"
echo "  4. Other harnesses: point a skill pointer at <dest>/skills/<skill>/SKILL.md"
echo '  5. Say "IQA-Beads" to start a live UAT session.'
