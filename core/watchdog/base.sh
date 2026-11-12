#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/base.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================


get_product_base() {
    if [[ -n "${CONFIG_BASE_DIRECTORY:-}" ]]; then
        printf '%s' "${CONFIG_BASE_DIRECTORY}"
    elif [[ -n "${BASE:-}" ]]; then
        printf '%s' "${BASE}"
    else
        printf '%s' "/opt/liltress-server"
    fi
}

watchdog_runtime_file() {
    local base="$1"
    local name="$2"
    local dir=""
    case "${base}" in
        /opt/liltress-workstation|/opt/liltress-workstation/*)
            dir="/var/lib/liltress-workstation/watchdog"
            ;;
        /opt/liltress-server|/opt/liltress-server/*|/opt/liltress|/opt/liltress/*)
            dir="/var/lib/liltress-server/watchdog"
            ;;
    esac
    if [[ -n "${dir}" ]]; then
        mkdir -p -- "${dir}" 2>/dev/null || true
        if [[ -d "${dir}" && -w "${dir}" ]]; then
            printf '%s\n' "${dir}/${name}"
            return 0
        fi
    fi
    mkdir -p -- "${base}/cron" 2>/dev/null || true
    printf '%s\n' "${base}/cron/${name}"
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
