#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/base.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Resolve the product root and one runtime path.
# Note       : A base under /opt uses the var lib directory when that directory can be used.
# -----------------------------------------------------------------------------


get_product_base() {
    if [[ -n "${CONFIG_BASE_DIRECTORY:-}" ]]; then
        printf '%s' "${CONFIG_BASE_DIRECTORY}"
    elif [[ -n "${BASE:-}" ]]; then
        printf '%s' "${BASE}"
    else
        printf '%s' "/opt/liltress-server"
    fi
}

get_watchdog_runtime_file() {
    local base="$1"
    local name="$2"
    local directory=""
    case "${base}" in
        /opt/liltress-workstation | /opt/liltress-workstation/*)
            directory="/var/lib/liltress-workstation/watchdog"
            ;;
        /opt/liltress-server | /opt/liltress-server/* | /opt/liltress | /opt/liltress/*)
            directory="/var/lib/liltress-server/watchdog"
            ;;
    esac
    if [[ -n "${directory}" ]]; then
        mkdir -p -- "${directory}" 2>/dev/null || true
        if [[ -d "${directory}" && -w "${directory}" ]]; then
            printf '%s\n' "${directory}/${name}"
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
    if [[ -x "${base}/service/cron/watchdogs/send.sh" ]]; then
        printf '%s\n' "${base}/service/cron/watchdogs/send.sh"
        return 0
    fi
    return 1
}
