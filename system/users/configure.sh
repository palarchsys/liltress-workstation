#!/usr/bin/env bash
# =============================================================================
# File       : system/users/configure.sh
# Updated at : 2026-11-17
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Set the workstation account passwords and the sudo timeout.
# Note       : The passwords are mailed and are not written by the log.
# -----------------------------------------------------------------------------


INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info "${INSTALL_WATCHER}" "configure.change-of-the-password-root"
ROOT_PASSWORD=$(openssl rand -hex 32)

apply_password() {
    local user="$1" pw="$2"
    if ! echo "${user}:${pw}" | chpasswd -c YESCRYPT 2>/dev/null; then
        echo "${user}:${pw}" | chpasswd
    fi
}
apply_password root "${ROOT_PASSWORD}"
log_success "${INSTALL_WATCHER}" "configure.password-root-changed"

log_info "${INSTALL_WATCHER}" "configure.change-of-the-password" "${SSH_USER}"
MAIN_PASSWORD=$(openssl rand -hex 32)
apply_password "${SSH_USER}" "${MAIN_PASSWORD}"
log_success "${INSTALL_WATCHER}" "configure.password-changed" "${SSH_USER}"

log_info "${INSTALL_WATCHER}" "configure.addition-of-the-rules-sudoers"
run_silent "${INSTALL_WATCHER}" "configure.users.error" bash -c "echo '${SSH_USER} ALL=(ALL) ALL' > '/etc/sudoers.d/${SSH_USER}'"
chown root:root /etc/sudoers.d
chmod 750 /etc/sudoers.d
chown root:root "/etc/sudoers.d/${SSH_USER}"
chmod 440 "/etc/sudoers.d/${SSH_USER}"
run_silent "${INSTALL_WATCHER}" "configure.users.error" visudo -cf "/etc/sudoers.d/${SSH_USER}"
log_success "${INSTALL_WATCHER}" "configure.rule-sudoers-added-for-required-password" "${SSH_USER}"

cat >/etc/sudoers.d/liltress-timeout <<'EOF'
Defaults timestamp_timeout=5
EOF
chown root:root /etc/sudoers.d/liltress-timeout
chmod 440 /etc/sudoers.d/liltress-timeout
if ! visudo -cf /etc/sudoers.d/liltress-timeout >/dev/null; then
    rm -f /etc/sudoers.d/liltress-timeout
    log_error "${INSTALL_WATCHER}" "configure.sudoers-timeout-invalid-file-removed"
fi
log_success "${INSTALL_WATCHER}" "configure.sudo-asks-again-the-password-after-5-minutes"

HOSTNAME=$(hostname -s 2>/dev/null || hostname)
OBJECT="${PROJECT_NAME} Deployment : ${HOSTNAME} / Users"
TITLE="Workstation Deployment"
MODULE_NAME="Users Credentials"
export OBJECT TITLE MODULE_NAME

# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/core/mail/mail.sh"
write_account_mail "${SSH_USER}"
send_install_mail

unset ROOT_PASSWORD
unset MAIN_PASSWORD
