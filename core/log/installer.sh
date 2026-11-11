#!/usr/bin/env bash
# =============================================================================
# File       : core/log/installer.sh
# Updated at : 2026-11-11
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
    local root="" base="" mail="" conf="" tmp="" back="" rm_rc=0
    root="$(cd -- "${INSTALL_DIRECTORY:?}" && pwd -P)" || return 1
    base="$(cd -- "${CONFIG_BASE_DIRECTORY:?}" && pwd -P)" || return 1
    check_installer_directory "${root}" "${base}" || return 1
    if [[ -f "${root}/core/mail/mail.sh" ]]; then
        mail="${root}/core/mail/mail.sh"
    elif [[ -f "${root}/../share/core/mail/mail.sh" ]]; then
        mail="${root}/../share/core/mail/mail.sh"
    else
        return 2
    fi
    conf="${root}/config/global.conf"
    [[ -f "${conf}" ]] || return 2
    tmp="$(mktemp -d)" || return 2
    if ! install -m 644 -- "${conf}" "${tmp}/global.conf" \
        || ! install -m 644 -- "${mail}" "${tmp}/mail.sh"; then
        rm -rf -- "${tmp}"
        return 2
    fi
    [[ -f "${root}/core/log/log.sh" ]] && install -m 644 -- "${root}/core/log/log.sh" "${tmp}/log.sh"
    [[ -f "${root}/core/text/text.sh" ]] && install -m 644 -- "${root}/core/text/text.sh" "${tmp}/text.sh"
    [[ -f "${root}/core/log/display.sh" ]] && install -m 644 -- "${root}/core/log/display.sh" "${tmp}/display.sh"
    [[ -f "${root}/core/log/journal.sh" ]] && install -m 644 -- "${root}/core/log/journal.sh" "${tmp}/journal.sh"
    [[ -f "${root}/core/watchdog/load.sh" ]] && install -m 644 -- "${root}/core/watchdog/load.sh" "${tmp}/watchdog-load.sh"
    [[ -f "${root}/core/host/fs.sh" ]] && install -m 644 -- "${root}/core/host/fs.sh" "${tmp}/fs.sh"
    if [[ -d "${root}/../share/locale" ]]; then
        mkdir -p -- "${tmp}/locale"
        cp -a "${root}/../share/locale/." "${tmp}/locale/"
    fi
    if [[ -d "${root}/locale" ]]; then
        mkdir -p -- "${tmp}/locale"
        cp -a "${root}/locale/." "${tmp}/locale/"
    fi
    [[ -f "${root}/config/chkrootkit/patterns.ignore" ]] \
        && install -m 644 -- "${root}/config/chkrootkit/patterns.ignore" "${tmp}/patterns.ignore"
    [[ -f "${root}/config/clamav/onaccess.conf" ]] \
        && install -m 644 -- "${root}/config/clamav/onaccess.conf" "${tmp}/onaccess.conf"
    back="$(pwd -P 2>/dev/null || true)"
    cd / || { rm -rf -- "${tmp}"; return 1; }
    rm -rf -- "${root}" || rm_rc=$?
    if ! install -d -m 755 -- "${base}/src" "${base}/src/core" "${base}/src/config" \
        "${base}/src/core/mail" "${base}/src/core/log" "${base}/src/core/text" \
        "${base}/src/core/watchdog" "${base}/src/core/host" "${base}/src/locale" \
        || ! install -m 644 -- "${tmp}/global.conf" "${base}/src/config/global.conf" \
        || ! install -m 644 -- "${tmp}/mail.sh" "${base}/src/core/mail/mail.sh"; then
        rm -rf -- "${tmp}"
        if [[ -n "${back}" && -d "${back}" ]]; then
            cd -- "${back}" || true
        fi
        return 4
    fi
    [[ -f "${tmp}/log.sh" ]] && install -m 644 -- "${tmp}/log.sh" "${base}/src/core/log/log.sh"
    [[ -f "${tmp}/text.sh" ]] && install -m 644 -- "${tmp}/text.sh" "${base}/src/core/text/text.sh"
    [[ -f "${tmp}/display.sh" ]] && install -m 644 -- "${tmp}/display.sh" "${base}/src/core/log/display.sh"
    [[ -f "${tmp}/journal.sh" ]] && install -m 644 -- "${tmp}/journal.sh" "${base}/src/core/log/journal.sh"
    [[ -f "${tmp}/watchdog-load.sh" ]] && install -m 644 -- "${tmp}/watchdog-load.sh" "${base}/src/core/watchdog/load.sh"
    [[ -f "${tmp}/fs.sh" ]] && install -m 644 -- "${tmp}/fs.sh" "${base}/src/core/host/fs.sh"
    if [[ -d "${tmp}/locale" ]]; then
        cp -a "${tmp}/locale/." "${base}/src/locale/"
    fi
    if [[ -f "${tmp}/patterns.ignore" ]]; then
        install -d -m 755 -- "${base}/src/config/chkrootkit"
        install -m 644 -- "${tmp}/patterns.ignore" "${base}/src/config/chkrootkit/patterns.ignore"
    fi
    if [[ -f "${tmp}/onaccess.conf" ]]; then
        install -d -m 755 -- "${base}/src/config/clamav"
        install -m 644 -- "${tmp}/onaccess.conf" "${base}/src/config/clamav/onaccess.conf"
    fi
    rm -rf -- "${tmp}"
    if [[ -n "${back}" && -d "${back}" ]]; then
        cd -- "${back}" || true
    fi
    if [[ "${rm_rc}" -ne 0 || -e "${root}/liltress" || -e "${root}/config/secrets.conf" || -e "${root}/script/run.sh" ]]; then
        return 3
    fi
    [[ -f "${base}/src/config/global.conf" && -f "${base}/src/core/mail/mail.sh" ]] || return 4
    [[ ! -e "${base}/src/config/secrets.conf" || "${root}" != "${base}/src" ]] || return 3
    return 0
}

offer_remove_installer() {
    local root=""
    root="$(cd -- "${INSTALL_DIRECTORY:?}" && pwd -P)" || {
        log_warn "${INSTALL_WATCHER:-BASH}" "install.log.warn.8"
        return 0
    }
    show_closing_command "$(get_text install.log.info.4)" "sudo rm -rf ${root}"
    return 0
}
