#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/refresh-integrity.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Refresh the integrity databases after a tunnel change.
# Note       : A stamp records that this visit ran.
# -----------------------------------------------------------------------------


set -euo pipefail

if [[ "${VPN_SKIP_INTEGRITY:-0}" == "1" ]]; then
    exit 0
fi

if [[ -n "${VPN_INTEGRITY_MARK:-}" ]]; then
    printf 'ran\n' >>"${VPN_INTEGRITY_MARK}"
fi

if [[ "${EUID}" -ne 0 ]]; then
    exit 0
fi

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "${here}/../.." && pwd)"
# shellcheck disable=SC1091
source "${root}/core/boot/lib.sh"
# shellcheck disable=SC1091
source "${root}/config/global.conf"
# shellcheck disable=SC1091
source "${root}/core/watchdog/base.sh"

INSTALL_WATCHER="${INSTALL_WATCHER:-BASH}"
log_info "${INSTALL_WATCHER}" "vpn.integrity.start"
wrote=0

if [[ -f /etc/aide/aide.conf && -f "${root}/service/aide/refresh-db.sh" ]]; then
    if ! bash "${root}/service/aide/refresh-db.sh"; then
        log_error "${INSTALL_WATCHER}" "vpn.integrity.aide"
    fi
    wrote=1
else
    log_info "${INSTALL_WATCHER}" "vpn.integrity.skip" "aide"
fi

if command -v rkhunter >/dev/null 2>&1 && [[ -f "${root}/service/rkhunter/refresh-db.sh" ]]; then
    if ! bash "${root}/service/rkhunter/refresh-db.sh"; then
        log_error "${INSTALL_WATCHER}" "vpn.integrity.rkhunter"
    fi
    wrote=1
else
    log_info "${INSTALL_WATCHER}" "vpn.integrity.skip" "rkhunter"
fi

base="$(get_product_base)"
list="${base}/config/integrity/paths.list"
if [[ ! -f "${list}" ]]; then
    log_info "${INSTALL_WATCHER}" "vpn.integrity.skip" "integrity"
elif ! stamp="$(watchdog_runtime_file "${base}" integrity.sha256)"; then
    log_error "${INSTALL_WATCHER}" "vpn.integrity.stamp"
else
    current="$(mktemp)"
    trap 'rm -f "${current}"' EXIT
    while read -r path; do
        [[ -n "${path}" && "${path}" != \#* && -f "${path}" ]] || continue
        sha256sum -- "${path}"
    done <"${list}" | sort >"${current}"
    mkdir -p -- "$(dirname -- "${stamp}")"
    if ! cat "${current}" >"${stamp}"; then
        log_error "${INSTALL_WATCHER}" "vpn.integrity.stamp"
    fi
    chmod 600 "${stamp}"
    wrote=1
fi

if [[ "${wrote}" -eq 1 ]]; then
    log_success "${INSTALL_WATCHER}" "vpn.integrity.ok"
fi
