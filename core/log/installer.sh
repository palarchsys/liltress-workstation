#!/usr/bin/env bash
# =============================================================================
# File       : core/log/installer.sh
# Updated at : 2026-11-13
# Creator    : palarchsys
# =============================================================================


ask() {
    local label="$1"
    local __var="$2"
    local width="${#label}"
    local value=""
    if (( width < 12 )); then
        width=12
    fi
    echo "" >&2
    printf '         \e[34m%*s\e[0m : ' "${width}" "${label}" >&2
    IFS= read -r value < /dev/tty || log_error "${INSTALL_WATCHER:-BASH}" "install.log.error.2"
    printf -v "${__var}" '%s' "${value}"
}

check_installer_directory() {
    local root="$1"
    local base="$2"
    [[ -n "${root}" && "${root}" == /* && -d "${root}" ]] || return 1
    [[ "${root}" != *[[:space:]]* && "${root}" != *$'\n'* ]] || return 1
    case "${root}" in
        /|/opt|/usr|/bin|/sbin|/lib|/lib64|/etc|/var|/home|/boot|/tmp|/root|/srv|/proc|/sys|/dev|/run)
            return 1
            ;;
    esac
    [[ "${root#/}" == */* ]] || return 1
    [[ -f "${root}/liltress" && -f "${root}/script/run.sh" ]] || return 1
    [[ -n "${base}" && "${base}" == /* && -d "${base}" ]] || return 1
    [[ "${base}" != *[[:space:]]* ]] || return 1

    case "${base}/" in
        "${root}/"*) return 1 ;;
    esac
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
