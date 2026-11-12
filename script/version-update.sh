#!/usr/bin/env bash
# =============================================================================
# File       : script/version-update.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

# -----------------------------------------------------------------------------
# Purpose    : Show the installed version, then update the published clone.
# Note       : The workshop tree keeps its links. This script refuses to pull there.
# -----------------------------------------------------------------------------

set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${root}/VERSION" ]]; then
    printf '%s\n' "$(tr -d '[:space:]' < "${root}/VERSION")"
fi
if [[ -L "${root}/core" ]]; then
    printf '%s\n' "atelier: le pull reste réservé au clone publié sous /opt" >&2
    exit 1
fi
if [[ ! -d "${root}/.git" ]]; then
    exit 0
fi
mark_prepared_config() {
    local flag="$1"
    if [[ ! -f "${root}/config/global.conf" ]]; then
        return 0
    fi
    if ! grep -q '^CONFIG_PREPARED=1$' "${root}/config/global.conf"; then
        return 0
    fi
    git -C "${root}" update-index "${flag}" -- config/global.conf 2>/dev/null || true
}
mark_prepared_config --skip-worktree
previous="$(git -C "${root}" rev-parse HEAD)"
git -C "${root}" pull --ff-only
if [[ -x "${root}/liltress" ]]; then
    if ! bash "${root}/liltress" run; then
        mark_prepared_config --no-skip-worktree
        git -C "${root}" checkout --detach "${previous}" >/dev/null 2>&1 || git -C "${root}" reset --hard "${previous}"
        mark_prepared_config --skip-worktree
        printf '%s\n' "mise à jour annulée, retour à ${previous}" >&2
        exit 1
    fi
fi
mark_prepared_config --skip-worktree
if [[ -f "${root}/VERSION" ]]; then
    printf '%s\n' "$(tr -d '[:space:]' < "${root}/VERSION")"
fi
