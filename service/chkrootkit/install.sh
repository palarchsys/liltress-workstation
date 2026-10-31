#!/usr/bin/env bash
# =============================================================================
# File       : service/chkrootkit/install.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY
G_INSTALL_DIRECTORY="${INSTALL_DIRECTORY}"
export G_INSTALL_DIRECTORY

# shellcheck disable=SC2155
readonly DIR_SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${G_INSTALL_DIRECTORY}/core/lib.sh"
source "${G_INSTALL_DIRECTORY}/config/global.conf"
require_root

log_subtitle     "${INSTALL_WATCHER}" "install.installation-chkrootkit"
log_info         "${INSTALL_WATCHER}" "install.installation-of-chkrootkit-2"
run_silent_apt   "${INSTALL_WATCHER}" "install -y chkrootkit" "install.chkrootkit.error"
install -d -m 755 "${G_CONFIG_BASE_DIRECTORY}/bin"
install -m 755 "${DIR_SCRIPT_PATH}/ignore-log.sh" "${G_CONFIG_BASE_DIRECTORY}/bin/chkrootkit-ignore-log.sh"
ignore_src="$(locate_config_file chkrootkit/patterns.ignore || true)"
ignore_dest="${G_CONFIG_BASE_DIRECTORY}/src/config/chkrootkit/patterns.ignore"
if [[ -z "${ignore_src}" || ! -f "${ignore_src}" ]]; then
    log_error        "${INSTALL_WATCHER}" "install.list-chkrootkit-not-found"
fi
if [[ "${ignore_src}" != "${ignore_dest}" ]]; then
    install -d -m 755 "${G_CONFIG_BASE_DIRECTORY}/src/config/chkrootkit"
    install -m 664 "${ignore_src}" "${ignore_dest}"
fi
log_success      "${INSTALL_WATCHER}" "install.chkrootkit-installed-2"
