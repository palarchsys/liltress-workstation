#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/chain-refresh-db.sh
# Updated at : 2026-11-17
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Refresh the signature tools, one after another.
# Note       : One failure leaves the next tool free to run.
# -----------------------------------------------------------------------------


run_refresh_link() {
    local script="$1"
    local status=0
    [[ -x "${HERE}/${script}" ]] || return 0
    set +e
    bash "${HERE}/${script}"
    status=$?
    set -e
    if [[ "${status}" -ge 128 ]]; then
        log_alert "$(get_crash_sentence "${script}" "${status}")" || true
    fi
}

run_refresh_chain() {
    run_refresh_link refresh-clamav-db.sh
    run_refresh_link refresh-rkhunter-db.sh
    run_refresh_link refresh-chkrootkit-db.sh
    run_refresh_link refresh-debsums-db.sh
}

set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/common.sh"
run_refresh_chain
exit 0
