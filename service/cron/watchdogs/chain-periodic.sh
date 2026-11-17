#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/chain-periodic.sh
# Updated at : 2026-11-17
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Run the periodic scan links one after another.
# Note       : A second start exits while the lock is held.
# Note       : One failure leaves the next link free to run.
# -----------------------------------------------------------------------------


run_periodic_link() {
    local script="$1"
    local label="$2"
    local status=0
    [[ -x "${HERE}/${script}" ]] || return 0
    set +e
    bash "${HERE}/${script}"
    status=$?
    set -e
    if [[ "${status}" -ge 128 ]]; then
        log_alert "$(get_crash_sentence "${label}" "${status}")" || true
    fi
}

run_periodic_chain() {
    local base="" lock_path="" previous=""
    base="$(get_product_base)"
    mkdir -p -- "${base}/cron" "${base}/log"
    lock_path="$(watchdog_runtime_file "${base}" watchdog-chain.lock)"
    exec 9>"${lock_path}"
    if ! flock -n 9; then
        return 0
    fi
    run_periodic_link chain-refresh-db.sh "signatures"
    run_periodic_link scan-clamav.sh "ClamAV"
    run_periodic_link chain-scan-integrity.sh "intégrité"
    run_periodic_link scan-fingerprint.sh "empreinte"
    run_periodic_link scan-egress.sh "journal sortant"
    run_periodic_link scan-usbguard.sh "USBGuard"
    previous="$(watchdog_runtime_file "${base}" watchdog-chain.stamp)"
    date +%s >"${previous}"
    chmod 600 "${previous}" 2>/dev/null || true
}

set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/common.sh"
if [[ -f "${BASE}/cron/mail.conf" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${BASE}/cron/mail.conf"
    set +a
fi
export BASE
if [[ -n "${CONFIG_BASE_DIRECTORY:-}" ]]; then
    export CONFIG_BASE_DIRECTORY
fi
run_periodic_chain
exit 0
