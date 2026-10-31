#!/usr/bin/env bash
# =============================================================================
# File       : service/auditd/configure.sh
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
get_current_user

log_subtitle     "${INSTALL_WATCHER}" "configure.configuration-auditd-2"
log_info         "${INSTALL_WATCHER}" "configure.configuration-of-auditd"

install -d -m 750 /etc/audit/rules.d
rm -f /etc/audit/rules.d/"${W_PROJECT_SLUG}".rules

write_audit_watch() {
    local path="$1" key="$2" field="dir"
    [[ -d "${path}" ]] || field="path"
    printf '%s\n' "-a always,exit -F arch=b64 -F ${field}=${path} -F perm=wa -F key=${key}"
}
grep -v '^#' "$(locate_config_file auditd/prelude.rules)" > /etc/audit/rules.d/00-liltress-workstation.rules

write_audit_list() {
    local profile path key
    while read -r profile path key; do
        [[ -n "${profile}" && "${profile}" != \#* ]] || continue
        case "${profile}" in
            any) ;;
            virt) check_virtual_machine || continue ;;
            *) continue ;;
        esac
        path="${path//__HF_BASE__/${G_CONFIG_BASE_DIRECTORY}}"
        write_audit_watch "${path}" "${key}"
    done < "$(locate_config_file auditd/watches.list)"
}
{
    write_audit_list
    for account_path in \
        "${CURRENT_HOME}/.ssh/authorized_keys" \
        "${CURRENT_HOME}/.bashrc" \
        "${CURRENT_HOME}/.profile" \
        "${CURRENT_HOME}/.bash_profile" \
        "${CURRENT_HOME}/.config/autostart" \
        "${CURRENT_HOME}/.config/systemd/user"
    do
        [[ -e "${account_path}" ]] || continue
        write_audit_watch "${account_path}" account
    done
    grep -v '^#' "$(locate_config_file auditd/tail.rules)"
} > /etc/audit/rules.d/50-liltress-workstation.rules
grep -v '^#' "$(locate_config_file auditd/enable.rules)" > /etc/audit/rules.d/99-liltress-workstation.rules
chmod 640 /etc/audit/rules.d/00-liltress-workstation.rules \
    /etc/audit/rules.d/50-liltress-workstation.rules \
    /etc/audit/rules.d/99-liltress-workstation.rules

run_silent       "${INSTALL_WATCHER}" "configure.auditd.error" systemctl enable auditd
if ! systemctl is-active --quiet auditd; then
    run_silent       "${INSTALL_WATCHER}" "configure.auditd.error" systemctl start auditd
fi

run_silent       "${INSTALL_WATCHER}" "configure.auditd.error" augenrules --load
log_success      "${INSTALL_WATCHER}" "configure.auditd-enabled-2"
