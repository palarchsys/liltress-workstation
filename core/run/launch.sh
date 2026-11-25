#!/usr/bin/env bash
# =============================================================================
# File       : core/run/launch.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Dispatch a product command to the matching script.
# -----------------------------------------------------------------------------


# Sources the first log engine that exists.
source_launch_log() {
    local root="$1"
    local launch_here="" launch_candidate=""
    launch_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    for launch_candidate in \
        "${launch_here}/../log/log.sh" \
        "${root}/core/log/log.sh" \
        "${root}/core/log/log.sh"; do
        if [[ -n "${launch_candidate}" && -f "${launch_candidate}" ]]; then
            # shellcheck disable=SC1090
            source "${launch_candidate}"
            return 0
        fi
    done
    return 0
}

load_launch_text() {
    local root="$1"
    if [[ -z "${PRODUCT_ROOT:-}" ]]; then
        PRODUCT_ROOT="${root}"
        export PRODUCT_ROOT
    fi
    if ! declare -F get_text >/dev/null 2>&1; then
        source_launch_log "${root}"
    fi
    if declare -F read_language_file >/dev/null 2>&1 \
        && [[ -f "${root}/config/global.conf" ]]; then
        read_language_file "${root}/config/global.conf"
    elif declare -F load_text >/dev/null 2>&1; then
        load_text "${LANGUAGE:-en}"
    fi
}

launch_unknown() {
    local root="$1"
    local name="$2"
    printf '%s\n' "$(get_text launch.unknown-command "${name}")" >&2
    printf '%s\n' "$(get_text launch.usage-liltress-help "${root}")" >&2
    exit 2
}

launch_exec() {
    local root="$1"
    local path="$2"
    shift 2
    if [[ ! -f "${path}" ]]; then
        launch_unknown "${root}" "${path}"
    fi
    exec bash "${path}" "$@"
}

launch_product() {
    local root="$1"
    if [[ -f "${root}/script/verify/workstation.sh" ]]; then
        printf '%s\n' workstation
    elif [[ -f "${root}/script/verify/matrix.sh" ]]; then
        printf '%s\n' server
    else
        printf '%s\n' unknown
    fi
}

launch_install() {
    local root="$1"
    shift
    local sub="${1:-}"
    local url="" repo=""
    shift || true
    case "$(launch_product "${root}")" in
        workstation)
            url="https://raw.githubusercontent.com/palarchsys/liltress-workstation/main/script/install.sh"
            repo="https://github.com/palarchsys/liltress-workstation"
            ;;
        server)
            url="https://raw.githubusercontent.com/palarchsys/liltress-server/main/script/install.sh"
            repo="https://github.com/palarchsys/liltress-server"
            ;;
        *)
            launch_unknown "${root}" "install"
            ;;
    esac
    case "${sub}" in
        apt-update)
            exec apt-get update
            ;;
        apt-packages)
            exec apt-get install -y ca-certificates curl git swaks tar
            ;;
        remote)
            curl -fsSL "${url}" | bash
            exit "$?"
            ;;
        clone)
            exec git clone "${repo}" "$@"
            ;;
        *)
            launch_unknown "${root}" "install ${sub}"
            ;;
    esac
}

launch_verify() {
    local root="$1"
    shift
    local sub="${1:-}"
    local profile=""
    shift || true
    case "${sub}" in
        alerts)
            launch_exec "${root}" "${root}/script/verify/alerts.sh" "$@"
            ;;
        workstation)
            launch_exec "${root}" "${root}/script/verify/workstation.sh" BASH "${root}"
            ;;
        boot-check)
            launch_exec "${root}" "${root}/script/boot-check.sh" "$@"
            ;;
        boot)
            launch_exec "${root}" "${root}/script/verify/boot.sh" "$@"
            ;;
        chkrootkit)
            launch_exec "${root}" "${root}/script/verify/chkrootkit-fp.sh" "$@"
            ;;
        matrix | livekit | wireguard)
            profile="$(printf '%s' "${sub}" | tr '[:lower:]' '[:upper:]')"
            launch_exec "${root}" "${root}/script/verify/${sub}.sh" "${root}" "${profile}"
            ;;
        *)
            launch_unknown "${root}" "verify ${sub}"
            ;;
    esac
}

# Known scan tools replace this process. An unknown name returns 1.
launch_maintain_scan() {
    local root="$1"
    local sub="$2"
    shift 2
    case "${sub}" in
        aide)
            if [[ -f "${root}/service/aide/refresh-db.sh" ]]; then
                launch_exec "${root}" "${root}/service/aide/refresh-db.sh" "$@"
            fi
            REBUILD_BASE=1 launch_exec "${root}" "${root}/service/aide/init-db.sh" BASH "${root}"
            ;;
        rkhunter)
            launch_exec "${root}" "${root}/service/rkhunter/refresh-db.sh" "$@"
            ;;
        chkrootkit)
            launch_exec "${root}" "${root}/service/chkrootkit/ignore-log.sh" "$@"
            ;;
        debsums)
            launch_exec "${root}" "${root}/service/debsums/ignore-log.sh" "$@"
            ;;
        scan-skip)
            launch_exec "${root}" "${root}/script/scan-skip.sh" "$@"
            ;;
        exclude)
            if [[ ! -f "${root}/script/exclusions.sh" ]]; then
                return 1
            fi
            launch_exec "${root}" "${root}/script/exclusions.sh" "$@"
            ;;
        *)
            return 1
            ;;
    esac
}

