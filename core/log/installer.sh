#!/usr/bin/env bash
# =============================================================================
# File       : core/log/installer.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Ask one question and accept only a nested install tree.
# -----------------------------------------------------------------------------


ask() {
    local label="$1"
    local __var="$2"
    local width="${#label}"
    local value=""
    if ((width < 12)); then
        width=12
    fi
    echo "" >&2
    printf '         \e[34m%*s\e[0m : ' "${width}" "${label}" >&2
    IFS= read -r value </dev/tty || log_error "${INSTALL_WATCHER:-BASH}" "install.log.error.2"
    printf -v "${__var}" '%s' "${value}"
}

# The path is absolute, present, and free of blanks.
check_plain_directory() {
    local path="$1"
    [[ -n "${path}" && "${path}" == /* && -d "${path}" ]] || return 1
    [[ "${path}" != *[[:space:]]* ]] || return 1
    return 0
}

# A product tree is nested and carries the marker plus the runner.
check_install_root_shape() {
    local root="$1"
    [[ "${root}" != *$'\n'* ]] || return 1
    case "${root}" in
        / | /opt | /usr | /bin | /sbin | /lib | /lib64 | /etc | /var | /home | /boot | /tmp | /root | /srv | /proc | /sys | /dev | /run)
            return 1
            ;;
    esac
    [[ "${root#/}" == */* ]] || return 1
    [[ -f "${root}/liltress" && -f "${root}/script/run.sh" ]] || return 1
    return 0
}

# The base stays outside the product tree.
check_install_base() {
    local root="$1"
    local base="$2"
    check_plain_directory "${base}" || return 1
    case "${base}/" in
        "${root}/"*) return 1 ;;
    esac
    return 0
}

check_installer_directory() {
    local root="$1"
    local base="$2"
    check_plain_directory "${root}" || return 1
    check_install_root_shape "${root}" || return 1
    check_install_base "${root}" "${base}" || return 1
    return 0
}

remove_installer_tree() {
    local root="" base=""
    root="$(cd -- "${INSTALL_DIRECTORY:?}" && pwd -P)" || return 1
    base="$(cd -- "${CONFIG_BASE_DIRECTORY:?}" && pwd -P)" || return 1
    check_installer_directory "${root}" "${base}" || return 1
    return 0
}

offer_remove_installer() {
    return 0
}
