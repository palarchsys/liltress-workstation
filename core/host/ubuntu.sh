#!/usr/bin/env bash
# =============================================================================
# File       : core/host/ubuntu.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================


check_ubuntu_base() {
    local os_id="${ID:-}"
    local os_codename="${UBUNTU_CODENAME:-}"
    local version_id="${VERSION_ID:-}"
    local pretty="${PRETTY_NAME:-${OS_PRETTY:-inconnu}}"
    local base_version=""

    if [[ "${os_id}" != "ubuntu" ]]; then
        log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.17" "${pretty}"
    fi

    if [[ "${version_id}" =~ ^([0-9]+)\.([0-9]+) ]]; then
        base_version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
    fi
    if [[ -z "${base_version}" ]]; then
        log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.18" "${version_id:-aucune}"
    fi

    UBUNTU_BASE_VERSION="${base_version}"
    UBUNTU_BASE_CODENAME="${os_codename:-inconnu}"
    if ! dpkg --compare-versions "${UBUNTU_BASE_VERSION}" ge "26.04"; then
        log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.19" "${UBUNTU_BASE_VERSION}" "${UBUNTU_BASE_CODENAME}"
    fi
    export UBUNTU_BASE_VERSION UBUNTU_BASE_CODENAME
}

# Return 0 when the resolved base is an LTS: even year, minor 4.

check_ubuntu_lts() {
    local version="${UBUNTU_BASE_VERSION:-}"
    local major=0
    local minor=0

    if [[ ! "${version}" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
        return 1
    fi
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    if [[ "${minor}" -eq 4 && $((major % 2)) -eq 0 ]]; then
        return 0
    fi
    return 1
}

# Print the Postfix map type in use: hash on 26.04, cdb on 26.10.

get_sasl_map_type() {
    local map_type=""
    map_type="$(postconf -h default_database_type 2>/dev/null || true)"
    case "${map_type}" in
        hash|cdb|lmdb)
            printf '%s\n' "${map_type}"
            ;;
        *)
            log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.20" "${map_type:-aucun}"
            ;;
    esac
}

get_operating_system() {
    # shellcheck disable=SC1091
    source /etc/os-release
    OS_ID="${ID:-}"
    OS_VERSION_ID="${VERSION_ID:-}"
    OS_PRETTY="${PRETTY_NAME:-}"
    export OS_ID OS_VERSION_ID OS_PRETTY
    check_ubuntu_base
}

check_virtual_machine() {
    if command -v virsh >/dev/null 2>&1; then
        return 0
    fi
    if dpkg-query -W -f '${Status}\n' qemu-kvm qemu-system-x86 libvirt-daemon 2>/dev/null | grep -q 'install ok'; then
        return 0
    fi
    if [[ -e /dev/kvm ]]; then
        return 0
    fi
    return 1
}

check_app() {
    local name="$1"
    command -v "$name" >/dev/null 2>&1 && return 0
    dpkg-query -W -f '${Status}\n' "$name" 2>/dev/null | grep -q 'install ok' && return 0
    flatpak info "$name" >/dev/null 2>&1 && return 0
    return 1
}

check_password_unchanged() {
    case "$*" in
        *chpasswd*|*passwd\ *|*" usermod -p "*|*chage*)
            log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.22" "$*"
            ;;
    esac
}

check_ubuntu_pro() {
    command -v pro >/dev/null 2>&1 || return 1
    local st
    st="$(pro status --format json 2>/dev/null || true)"
    if [[ -n "$st" ]] && command -v jq >/dev/null 2>&1; then
        echo "$st" | jq -e '.attached == true' >/dev/null 2>&1 && return 0
    fi
    pro status 2>/dev/null | grep -qiE 'This machine is attached|machine is attached to an Ubuntu Pro|est attachée|Attached:[[:space:]]*(yes|true)' && return 0
    return 1
}
