#!/usr/bin/env bash
# =============================================================================
# File       : service/aide/configure.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Install the workstation integrity configuration and record the home directory.
# -----------------------------------------------------------------------------


# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../core/boot/python.sh"

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

# shellcheck disable=SC2155
readonly DIR_SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
require_root
get_current_user

log_info "${INSTALL_WATCHER}" "configure.configuration-of-help-2"
ensure_directory /etc/aide 755
ensure_directory /var/lib/aide 700
sed "s|__HF_BASE__|${CONFIG_BASE_DIRECTORY}|g" "$(locate_config_file service/aide/aide.conf)" >/etc/aide/aide.conf
python3 "$(locate_python_directory)/aide-home.py" workstation /etc/aide/aide.conf "${CURRENT_HOME}"
python3 "$(locate_python_directory)/exclusions.py" splice /etc/aide/aide.conf "${CONFIG_BASE_DIRECTORY}/config/service/exclusions/generated/aide.rules"
log_success "${INSTALL_WATCHER}" "configure.help-conf-installed"
log_info "${INSTALL_WATCHER}" "configure.base-help-after-the-purge-of-the-packages-and-rk"
