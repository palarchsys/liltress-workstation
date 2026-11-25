#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/scan-egress.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Hold a suspicious outbound flow and mail a refused one.
# Note       : The stamp lives under the product cron directory.
# Note       : The opening visit stores the stamp and stays silent.
# Note       : A temporary or quarantined executable holds that one destination.
# Note       : A refused line is mailed when the product key is absent.
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

read_egress_key() {
    local candidate="" line=""
    EGRESS_KEY="w-egress"
    for candidate in \
        "${BASE:-}/config/service/watchdog/egress.keys" \
        "${CONFIG_BASE_DIRECTORY:-}/config/service/watchdog/egress.keys" \
        "${INSTALL_DIRECTORY:-}/config/service/watchdog/egress.keys"; do
        [[ -n "${candidate}" && -f "${candidate}" ]] || continue
        line="$(grep -v '^#' "${candidate}" | head -n 1 || true)"
        [[ -n "${line}" ]] && EGRESS_KEY="${line}"
        return 0
    done
}

report_ufw_blocks() {
    local ufw_file="$1"
    if [[ ! -s "${ufw_file}" ]]; then
        log_pass "$(get_text watchdog.no-flow-outbound-unexpected)"
        return 0
    fi
    if declare -F render_egress_body >/dev/null 2>&1; then
        render_egress_body "${ufw_file}" "${audit_tmp}" >>"${LOG_FILE}" || true
    else
        head -n 40 "${ufw_file}" >>"${LOG_FILE}"
    fi
    log_alert "$(get_text watchdog.flow-outbound-refus-s-by-the-policy-of-output)"
}

load_egress_config() {
    set -euo pipefail
    HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -r "${HERE}/watchdog.conf" ]]; then
        # shellcheck disable=SC1091
        source "${HERE}/watchdog.conf"
    fi
    if [[ -z "${BASE:-}" && -z "${CONFIG_BASE_DIRECTORY:-}" && -n "${CONFIG_BASE_DIRECTORY+x}" ]]; then
        exit 0
    fi
    # shellcheck disable=SC1091
    source "${HERE}/common.sh"
    if [[ -z "${BASE:-}" ]]; then
        BASE="${CONFIG_BASE_DIRECTORY:-/opt/liltress-workstation}"
    fi
    if [[ -f "${BASE}/cron/egress.conf" ]]; then
        # shellcheck disable=SC1091
        source "${BASE}/cron/egress.conf"
    fi
}

set_egress_paths() {
    STAMP="${STAMP:-$(date +%Y%m%d-%H%M%S)}"
    LOG_DIR="${LOG_DIR:-${BASE}/cron/security_logs}"
    ALERT_DIR="${ALERT_DIR:-${BASE}/cron/alerts}"
    mkdir -p -- "${LOG_DIR}" "${ALERT_DIR}"
    LOG_FILE="${LOG_DIR}/egress-${STAMP}.log"
    ALERT_FILE="${ALERT_DIR}/egress-${STAMP}.txt"
    MODULE_NAME="Ufw"
    if ! declare -F log_pass >/dev/null 2>&1; then
        log_pass() { printf '%s\n' "$*"; }
    fi
    read_egress_key
}

require_egress_journal() {
    if ! command -v journalctl >/dev/null 2>&1; then
        log_pass "$(get_text watchdog.journalctl-absent)"
        exit 0
    fi
}

locate_egress_stamp() {
    if declare -F watchdog_runtime_file >/dev/null 2>&1; then
        stamp="$(watchdog_runtime_file "${BASE}" egress.stamp)"
    else
        stamp="${BASE}/cron/egress.stamp"
    fi
}

record_egress_stamp() {
    local moment
    moment="$(date '+%Y-%m-%d %H:%M:%S')"
    mkdir -p -- "$(dirname -- "${stamp}")"
    printf '%s\n' "${moment}" >"${stamp}"
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

# The two time ports stay quiet.
check_egress_time() {
    local proto="$1"
    local dpt="$2"
    case "${proto}:${dpt}" in
        UDP:123 | TCP:4460)
            return 0
            ;;
    esac
    return 1
}

# The two address-lease ports stay quiet.
check_egress_dhcp() {
    local proto="$1"
    local spt="$2"
    local dpt="$3"
    if [[ "${proto}" == "UDP" && "${spt}" == "68" && "${dpt}" == "67" ]]; then
        return 0
    fi
    if [[ "${proto}" == "UDP" && "${spt}" == "546" && "${dpt}" == "547" ]]; then
        return 0
    fi
    return 1
}

# Multicast name lookup on port 5353 stays quiet.
check_egress_multicast() {
    local proto="$1"
    local dpt="$2"
    local folded="$3"
    if [[ "${proto}" == "UDP" && "${dpt}" == "5353" ]]; then
        case "${folded}" in
            224.0.0.251 | ff02::fb | ff02::00fb | ff02:0:0:0:0:0:0:fb | ff02:0000:0000:0000:0000:0000:0000:00fb)
                return 0
                ;;
        esac
    fi
    return 1
}

