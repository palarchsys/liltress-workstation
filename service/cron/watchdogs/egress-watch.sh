#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/egress-watch.sh
# Updated at : 2026-11-04
# Creator    : palarchsys
# =============================================================================

locate_python_dir() {
    local dir hops=0 candidate
    for candidate in \
        "${CONFIG_BASE_DIRECTORY:-}/python" \
        "${BASE:-}/python" \
        "${INSTALL_DIRECTORY:-}/python" \
        "${INSTALL_DIRECTORY:-}/../share/python"
    do
        if [[ -n "${candidate}" && -d "${candidate}" ]]; then
            (cd -- "${candidate}" && pwd -P)
            return 0
        fi
    done
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -d "${dir}/share/python" ]]; then
            printf '%s\n' "${dir}/share/python"
            return 0
        fi
        if [[ -d "${dir}/python" ]]; then
            (cd -- "${dir}/python" && pwd -P)
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

# -----------------------------------------------------------------------------
# Note       : The stamp lives under the Liltress cron directory.
# Note       : The first pass writes the stamp and stays silent.
# Note       : A temporary or quarantined executable holds that one destination.
# -----------------------------------------------------------------------------

set -euo pipefail
BASE="${BASE:-/opt/liltress-workstation}"
# shellcheck disable=SC1091
source "${BASE}/cron/bin/common.sh"
if [[ -f "${BASE}/cron/egress.conf" ]]; then
    # shellcheck disable=SC1091
    source "${BASE}/cron/egress.conf"
fi
LOG_FILE="${LOG_DIR}/egress-${STAMP}.log"
ALERT_FILE="${ALERT_DIR}/egress-${STAMP}.txt"
MODULE_NAME="Ufw"

if ! command -v journalctl >/dev/null 2>&1; then
    log_pass "$(get_text watchdog.journalctl-absent)"
    exit 0
fi

if declare -F watchdog_runtime_file >/dev/null 2>&1; then
    stamp="$(watchdog_runtime_file "${BASE}" egress.stamp)"
else
    stamp="${BASE}/cron/egress.stamp"
fi

record_egress_stamp() {
    local moment
    moment="$(date '+%Y-%m-%d %H:%M:%S')"
    install -d -m 750 "${BASE}/cron"
    printf '%s\n' "${moment}" > "${stamp}"
    chmod 600 "${stamp}"
}

get_egress_field() {
    local line="$1"
    local key="$2"
    local chunk="${line}"
    chunk="${chunk#*${key}=}"
    if [[ "${chunk}" == "${line}" ]]; then
        printf "$(get_text log.n)"
        return 0
    fi
    printf '%s\n' "${chunk%%[[:space:]]*}"
}

