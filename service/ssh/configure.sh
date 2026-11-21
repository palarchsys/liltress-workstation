#!/usr/bin/env bash
# =============================================================================
# File       : service/ssh/configure.sh
# Updated at : 2026-11-21
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Write the SSH settings, the login banner, and keep root login off.
# Note       : Root login must stay off after the service is enabled.
# -----------------------------------------------------------------------------


INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

# shellcheck disable=SC2155
readonly DIR_SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"

require_root

log_info "${INSTALL_WATCHER}" "configure.port-detected" "${SSH_PORT}"
log_info "${INSTALL_WATCHER}" "configure.configuration-of-ssh"
install_sshd_dropin "${SSH_USER}" "liltress-workstation"

ensure_directory "$(dirname "${SSH_BANNER_PATH}")" 755
ensure_directory /run/sshd 755
printf '%s\n' "${BANNER_MESSAGE}" >"${SSH_BANNER_PATH}"
chmod 644 "${SSH_BANNER_PATH}"

log_info "${INSTALL_WATCHER}" "configure.ssh.info.3"
if ! sshd -t; then
    log_error "${INSTALL_WATCHER}" "configure.sshd-t-a-failed-drop-in-removed"
fi
root_login="$(get_sshd_value permitrootlogin)"
if [[ "${root_login}" != "no" ]]; then
    log_error "${INSTALL_WATCHER}" "configure.effective-permitrootlogin-expected-no" "${root_login:-inconnu}"
fi

log_info "${INSTALL_WATCHER}" "configure.pass-of-ssh-in-service-not-only-the-activation-b"
run_optional "${INSTALL_WATCHER}" "configure.ssh.error.3" systemctl disable --now ssh.socket
run_optional "${INSTALL_WATCHER}" "configure.ssh.error.4" systemctl unmask "${SSH_SERVICE_NAME}.service"
run_silent "${INSTALL_WATCHER}" "configure.ssh.error.5" systemctl enable --now "${SSH_SERVICE_NAME}.service"
run_silent "${INSTALL_WATCHER}" "configure.ssh.error.6" reload_sshd_unit
log_success "${INSTALL_WATCHER}" "configure.hardened-ssh-root-forbidden-password-kept-port" "${SSH_PORT}"
