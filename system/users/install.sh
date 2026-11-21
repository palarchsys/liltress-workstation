#!/usr/bin/env bash
# =============================================================================
# File       : system/users/install.sh
# Updated at : 2026-11-17
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Create the workstation SSH group and account.
# -----------------------------------------------------------------------------


INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root

log_info "${INSTALL_WATCHER}" "log.check-of-the-user" "${SSH_USER}"
if ! getent group "${SSH_GROUP}" >/dev/null 2>&1; then
    run_silent "${INSTALL_WATCHER}" "install.users.error" groupadd "${SSH_GROUP}"
fi
if ! getent passwd "${SSH_USER}" >/dev/null 2>&1; then
    log_info "${INSTALL_WATCHER}" "log.creation-of" "${SSH_USER}"
    run_silent "${INSTALL_WATCHER}" "install.users.error" useradd -m -s /bin/bash -g "${SSH_GROUP}" "${SSH_USER}"
    log_success "${INSTALL_WATCHER}" "log.user-created" "${SSH_USER}"
else
    primary="$(id -gn "${SSH_USER}")"
    if [[ "${primary}" != "${SSH_GROUP}" ]]; then
        run_silent "${INSTALL_WATCHER}" "install.users.error" usermod -g "${SSH_GROUP}" "${SSH_USER}"
    fi
    log_success "${INSTALL_WATCHER}" "install.exists-already-password-unchanged" "${SSH_USER}"
fi