# Broadcast and multicast SNMP on port 161 stays quiet.
check_egress_broadcast() {
    local proto="$1"
    local dpt="$2"
    local dst="$3"
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
    check_egress_time "${proto}" "${dpt}" && return 0
    check_egress_dhcp "${proto}" "${spt}" "${dpt}" && return 0
    check_egress_multicast "${proto}" "${dpt}" "${folded}" && return 0
    check_egress_broadcast "${proto}" "${dpt}" "${dst}" && return 0
    return 1
}

strip_egress_routine() {
    local source="$1"
    local kept="$2"
    local line
    : >"${kept}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == *"${EGRESS_KEY}"* ]] && check_egress_routine "${line}"; then
            continue
        fi
        printf '%s\n' "${line}" >>"${kept}"
    done <"${source}"
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

check_egress_flow() {
    [[ -n "${1}" && -n "${2}" && -n "${3}" ]]
}

check_egress_stamp() {
    if [[ ! -s "${stamp}" ]] || ! grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' "${stamp}"; then
        record_egress_stamp
        log_pass "$(get_text watchdog.initial-rep-re-written)"
        exit 0
    fi
}

set_egress_scan() {
    install -d -m 755 /run/liltress-workstation
    raw="$(mktemp -p /run/liltress-workstation)"
    found="$(mktemp -p /run/liltress-workstation)"
    audit_tmp="$(mktemp -p /run/liltress-workstation)"
    kept="$(mktemp -p /run/liltress-workstation)"
    suspects="$(mktemp -p /run/liltress-workstation)"
    blocked_lines="$(mktemp -p /run/liltress-workstation)"
    ufw_file="$(mktemp -p /run/liltress-workstation)"
    trap 'rm -f "${raw}" "${found}" "${audit_tmp}" "${kept}" "${suspects}" "${blocked_lines}" "${ufw_file}"' EXIT
    start="$(head -n 1 "${stamp}")"
    journalctl -k --since "${start}" --no-pager >"${raw}" 2>/dev/null || true
    grep -F -- "${EGRESS_KEY}" "${raw}" >"${found}" || true
    strip_egress_routine "${found}" "${kept}"
    mv -f "${kept}" "${found}"
    record_egress_stamp
    if ! grep -q -F -- "${EGRESS_KEY}" "${found}"; then
        grep -E '\[UFW BLOCK\].*IN= .*OUT=[^[:space:]]' "${raw}" >"${ufw_file}" || true
        report_ufw_blocks "${ufw_file}"
        exit 0
    fi
}

collect_egress_audit() {
    local formatted
    if command -v ausearch >/dev/null 2>&1; then
        formatted="$(date -d "${start}" '+%m/%d/%Y %H:%M:%S' 2>/dev/null || true)"
        if [[ -n "${formatted}" ]]; then
            # shellcheck disable=SC2086
            ausearch -k "${EGRESS_KEY}" --start ${formatted} >"${audit_tmp}" 2>/dev/null || true
        fi
    fi
}

locate_egress_registry() {
    if declare -F watchdog_runtime_file >/dev/null 2>&1; then
        registry="$(watchdog_runtime_file "${BASE}" quarantine.registry)"
    else
        registry="${BASE}/cron/quarantine.registry"
    fi
    list_egress_suspects "${found}" "${audit_tmp}" "${registry}" >"${suspects}" || true
}

apply_egress_holds() {
    local sec flow_key proto dst dpt exe kline
    if [[ ! -s "${suspects}" ]]; then
        log_pass "$(get_text watchdog.no-flow-suspicious-outbound)"
        exit 0
    fi
    sec="$(get_isolate_seconds)"
    declare -A held_flows=()
    blocked=0
    while IFS=$'\t' read -r proto dst dpt exe kline || [[ -n "${proto}" ]]; do
        check_egress_flow "${proto}" "${dst}" "${dpt}" || continue
        flow_key="${proto}|${dst}|${dpt}"
        if [[ -z "${held_flows[${flow_key}]:-}" ]]; then
            if install_egress_hold "${dst}" "${proto}" "${dpt}" "${sec}"; then
                held_flows["${flow_key}"]=1
                blocked=1
                printf '%s\n' "$(get_text watchdog.blocked-during-s "${dst}" "${proto,,}" "${dpt}" "${sec}" "${exe}")" >>"${LOG_FILE}"
            fi
        fi
        if [[ -n "${held_flows[${flow_key}]:-}" ]]; then
            printf '%s\n' "${kline}" >>"${blocked_lines}"
        fi
    done <"${suspects}"
}

finish_egress_scan() {
    if [[ "${blocked}" -eq 0 ]]; then
        log_pass "$(get_text watchdog.block-rejected)"
        exit 0
    fi
    if declare -F render_egress_body >/dev/null 2>&1; then
        render_egress_body "${blocked_lines}" "${audit_tmp}" >>"${LOG_FILE}" || true
    else
        cat "${blocked_lines}" >>"${LOG_FILE}"
    fi
    log_alert "$(get_text watchdog.flow-outbound-suspicious-blocked)"
    exit 0
}

load_egress_config
set_egress_paths
require_egress_journal
locate_egress_stamp
check_egress_stamp
set_egress_scan
collect_egress_audit
locate_egress_registry
apply_egress_holds
finish_egress_scan
