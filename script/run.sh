#!/usr/bin/env bash
# =============================================================================
# File       : script/run.sh
# Updated at : 2026-11-22
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Launch the workstation hardening from the prepared configuration.
# Note       : An unprepared configuration stops before any change.
# -----------------------------------------------------------------------------


# shellcheck disable=SC2155

INSTALL_WATCHER="${INSTALL_WATCHER:-BASH}"
export INSTALL_WATCHER

INSTALL_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
export INSTALL_DIRECTORY

# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/script/config-check.sh"
if ! require_prepared_config "${INSTALL_DIRECTORY}"; then
    printf "$(get_text log.ninstallation-rejected-prepare-the-two-files-n)" >&2
    printf "$(get_text log.bash-liltress-configures "${INSTALL_DIRECTORY}")" >&2
    printf "$(get_text log.bash-liltress-check "${INSTALL_DIRECTORY}")" >&2
    exit 1
fi
readonly INSTALL_DIRECTORY

# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/config/global.conf"
# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/core/boot/lib.sh"

require_root
chmod 755 "${INSTALL_DIRECTORY}/liltress"
get_operating_system
get_current_user
get_ssh_port

init_install_log
record_account_snapshot
trap install_exit EXIT

# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/service/unbound/dns.sh"
clear_dns_override

# A pending kernel or service change requests a reboot.
show_reboot_notice() {
    set_step_hidden "$(get_text run.close.done)"
    show_closing_note "$(get_text log.journals-title)" "$(show_path "${INSTALL_LOG_DIR}")"
    show_closing_note "$(get_text log.lynis-launch)" "$(get_text log.lynis-command)"
    reboot_needed=0
    [[ -f /var/run/reboot-required ]] && reboot_needed=1
    if command -v needrestart >/dev/null 2>&1; then
        nr_out="$(needrestart -b -r l 2>/dev/null || true)"
        if printf '%s\n' "${nr_out}" | grep -qE '^NEEDRESTART-KSTA: [2-9]|^NEEDRESTART-SVC:|^NEEDRESTART-SESS:'; then
            reboot_needed=1
        fi
    fi
    if [[ "${reboot_needed}" -eq 1 ]]; then
        log_info "${INSTALL_WATCHER}" "log.a-reboot-is-recommended-kernel-libc"
    fi
}

run_install_action() {
    local name="$1"
    case "${name}" in
        sysctl)
            log_info "${INSTALL_WATCHER}" "log.application-of-sysctl"
            run_optional "${INSTALL_WATCHER}" "run.script.error" sysctl --system
            log_success "${INSTALL_WATCHER}" "log.sysctl-applied"
            ;;
        apt-upgrade)
            log_info "${INSTALL_WATCHER}" "log.installation-of-the-fixes-of-security"
            export DEBIAN_FRONTEND=noninteractive
            export NEEDRESTART_MODE=a
            run_silent_apt "${INSTALL_WATCHER}" "update" "run.script.error"
            run_silent_apt "${INSTALL_WATCHER}" "-o APT::Get::Always-Include-Phased-Updates=true upgrade -y --with-new-pkgs" "run.script.error"
            log_success "${INSTALL_WATCHER}" "log.fixes-of-security-installed"
            ;;
        reboot-notice)
            show_reboot_notice
            ;;
        *)
            log_error "${INSTALL_WATCHER}" "run.script.error.6" "${name}"
            ;;
    esac
}

run_install_plan "${INSTALL_DIRECTORY}" "${INSTALL_DIRECTORY}/config/schema/installation.json"
# The watched files are already in their installed state.
CONFIG_BASE_DIRECTORY="${CONFIG_BASE_DIRECTORY:-${INSTALL_DIRECTORY}}" \
    bash "${INSTALL_DIRECTORY}/service/cron/watchdogs/scan-fingerprint.sh" refresh
printf '\n' >&2