# Host tools replace this process. An unknown name returns 1.
launch_maintain_host() {
    local root="$1"
    local sub="$2"
    shift 2
    case "${sub}" in
        mirrors)
            launch_exec "${root}" "${root}/service/cron/watchdogs/record-mirrors.sh" "$@"
            ;;
        web)
            launch_exec "${root}" "${root}/docker/web/update.sh" "$@"
            ;;
        recover-pam)
            launch_exec "${root}" "${root}/system/recover-pam.sh" "$@"
            ;;
        restore)
            launch_exec "${root}" "${root}/core/quarantine/restore.sh" "$@"
            ;;
        mail)
            launch_exec "${root}" "${root}/core/mail/mail-test.sh" "$@"
            ;;
        ssh-close)
            if [[ ! -f "${root}/script/ssh-close.sh" ]]; then
                return 1
            fi
            launch_exec "${root}" "${root}/script/ssh-close.sh" "$@"
            ;;
        *)
            return 1
            ;;
    esac
}

launch_maintain() {
    local root="$1"
    shift
    local sub="${1:-}"
    shift || true
    launch_maintain_scan "${root}" "${sub}" "$@" && return 0
    launch_maintain_host "${root}" "${sub}" "$@" && return 0
    launch_unknown "${root}" "maintain ${sub}"
}

launch_watchdog() {
    local root="$1"
    local name="${2:-}"
    local script=""
    shift 2 || true
    if [[ ! "${name}" =~ ^[A-Za-z0-9._-]+$ ]]; then
        launch_unknown "${root}" "${name}"
    fi
    case "${name}" in
        chain) script="chain-periodic.sh" ;;
        aide | rkhunter | chkrootkit | clamav | debsums | auditd) script="scan-${name}.sh" ;;
        *) script="${name}.sh" ;;
    esac
    launch_exec "${root}" "${root}/service/cron/watchdogs/${script}" "$@"
}

# Root stays. Another account is sent through sudo, except help and a repository clone.
require_launch_root() {
    local root="$1"
    local cmd="$2"
    shift 2
    [[ "${EUID}" -eq 0 ]] && return 0
    case "${cmd}" in
        help | -h | --help) return 0 ;;
        install)
            if [[ "${1:-}" != "clone" ]]; then
                exec sudo -- "${root}/liltress" "${cmd}" "$@"
            fi
            return 0
            ;;
        *)
            exec sudo -- "${root}/liltress" "${cmd}" "$@"
            ;;
    esac
}

# extra stays visible to the caller.
show_launch_help() {
    local root="$1"
    printf '%s\n' "$(get_text launch.usage "${root}")"
    extra=""
    if [[ -f "${root}/script/verify/workstation.sh" ]]; then
        extra="$(get_text launch.usage.extra.workstation)"
        if [[ "${extra}" == "launch.usage.extra.workstation" ]]; then
            extra=""
        fi
    elif [[ -f "${root}/script/verify/matrix.sh" ]]; then
        extra="$(get_text launch.usage.extra.server)"
        if [[ "${extra}" == "launch.usage.extra.server" ]]; then
            extra=""
        fi
    fi
    if [[ -n "${extra}" ]]; then
        printf '\n%s\n' "${extra}"
    fi
}

# Known script names replace this process. The caller owns launch_known.
launch_script() {
    local root="$1"
    local cmd="$2"
    shift 2
    launch_known=0
    case "${cmd}" in
        configure)
            launch_known=1
            exec bash "${root}/script/configure.sh" "$@"
            ;;
        check)
            launch_known=1
            exec bash "${root}/script/configure.sh" --check "$@"
            ;;
        run)
            launch_known=1
            exec bash "${root}/script/run.sh" "$@"
            ;;
        lynis)
            launch_known=1
            exec bash "${root}/core/run/lynis.sh" "${root}" "$@"
            ;;
        logs)
            launch_known=1
            exec bash "${root}/script/log-collect.sh" "$@"
            ;;
    esac
    return 0
}

run_launch() {
    local root="$1"
    local cmd="${2:-help}"
    local launch_known=0
    shift 2 || true
    require_launch_root "${root}" "${cmd}" "$@"
    load_launch_text "${root}"
    launch_script "${root}" "${cmd}" "$@"
    if [[ "${launch_known}" -eq 1 ]]; then
        return 0
    fi
    case "${cmd}" in
        vpn)
            if [[ -f "${root}/service/vpn/cli.sh" ]]; then
                exec bash "${root}/service/vpn/cli.sh" "$@"
            fi
            launch_unknown "${root}" "${cmd}"
            ;;
        verify)
            launch_verify "${root}" "$@"
            ;;
        maintain)
            launch_maintain "${root}" "$@"
            ;;
        timer | cron)
            launch_watchdog "${root}" "$@"
            ;;
        install)
            launch_install "${root}" "$@"
            ;;
        help | -h | --help)
            show_launch_help "${root}"
            ;;
        *)
            launch_unknown "${root}" "${cmd}"
            ;;
    esac
}