# Quiet when the flow is time sync, mDNS multicast, DHCP, or broadcast SNMP.
check_egress_routine() {
    local line="$1"
    local proto dpt spt dst folded
    proto="$(get_egress_field "${line}" PROTO)"
    dpt="$(get_egress_field "${line}" DPT)"
    spt="$(get_egress_field "${line}" SPT)"
    dst="$(get_egress_field "${line}" DST)"
    proto="${proto^^}"
    folded="${dst,,}"
    case "${proto}:${dpt}" in
        UDP:123|TCP:4460)
            return 0
            ;;
    esac
    if [[ "${proto}" == "UDP" && "${spt}" == "68" && "${dpt}" == "67" ]]; then
        return 0
    fi
    if [[ "${proto}" == "UDP" && "${spt}" == "546" && "${dpt}" == "547" ]]; then
        return 0
    fi
    if [[ "${proto}" == "UDP" && "${dpt}" == "5353" ]]; then
        case "${folded}" in
            224.0.0.251|ff02::fb|ff02::00fb|ff02:0:0:0:0:0:0:fb|ff02:0000:0000:0000:0000:0000:0000:00fb)
                return 0
                ;;
        esac
    fi
    if [[ "${proto}" == "UDP" && "${dpt}" == "161" ]]; then
        if [[ "${dst}" == "255.255.255.255" ]]; then
            return 0
        fi
        if [[ "${dst}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.255$ ]]; then
            return 0
        fi
        if [[ "${dst}" =~ ^22[4-9]\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            return 0
        fi
        if [[ "${dst}" =~ ^23[0-9]\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            return 0
        fi
    fi
    return 1
}

strip_egress_routine() {
    local source="$1"
    local kept="$2"
    local line
    : > "${kept}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == *w-egress* ]] && check_egress_routine "${line}"; then
            continue
        fi
        printf '%s\n' "${line}" >> "${kept}"
    done < "${source}"
}

get_isolate_seconds() {
    local sec="${NET_ISOLATE_SEC:-120}"
    if [[ ! "${sec}" =~ ^[0-9]+$ ]] || [[ "${sec}" -lt 30 ]] || [[ "${sec}" -gt 300 ]]; then
        sec=120
    fi
    printf '%s\n' "${sec}"
}

list_egress_suspects() {
    local kernel="$1"
    local audit="$2"
    local registry="$3"
    EGRESS_KERNEL="${kernel}" EGRESS_AUDIT="${audit}" EGRESS_REGISTRY="${registry}" python3 "$(locate_python_dir)/egress-body.py" watch
}

ensure_egress_hold() {
    if nft list table inet w_flow_hold >/dev/null 2>&1; then
        return 0
    fi
    nft add table inet w_flow_hold || return 1
    nft add set inet w_flow_hold v4 '{ type ipv4_addr . inet_proto . inet_service; flags timeout; }' || return 1
    nft add set inet w_flow_hold v6 '{ type ipv6_addr . inet_proto . inet_service; flags timeout; }' || return 1
    nft add chain inet w_flow_hold output '{ type filter hook output priority -10 ; policy accept ; }' || return 1
    nft add rule inet w_flow_hold output ip daddr . meta l4proto . th dport @v4 reject || return 1
    nft add rule inet w_flow_hold output ip6 daddr . meta l4proto . th dport @v6 reject || return 1
}

install_egress_hold() {
    local dst="$1"
    local proto="$2"
    local dpt="$3"
    local sec="$4"
    local set_name="v4"
    local lower="${proto,,}"
    [[ "${lower}" == "tcp" || "${lower}" == "udp" ]] || return 1
    [[ "${dpt}" =~ ^[0-9]+$ ]] || return 1
    [[ -n "${dst}" ]] || return 1
    if [[ "${dst}" == *:* ]]; then
        set_name="v6"
    fi
    ensure_egress_hold || return 1
    nft add element inet w_flow_hold "${set_name}" "{ ${dst} . ${lower} . ${dpt} timeout ${sec}s }"
}

if [[ ! -s "${stamp}" ]] || ! grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' "${stamp}"; then
    record_egress_stamp
    log_pass "$(get_text watchdog.initial-rep-re-written)"
    exit 0
fi

install -d -m 755 /run/liltress-workstation
found="$(mktemp -p /run/liltress-workstation)"
audit_tmp="$(mktemp -p /run/liltress-workstation)"
kept="$(mktemp -p /run/liltress-workstation)"
suspects="$(mktemp -p /run/liltress-workstation)"
blocked_lines="$(mktemp -p /run/liltress-workstation)"
trap 'rm -f "${found}" "${audit_tmp}" "${kept}" "${suspects}" "${blocked_lines}"' EXIT
start="$(head -n 1 "${stamp}")"
journalctl -k --since "${start}" -g 'w-egress' --no-pager > "${found}" 2>/dev/null || true
strip_egress_routine "${found}" "${kept}"
mv -f "${kept}" "${found}"
record_egress_stamp
if ! grep -q 'w-egress' "${found}"; then
    log_pass "$(get_text watchdog.no-flow-outbound-unexpected)"
    exit 0
fi
if command -v ausearch >/dev/null 2>&1; then
    formatted="$(date -d "${start}" '+%m/%d/%Y %H:%M:%S' 2>/dev/null || true)"
    if [[ -n "${formatted}" ]]; then
        # shellcheck disable=SC2086
        ausearch -k w-egress --start ${formatted} > "${audit_tmp}" 2>/dev/null || true
    fi
fi
if declare -F watchdog_runtime_file >/dev/null 2>&1; then
    registry="$(watchdog_runtime_file "${BASE}" quarantine.registry)"
else
    registry="${BASE}/cron/quarantine.registry"
fi
list_egress_suspects "${found}" "${audit_tmp}" "${registry}" > "${suspects}" || true
if [[ ! -s "${suspects}" ]]; then
    log_pass "$(get_text watchdog.no-flow-suspicious-outbound)"
    exit 0
fi
sec="$(get_isolate_seconds)"
declare -A held_flows=()
blocked=0
while IFS=$'\t' read -r proto dst dpt exe kline || [[ -n "${proto}" ]]; do
    [[ -n "${proto}" && -n "${dst}" && -n "${dpt}" ]] || continue
    flow_key="${proto}|${dst}|${dpt}"
    if [[ -z "${held_flows[${flow_key}]:-}" ]]; then
        if install_egress_hold "${dst}" "${proto}" "${dpt}" "${sec}"; then
            held_flows["${flow_key}"]=1
            blocked=1
            printf '%s\n' "$(get_text watchdog.blocked-during-s "${dst}" "${proto,,}" "${dpt}" "${sec}" "${exe}")" >> "${LOG_FILE}"
        fi
    fi
    if [[ -n "${held_flows[${flow_key}]:-}" ]]; then
        printf '%s\n' "${kline}" >> "${blocked_lines}"
    fi
done < "${suspects}"
if [[ "${blocked}" -eq 0 ]]; then
    log_pass "$(get_text watchdog.block-rejected)"
    exit 0
fi
if declare -F render_egress_body >/dev/null 2>&1; then
    render_egress_body "${blocked_lines}" "${audit_tmp}" >> "${LOG_FILE}" || true
else
    cat "${blocked_lines}" >> "${LOG_FILE}"
fi
log_alert "$(get_text watchdog.flow-outbound-suspicious-blocked)"
exit 0
