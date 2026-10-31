#!/usr/bin/env bash
# =============================================================================
# File       : system/sysctl/configure.sh
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
# shellcheck disable=SC2155
readonly DIR_SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

log_subtitle     "${INSTALL_WATCHER}" "configure.sysctl-workstation"
log_info         "${INSTALL_WATCHER}" "configure.ipv6-and-user-namespaces-active"

ip_forward=1
rp_filter=2
log_info         "${INSTALL_WATCHER}" "configure.application-of-the-sysctl-ip-forward-1-rp-filter"

tee /etc/sysctl.d/90-liltress-workstation.conf > /dev/null << EOF

net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.proxy_arp = 0
net.ipv4.conf.default.proxy_arp = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = ${rp_filter}
net.ipv4.conf.default.rp_filter = ${rp_filter}
net.ipv4.ip_forward = ${ip_forward}
net.ipv4.conf.all.forwarding = ${ip_forward}

net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

net.core.bpf_jit_harden = 2

kernel.sysrq = 0
kernel.ctrl-alt-del = 0
kernel.unprivileged_bpf_disabled = 1
kernel.perf_event_paranoid = 3
kernel.randomize_va_space = 2
kernel.core_uses_pid = 1
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
kernel.kexec_load_disabled = 1
fs.suid_dumpable = 0
fs.protected_fifos = 2
fs.protected_regular = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
dev.tty.ldisc_autoload = 0
EOF

cp -f /etc/sysctl.d/90-liltress-workstation.conf /etc/sysctl.d/99-zzz-liltress-workstation.conf
chmod 644 /etc/sysctl.d/90-liltress-workstation.conf /etc/sysctl.d/99-zzz-liltress-workstation.conf
install -d -m 755 "${G_CONFIG_BASE_DIRECTORY}/cron/bin"
install -m 755 "${DIR_SCRIPT_PATH}/w-sysctl-apply.sh" \
    "${G_CONFIG_BASE_DIRECTORY}/cron/bin/w-sysctl-apply.sh"
sed "s|__HF_BASE__|${G_CONFIG_BASE_DIRECTORY}|g" "$(locate_config_file system/sysctl.service)" \
    > /etc/systemd/system/liltress-workstation-sysctl.service

rm -f /etc/systemd/system/docker.service.wants/liltress-workstation-sysctl.service
rm -f /etc/systemd/system/libvirtd.service.wants/liltress-workstation-sysctl.service
run_silent       "${INSTALL_WATCHER}" "configure.sysctl.error" systemctl daemon-reload
run_silent       "${INSTALL_WATCHER}" "configure.sysctl.error" systemctl enable --now liltress-workstation-sysctl.service
run_silent       "${INSTALL_WATCHER}" "configure.sysctl.error" sysctl --system
log_success      "${INSTALL_WATCHER}" "configure.sysctl-applied"
