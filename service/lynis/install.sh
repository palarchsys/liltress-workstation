#!/usr/bin/env bash
# =============================================================================
# File       : service/lynis/install.sh
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
log_subtitle     "${INSTALL_WATCHER}" "install.repository-lynis-cisofy"
log_info         "${INSTALL_WATCHER}" "install.creation-of-etc-apt-keyrings"
ensure_directory /etc/apt/keyrings 755

LYNIS_KEY="/etc/apt/keyrings/cisofy-software.gpg"
LYNIS_LIST="/etc/apt/sources.list.d/lynis.list"

if ! check_repository_key "${LYNIS_KEY}"; then
    rm -f -- "${LYNIS_KEY}"
    log_info         "${INSTALL_WATCHER}" "install.download-of-the-key-gpg-lynis"
    install_repository_key "https://packages.cisofy.com/keys/cisofy-software-public.key" "${LYNIS_KEY}"
    log_success      "${INSTALL_WATCHER}" "install.key-gpg-lynis-installed"
fi

log_info         "${INSTALL_WATCHER}" "install.configuration-of-the-repository-lynis"
tee "${LYNIS_LIST}" > /dev/null << EOF
deb [arch=$(dpkg --print-architecture) signed-by=${LYNIS_KEY}] https://packages.cisofy.com/community/lynis/deb/ stable main
EOF
chmod 644 "${LYNIS_LIST}"
log_success      "${INSTALL_WATCHER}" "install.repository-lynis-configured-sources-ubuntu-not-c"

log_subtitle     "${INSTALL_WATCHER}" "log.lynis"
log_info         "${INSTALL_WATCHER}" "install.installation-of-lynis"
run_silent_apt   "${INSTALL_WATCHER}" "install -y lynis --no-install-recommends" "install.lynis.error"
log_success      "${INSTALL_WATCHER}" "install.lynis-installed"
