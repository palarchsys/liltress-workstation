#!/usr/bin/env bash
# =============================================================================
# File       : service/fail2ban/configure.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY
G_INSTALL_DIRECTORY="${INSTALL_DIRECTORY}"
export G_INSTALL_DIRECTORY

source "${G_INSTALL_DIRECTORY}/core/lib.sh"
source "${G_INSTALL_DIRECTORY}/config/global.conf"
require_root
get_ssh_port

log_subtitle     "${INSTALL_WATCHER}" "configure.configuration-fail2ban"
log_info         "${INSTALL_WATCHER}" "configure.configuration-of-fail2ban"
envsubst '$SSH_PORT' < "$(locate_config_file fail2ban/jail.local)" > /etc/fail2ban/jail.local
chmod 644 /etc/fail2ban/jail.local
log_success      "${INSTALL_WATCHER}" "configure.jail-local-installed-sshd-port" "${SSH_PORT}"

log_info         "${INSTALL_WATCHER}" "configure.activation-of-fail2ban"
run_silent       "${INSTALL_WATCHER}" "configure.fail2ban.error" systemctl enable --now fail2ban
run_optional     "${INSTALL_WATCHER}" "configure.fail2ban.error" fail2ban-client reload
log_success      "${INSTALL_WATCHER}" "configure.fail2ban-enabled"
