#!/usr/bin/env bash
# =============================================================================
# File       : script/test/suites/05_secrets_git.sh
# Updated at : 2026-10-28
# Creator    : palarchsys
# =============================================================================

t_section "secrets hors git"
MONO="$(cd -- "${T_ROOT}/.." && pwd)"
for repo in server workstation web; do
    if git -C "${MONO}/${repo}" ls-files | grep -E '(^|/)secrets\.conf$|\.env$|human\.tsv$' >/dev/null; then
        t_fail "secrets:${repo}" "fichier sensible indexé"
    else
        t_pass "secrets:${repo}" "index propre"
    fi
    if git -C "${MONO}/${repo}" ls-files | grep -E '(^|/)AGENTS\.md$' >/dev/null; then
        t_fail "agents:${repo}" "AGENTS.md indexé"
    else
        t_pass "agents:${repo}" "aucun AGENTS.md"
    fi
done
