#!/usr/bin/env bash
# =============================================================================
# File       : script/run.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

# shellcheck disable=SC2155

INSTALL_WATCHER="${INSTALL_WATCHER:-BASH}"
export INSTALL_WATCHER

G_INSTALL_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
export G_INSTALL_DIRECTORY

# shellcheck disable=SC1091
source "${G_INSTALL_DIRECTORY}/script/config-check.sh"
if ! require_prepared_config "${G_INSTALL_DIRECTORY}"; then
    printf "$(get_text log.ninstallation-rejected-prepare-the-two-files-n)" >&2
    printf "$(get_text log.bash-liltress-configures "${G_INSTALL_DIRECTORY}")" >&2
    printf "$(get_text log.bash-liltress-check "${G_INSTALL_DIRECTORY}")" >&2
    exit 1
fi
readonly G_INSTALL_DIRECTORY

clear

# shellcheck disable=SC1091
source "${G_INSTALL_DIRECTORY}/config/global.conf"
# shellcheck disable=SC1091
source "${G_INSTALL_DIRECTORY}/core/lib.sh"

require_root
chmod 755 "${G_INSTALL_DIRECTORY}/liltress"
get_operating_system
get_current_user
get_ssh_port

set_color_violet "═════════════════════════════════════════════════════════════════════════════════"
set_color_violet "$(get_text log.liltress-workstation-hardening-workstation)"
set_color_violet "═════════════════════════════════════════════════════════════════════════════════"

echo "$(get_text log.current-user-home "${CURRENT_USER}" "${CURRENT_HOME}")"
echo "$(get_text log.port-ssh-detected "${SSH_PORT}")"
echo "$(get_text log.os "${OS_PRETTY}")"
echo ""
echo "$(get_text log.ssh-then-the-stack-of-security-postfix-follows-t)"
echo "$(get_text log.after-the-fixes-usbguard)"
echo "$(get_text log.i386-enabled-on-amd64)"
echo "$(get_text log.ufw-deny-incoming-allow-outgoing)"
echo "$(get_text log.dns-local-unbound)"
echo "$(get_text log.ssh-passwordauthentication-yes-permitrootlogin-n)"
echo "$(get_text log.ubuntu-pro-esm-infra-esm-apps-and-livepatch)"
echo "$(get_text log.help-baseline-then-verify-workstation-sh)"
echo ""

init_install_log
record_account_snapshot
trap install_exit EXIT

run_install_action() {
    local name="$1"
    case "${name}" in
        sysctl)
            run_optional "${INSTALL_WATCHER}" "run.script.error" sysctl --system
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
            if [[ "${G_MAIL_ALERTS:-0}" == "1" ]]; then
                if [[ -z "${G_WATCHDOG_MAIL:-}" ]]; then
                    log_error "${INSTALL_WATCHER}" "log.g-watchdog-mail-is-empty-l-e-mail-of-end-of-inst"
                fi
                log_info "${INSTALL_WATCHER}" "log.send-of-the-e-mail-of-test-to" "${G_WATCHDOG_MAIL}"
                export TITLE="$(get_text mail.install.test.title)"
                export MODULE_NAME="$(get_text mail.install.module)"
                export G_PROJECT_NAME
                export G_WATCHDOG_MAIL
                export CONTENT="$(get_text mail.install.test.body "${G_PROJECT_NAME}" "${G_WATCHDOG_MAIL}")"
                if ! bash "${G_INSTALL_DIRECTORY}/service/cron/watchdogs/send.sh"; then
                    log_error "${INSTALL_WATCHER}" "log.l-e-mail-of-test-toward-was-not-accepted-by-post" "${G_WATCHDOG_MAIL}"
                fi
                log_success "${INSTALL_WATCHER}" "log.e-mail-of-test-sent-to" "${G_WATCHDOG_MAIL}"
            else
                log_info "${INSTALL_WATCHER}" "log.alerts-e-mail-off-no-message-of-end-not-is-sent"
            fi
            ;;
        reboot-notice)
            set_step_hidden "$(get_text run.close.done)"
            log_info "${INSTALL_WATCHER}" "log.journals" "${G_LOG_DIR}"
            log_info "${INSTALL_WATCHER}" "log.lynis-manual-hint"
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

run_install_plan "${G_INSTALL_DIRECTORY}" "${G_INSTALL_DIRECTORY}/script/install.json"
