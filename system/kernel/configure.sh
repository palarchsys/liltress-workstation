#!/usr/bin/env bash
# =============================================================================
# File       : system/kernel/configure.sh
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
log_info         "${INSTALL_WATCHER}" "configure.tightening-of-the-permissions-of-the-files-read"

apply_strict_mode() {
    local mode="$1" owner="$2" group="$3" path="$4"
    [[ -e "${path}" ]] || return 0
    if dpkg-statoverride --list "${path}" >/dev/null 2>&1; then
        dpkg-statoverride --remove "${path}" >/dev/null 2>&1 || true
    fi
    dpkg-statoverride --update --add "${owner}" "${group}" "${mode}" "${path}" >/dev/null
}
for cron_dir in /etc/cron.d /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly; do
    apply_strict_mode 700 root root "${cron_dir}"
done
apply_strict_mode 600 root root /etc/crontab
apply_strict_mode 600 root root /etc/ssh/sshd_config
apply_strict_mode 750 root root /etc/sudoers.d
tee /etc/tmpfiles.d/liltress-workstation-cron.conf > /dev/null << 'EOF'
z /etc/cron.d 0700 root root -
z /etc/cron.hourly 0700 root root -
z /etc/cron.daily 0700 root root -
z /etc/cron.weekly 0700 root root -
z /etc/cron.monthly 0700 root root -
EOF
log_success      "${INSTALL_WATCHER}" "configure.permissions-cron-sudoers-and-ssh-tightened"
log_subtitle     "${INSTALL_WATCHER}" "configure.modules-protocols-and-systems-of-unused-files"
log_info         "${INSTALL_WATCHER}" "configure.blacklist-of-the-protocols-unused"
tee /etc/modprobe.d/disable-uncommon-protocols.conf > /dev/null << EOF
blacklist dccp
blacklist sctp
blacklist rds
blacklist tipc
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
EOF
log_success      "${INSTALL_WATCHER}" "configure.dccp-sctp-rds-tipc-blacklisted"

log_info         "${INSTALL_WATCHER}" "configure.blacklist-of-the-systems-of-files-unused"
tee /etc/modprobe.d/disable-unused-fs.conf > /dev/null << 'EOF'
install cramfs /bin/true
install freevxfs /bin/true
install hfs /bin/true
install hfsplus /bin/true
install jffs2 /bin/true
install udf /bin/true
blacklist cramfs
blacklist freevxfs
blacklist hfs
blacklist hfsplus
blacklist jffs2
blacklist udf
EOF
log_success      "${INSTALL_WATCHER}" "configure.unused-fs-blacklisted"

rm -f /etc/modules-load.d/kvm.conf

log_subtitle     "${INSTALL_WATCHER}" "configure.core-dumps-disabled"
log_info         "${INSTALL_WATCHER}" "configure.deactivation-of-the-core-dumps"
tee /etc/security/limits.d/90-disable-core.conf > /dev/null << EOF
* soft core 0
* hard core 0
EOF
log_success      "${INSTALL_WATCHER}" "configure.limits-core-0-installed"

log_subtitle     "${INSTALL_WATCHER}" "configure.initramfs"
log_info         "${INSTALL_WATCHER}" "configure.update-of-the-initramfs-modules-blacklist"
run_optional     "${INSTALL_WATCHER}" "configure.kernel.error" update-initramfs -u
log_success      "${INSTALL_WATCHER}" "configure.initramfs-updated-up-to-date-best-effort"

log_success      "${INSTALL_WATCHER}" "configure.configuration-system-workstation-finished"
