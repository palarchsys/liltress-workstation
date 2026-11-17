#!/usr/bin/env bash
# =============================================================================
# File       : service/aide/configure.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Install the workstation integrity configuration and record the home directory.
# -----------------------------------------------------------------------------


# The caller owns shown_python and reads it after this call.
show_python_directory() {
    local candidate="$1"
    shown_python=0
    [[ -n "${candidate}" && -d "${candidate}" ]] || return 0
    (cd -- "${candidate}" && pwd -P)
    shown_python=1
    return 0
}

# The shared directory is printed as given, without resolving links.
show_share_python() {
    local dir="$1"
    shown_python=0
    if [[ ! -d "${dir}/share/python" ]]; then
        return 0
    fi
    printf '%s\n' "${dir}/share/python"
    shown_python=1
    return 0
}

locate_python_dir() {
    local dir="" hops=0 candidate="" shown_python=0
    for candidate in \
        "${CONFIG_BASE_DIRECTORY:-}/python" \
        "${BASE:-}/python" \
        "${INSTALL_DIRECTORY:-}/python" \
        "${INSTALL_DIRECTORY:-}/../share/python"; do
        show_python_directory "${candidate}"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
    done
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        show_share_python "${dir}"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
        show_python_directory "${dir}/python"
        if [[ "${shown_python}" -eq 1 ]]; then
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

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
sed "s|__HF_BASE__|${CONFIG_BASE_DIRECTORY}|g" "$(locate_config_file aide/aide.conf)" >/etc/aide/aide.conf
python3 "$(locate_python_dir)/aide-home.py" workstation /etc/aide/aide.conf "${CURRENT_HOME}"
log_success "${INSTALL_WATCHER}" "configure.help-conf-installed"
log_info "${INSTALL_WATCHER}" "configure.base-help-after-the-purge-of-the-packages-and-rk"
