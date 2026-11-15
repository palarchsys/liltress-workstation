#!/usr/bin/env bash
# =============================================================================
# File       : service/unbound/configure.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
source "${INSTALL_DIRECTORY}/config/global.conf"
source "${INSTALL_DIRECTORY}/service/unbound/dns.sh"
require_root

log_info         "${INSTALL_WATCHER}" "configure.configuration-of-unbound"

if [[ ! -f /usr/share/dns/root.hints ]]; then
    log_error        "${INSTALL_WATCHER}" "configure.dns-root-data-is-incomplete-usr-share-dns-root-h"
fi

ensure_directory /etc/unbound/unbound.conf.d 755
install -m 644 "$(locate_config_file unbound/resolver.conf)" /etc/unbound/unbound.conf.d/liltress-workstation.conf

grep -v '^#' "$(locate_config_file unbound/default.conf)" > /etc/default/unbound
chmod 644 /etc/default/unbound
if [[ -f /etc/resolvconf/update.d/unbound ]]; then
    chmod a-x /etc/resolvconf/update.d/unbound
fi

check_out="$(unbound-checkconf 2>&1)" || log_error        "${INSTALL_WATCHER}" "configure.unbound-checkconf-refuses-the-configuration" "${check_out}"

ensure_directory /etc/systemd/system/systemd-resolved.service.d 755
grep -v '^#' "$(locate_config_file unbound/resolved-service.conf)" > /etc/systemd/system/systemd-resolved.service.d/90-liltress-workstation.conf
chmod 644 /etc/systemd/system/systemd-resolved.service.d/90-liltress-workstation.conf

ensure_directory /etc/systemd/system/unbound.service.d 755
grep -v '^#' "$(locate_config_file unbound/service.conf)" > /etc/systemd/system/unbound.service.d/90-liltress-workstation.conf
chmod 644 /etc/systemd/system/unbound.service.d/90-liltress-workstation.conf

install -m 644 "$(locate_config_file unbound/root-hints.service)" /etc/systemd/system/w-unbound-root-hints.service
install -m 644 "$(locate_config_file unbound/root-hints.path)" /etc/systemd/system/w-unbound-root-hints.path

run_optional     "${INSTALL_WATCHER}" "configure.unbound.error.4" systemctl disable --now unbound-resolvconf.service
run_silent       "${INSTALL_WATCHER}" "configure.unbound.error.5" systemctl daemon-reload
run_silent       "${INSTALL_WATCHER}" "configure.unbound.error.6" systemctl enable unbound.service
run_silent       "${INSTALL_WATCHER}" "configure.unbound.error.7" systemctl restart unbound.service
run_silent       "${INSTALL_WATCHER}" "configure.unbound.error.8" systemctl enable --now w-unbound-root-hints.path

ready=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if unbound-control status >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 1
done
if [[ "${ready}" -ne 1 ]]; then
    clear_dns_override
    log_error        "${INSTALL_WATCHER}" "configure.unbound-is-not-ready-after-the-start-of-the-serv"
fi
apply_unbound_dns

resolved=0
query_out=""
for _ in 1 2 3 4 5; do
    query_out="$(resolvectl query ubuntu.com 2>&1)" && {
        resolved=1
        break
    }
    sleep 2
done
if [[ "${resolved}" -ne 1 ]]; then
    log_error        "${INSTALL_WATCHER}" "configure.the-resolution-local-via-unbound-a-failed" "${query_out}"
fi

log_success      "${INSTALL_WATCHER}" "configure.unbound-configured-resolution-on-the-workstation"
