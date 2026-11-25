#!/usr/bin/env bash
# =============================================================================
# File       : service/aide/configure.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Install the workstation integrity configuration and record the home directory.
# -----------------------------------------------------------------------------


source_python_boot() {
    local dir hops
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    hops=0
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -f "${dir}/core/boot/python.sh" ]]; then
            # shellcheck disable=SC1090
            source "${dir}/core/boot/python.sh"
            return 0
        fi
        if [[ -f "${dir}/share/core/boot/python.sh" ]]; then
            # shellcheck disable=SC1090
            source "${dir}/share/core/boot/python.sh"
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

source_python_boot

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
python3 "$(locate_python_dir)/aide-home.py" workstation /etc/aide/aide.conf "${CURRENT_HOME}"
python3 "$(locate_python_dir)/exclusions.py" splice /etc/aide/aide.conf "${CONFIG_BASE_DIRECTORY}/config/service/exclusions/generated/aide.rules"
log_success "${INSTALL_WATCHER}" "configure.help-conf-installed"
log_info "${INSTALL_WATCHER}" "configure.base-help-after-the-purge-of-the-packages-and-rk"
