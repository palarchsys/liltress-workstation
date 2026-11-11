#!/usr/bin/env bash
# =============================================================================
# File       : script/run.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

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

clear

# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/config/global.conf"
# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/core/lib.sh"

require_root
chmod 755 "${INSTALL_DIRECTORY}/liltress"
get_operating_system
get_current_user
get_ssh_port

show_title_box "$(get_text log.liltress-workstation-hardening-workstation)"
printf '\n' >&2
log_info "${INSTALL_WATCHER}" "log.current-user-home" "${CURRENT_USER}" "${CURRENT_HOME}"
log_info "${INSTALL_WATCHER}" "log.port-ssh-detected" "${SSH_PORT}"
log_info "${INSTALL_WATCHER}" "log.os" "${OS_PRETTY}"
printf '\n' >&2

init_install_log
record_account_snapshot
trap install_exit EXIT

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
        test-mail)
            if [[ "${MAIL_ALERTS:-0}" == "1" ]]; then
                if [[ -z "${WATCHDOG_MAIL:-}" ]]; then
                    log_error "${INSTALL_WATCHER}" "log.g-watchdog-mail-is-empty-l-e-mail-of-end-of-inst"
                fi
                log_info "${INSTALL_WATCHER}" "log.send-of-the-e-mail-of-test-to" "${WATCHDOG_MAIL}"
                export TITLE="$(get_text mail.install.test.title)"
                export MODULE_NAME="$(get_text mail.install.module)"
                export PROJECT_NAME
                export WATCHDOG_MAIL
                export CONTENT="$(get_text mail.install.test.body "${PROJECT_NAME}" "${WATCHDOG_MAIL}")"
                if ! bash "${INSTALL_DIRECTORY}/service/cron/watchdogs/send.sh"; then
                    log_error "${INSTALL_WATCHER}" "log.l-e-mail-of-test-toward-was-not-accepted-by-post" "${WATCHDOG_MAIL}"
                fi
                log_success "${INSTALL_WATCHER}" "log.e-mail-of-test-sent-to" "${WATCHDOG_MAIL}"
            else
                log_info "${INSTALL_WATCHER}" "log.alerts-e-mail-off-no-message-of-end-not-is-sent"
            fi
            ;;
        reboot-notice)
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
            ;;
        offer-remove)
            offer_remove_installer
            ;;
        *)
            log_error "${INSTALL_WATCHER}" "run.script.error.6" "${name}"
            ;;
    esac
}

run_install_plan "${INSTALL_DIRECTORY}" "${INSTALL_DIRECTORY}/config/schema/installation.json"
printf '\n' >&2
