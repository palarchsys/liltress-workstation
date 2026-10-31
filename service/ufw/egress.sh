#!/usr/bin/env bash
# =============================================================================
# File       : service/ufw/egress.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================
# -----------------------------------------------------------------------------
# Note       : The log table is installed on every configure.
# Note       : The outbound policy stays allow.
# -----------------------------------------------------------------------------

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY
G_INSTALL_DIRECTORY="${INSTALL_DIRECTORY}"
export G_INSTALL_DIRECTORY

source "${G_INSTALL_DIRECTORY}/core/lib.sh"
source "${G_INSTALL_DIRECTORY}/config/global.conf"
require_root
# shellcheck disable=SC1091
source "$(locate_config_file ufw/egress.conf)"

install -d -m 750 "${G_CONFIG_BASE_DIRECTORY}/cron"
umask 077
cat > "${G_CONFIG_BASE_DIRECTORY}/cron/egress.conf" << EOF
W_NET_ISOLATE_SEC=${W_NET_ISOLATE_SEC}
EOF
umask 022
chmod 600 "${G_CONFIG_BASE_DIRECTORY}/cron/egress.conf"

install -d -m 755 "${G_CONFIG_BASE_DIRECTORY}/cron/bin"
cat > "${G_CONFIG_BASE_DIRECTORY}/cron/bin/egress-table.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
command -v nft >/dev/null 2>&1 || exit 0
nft delete table inet w_egress >/dev/null 2>&1 || true
nft add table inet w_egress
nft add chain inet w_egress output '{ type filter hook output priority 0 ; policy accept ; }'
nft add rule inet w_egress output ct state established,related accept
nft add rule inet w_egress output ip daddr 127.0.0.0/8 accept
nft add rule inet w_egress output ip6 daddr ::1 accept
nft add rule inet w_egress output meta l4proto '{ tcp, udp }' th dport '{ 53, 80, 443 }' accept
# Workstation baseline: time sync, link-local discovery, DHCP. Other TCP/UDP stays logged.
nft add rule inet w_egress output meta l4proto udp th dport 123 accept
nft add rule inet w_egress output meta l4proto tcp th dport 4460 accept
nft add rule inet w_egress output ip daddr 224.0.0.251 meta l4proto udp th dport 5353 accept
nft add rule inet w_egress output ip6 daddr ff02::fb meta l4proto udp th dport 5353 accept
nft add rule inet w_egress output meta l4proto udp th sport 68 th dport 67 accept
nft add rule inet w_egress output meta l4proto udp th sport 546 th dport 547 accept
nft add rule inet w_egress output meta l4proto udp th dport 161 meta pkttype '{ broadcast, multicast }' accept
nft add rule inet w_egress output meta l4proto '{ tcp, udp }' limit rate 30/minute log prefix 'w-egress '
EOF
chmod 755 "${G_CONFIG_BASE_DIRECTORY}/cron/bin/egress-table.sh"
cat > /etc/systemd/system/w-egress-table.service << EOF
[Unit]
Description=Pose le journal des flux sortants
After=ufw.service
Before=w-boot-chain.service

[Service]
Type=oneshot
ExecStart=${G_CONFIG_BASE_DIRECTORY}/cron/bin/egress-table.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
chmod 644 /etc/systemd/system/w-egress-table.service
run_silent "${INSTALL_WATCHER}" "install.ufw.error" systemctl daemon-reload
run_silent "${INSTALL_WATCHER}" "install.ufw.error" systemctl enable w-egress-table.service

if ! command -v nft >/dev/null 2>&1; then
    log_warn "${INSTALL_WATCHER}" "log.nft-absent-journal-of-the-flow-outbound-not-inst"
    exit 0
fi
log_info "${INSTALL_WATCHER}" "log.install-of-the-journal-of-the-flow-outbound"
bash "${G_CONFIG_BASE_DIRECTORY}/cron/bin/egress-table.sh"
log_success "${INSTALL_WATCHER}" "log.journal-of-the-flow-active-outbound"
