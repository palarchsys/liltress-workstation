#!/usr/bin/env bash
# =============================================================================
# File       : service/apparmor/detect-and-apply.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================
# -----------------------------------------------------------------------------
# Purpose    : Remove an hfu profile that is not shipped.
# Note       : The parser unload is written under cron/security_logs.
# -----------------------------------------------------------------------------

INSTALL_DIRECTORY="${1:-${INSTALL_DIRECTORY:-}}"
export INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_apparmor_detect() {
    local base="${CONFIG_BASE_DIRECTORY:-/opt/liltress-workstation}"
    install -d -m 750 "${base}/cron/security_logs"
    printf '%s %s\n' "$(date -Iseconds)" "$*" >> "${base}/cron/security_logs/apparmor-detect.log"
}

remove_unshipped_profile() {
    local installed base
    shopt -s nullglob
    for installed in /etc/apparmor.d/w-*; do
        base="$(basename -- "${installed}")"
        if [[ -f "${INSTALL_DIRECTORY}/config/apparmor/${base}" ]]; then
            continue
        fi
        log_info "BASH" "log.removal-of-the-profile" "${base}"
        if command -v apparmor_parser >/dev/null 2>&1; then
            apparmor_parser -R "${installed}" >/dev/null 2>&1 || true
        fi
        rm -f "${installed}"
        log_success "BASH" "log.profile-removed" "${base}"
        log_apparmor_detect "${base} retiré"
    done
    shopt -u nullglob
}

remove_unshipped_profile
