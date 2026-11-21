#!/usr/bin/env bash
# =============================================================================
# File       : service/unbound/dns.sh
# Updated at : 2026-11-21
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Point local resolvers at the recursive service, or put the old settings back.
# Note       : Nothing is removed when the resolver port is open.
# -----------------------------------------------------------------------------


check_unbound_port() {
    timeout 1 bash -c ':</dev/tcp/127.0.0.1/53' >/dev/null 2>&1
}

# A present override file marks the network as changed.
mark_dns_override_files() {
    local path
    for path in \
        /etc/systemd/resolved.conf.d/90-liltress-workstation.conf \
        /etc/NetworkManager/conf.d/90-liltress-workstation-dns.conf \
        /etc/NetworkManager/dispatcher.d/10-liltress-workstation-dns; do
        if [[ -e "${path}" ]]; then
            changed=1
        fi
    done
}

# A connection that still points at the local resolver is collected.
collect_dns_connections() {
    local uuid ctype dns
    if command -v nmcli >/dev/null 2>&1; then
        while IFS=: read -r uuid ctype; do
            [[ -n "${uuid}" ]] || continue
            case "${ctype}" in
                802-3-ethernet | 802-11-wireless | gsm | cdma) ;;
                *) continue ;;
            esac
            dns="$(nmcli -g ipv4.dns connection show "${uuid}" 2>/dev/null || true)"
            case "${dns}" in
                *127.0.0.1*)
                    uuids+=("${uuid}")
                    changed=1
                    ;;
            esac
        done < <(nmcli -t -f UUID,TYPE connection show 2>/dev/null || true)
    fi
}

# The override files are removed before the connections are edited.
remove_dns_override_files() {
    local path
    for path in \
        /etc/systemd/resolved.conf.d/90-liltress-workstation.conf \
        /etc/NetworkManager/conf.d/90-liltress-workstation-dns.conf \
        /etc/NetworkManager/dispatcher.d/10-liltress-workstation-dns; do
        rm -f "${path}"
    done
}

# Each saved connection loses the local resolver address.
clear_dns_connections() {
    local uuid
    for uuid in "${uuids[@]}"; do
        nmcli connection modify "${uuid}" \
            ipv4.ignore-auto-dns no \
            ipv6.ignore-auto-dns no \
            ipv4.dns "" \
            ipv6.dns "" \
            >/dev/null 2>&1 || true
    done
}

# Connected devices receive the restored resolver.
refresh_dns_devices() {
    local dev dtype state
    if command -v nmcli >/dev/null 2>&1; then
        while IFS=: read -r dev dtype state; do
            [[ "${state}" == "connected" ]] || continue
            case "${dtype}" in
                ethernet | wifi | gsm)
                    nmcli device reapply "${dev}" >/dev/null 2>&1 || true
                    ;;
            esac
        done < <(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null || true)
    fi
}

clear_dns_override() {
    local changed=0
    local -a uuids=()
    if check_unbound_port; then
        return 0
    fi
    mark_dns_override_files
    collect_dns_connections
    [[ "${changed}" -eq 1 ]] || return 0
    log_info "${INSTALL_WATCHER}" "configure.return-to-the-network-dns"
    remove_dns_override_files
    clear_dns_connections
    refresh_dns_devices
    systemctl restart systemd-resolved >/dev/null 2>&1 || true
    log_success "${INSTALL_WATCHER}" "configure.network-dns-restored"
}

# Each matching connection ignores automatic resolvers.
apply_unbound_connections() {
    local uuid ctype
    if command -v nmcli >/dev/null 2>&1; then
        while IFS=: read -r uuid ctype; do
            [[ -n "${uuid}" ]] || continue
            case "${ctype}" in
                802-3-ethernet | 802-11-wireless | gsm | cdma)
                    run_optional "${INSTALL_WATCHER}" "configure.unbound.error.3" nmcli connection modify "${uuid}" \
                        ipv4.ignore-auto-dns yes \
                        ipv6.ignore-auto-dns yes \
                        ipv4.dns 127.0.0.1
                    ;;
            esac
        done < <(nmcli -t -f UUID,TYPE connection show 2>/dev/null || true)
    fi
}

# Each connected device receives the local resolver.
apply_unbound_devices() {
    local dev dtype
    if command -v nmcli >/dev/null 2>&1; then
        while IFS=: read -r dev dtype; do
            [[ -n "${dev}" ]] || continue
            case "${dtype}" in
                ethernet | wifi | gsm)
                    run_optional "${INSTALL_WATCHER}" "configure.unbound.error.11" resolvectl dns "${dev}" 127.0.0.1
                    ;;
            esac
        done < <(nmcli -t -f DEVICE,TYPE device status 2>/dev/null || true)
    fi
}

apply_unbound_dns() {
    local script_dir
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
    ensure_directory /etc/systemd/resolved.conf.d 755
    grep -v '^#' "$(locate_config_file service/unbound/resolved.conf)" >/etc/systemd/resolved.conf.d/90-liltress-workstation.conf
    chmod 644 /etc/systemd/resolved.conf.d/90-liltress-workstation.conf
    ensure_directory /etc/NetworkManager/conf.d 755
    grep -v '^#' "$(locate_config_file service/unbound/networkmanager.conf)" >/etc/NetworkManager/conf.d/90-liltress-workstation-dns.conf
    chmod 644 /etc/NetworkManager/conf.d/90-liltress-workstation-dns.conf
    install -d -m 755 /etc/NetworkManager/dispatcher.d
    install -m 755 "${script_dir}/nm-dispatcher.sh" \
        /etc/NetworkManager/dispatcher.d/10-liltress-workstation-dns
    apply_unbound_connections
    run_optional "${INSTALL_WATCHER}" "configure.unbound.error.9" systemctl restart systemd-resolved.service
    run_optional "${INSTALL_WATCHER}" "configure.unbound.error.10" systemctl reload NetworkManager
    apply_unbound_devices
    run_optional "${INSTALL_WATCHER}" "configure.unbound.error.12" resolvectl flush-caches
}
