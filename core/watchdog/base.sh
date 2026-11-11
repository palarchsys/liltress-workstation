#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/base.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================


get_product_base() {
    if [[ -n "${CONFIG_BASE_DIRECTORY:-}" ]]; then
        printf '%s' "${CONFIG_BASE_DIRECTORY}"
    elif [[ -n "${BASE:-}" ]]; then
        printf '%s' "${BASE}"
    else
        printf '%s' "/opt/liltress"
    fi
}

send_path() {
    if [[ -n "${CRON_BIN_PATH:-}" && -x "${CRON_BIN_PATH}/send.sh" ]]; then
        printf '%s\n' "${CRON_BIN_PATH}/send.sh"
        return 0
    fi
    local base
    base="$(get_product_base)"
    if [[ -x "${base}/cron/bin/send.sh" ]]; then
        printf '%s\n' "${base}/cron/bin/send.sh"
        return 0
    fi
    return 1
}
