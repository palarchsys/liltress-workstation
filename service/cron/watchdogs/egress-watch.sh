#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/egress-watch.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================
# -----------------------------------------------------------------------------
# Note       : The stamp lives under the Liltress cron directory.
# Note       : The first pass writes the stamp and stays silent.
# Note       : A temporary or quarantined executable holds that one destination.
# -----------------------------------------------------------------------------

set -euo pipefail
W_BASE="${W_BASE:-/opt/liltress-workstation}"
# shellcheck disable=SC1091
source "${W_BASE}/cron/bin/common.sh"
if [[ -f "${W_BASE}/cron/egress.conf" ]]; then
    # shellcheck disable=SC1091
    source "${W_BASE}/cron/egress.conf"
fi
LOG_FILE="${LOG_DIR}/egress-${STAMP}.log"
ALERT_FILE="${ALERT_DIR}/egress-${STAMP}.txt"
MODULE_NAME="Ufw"

if ! command -v journalctl >/dev/null 2>&1; then
    log_pass "$(get_text watchdog.journalctl-absent)"
    exit 0
fi

stamp="${W_BASE}/cron/egress.stamp"

record_egress_stamp() {
    local moment
    moment="$(date '+%Y-%m-%d %H:%M:%S')"
    install -d -m 750 "${W_BASE}/cron"
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
    local sec="${W_NET_ISOLATE_SEC:-120}"
    if [[ ! "${sec}" =~ ^[0-9]+$ ]] || [[ "${sec}" -lt 30 ]] || [[ "${sec}" -gt 300 ]]; then
        sec=120
    fi
    printf '%s\n' "${sec}"
}

list_egress_suspects() {
    local kernel="$1"
    local audit="$2"
    local registry="$3"
    W_EGRESS_KERNEL="${kernel}" W_EGRESS_AUDIT="${audit}" W_EGRESS_REGISTRY="${registry}" python3 - << 'PY'
import ipaddress
import os
import re
import sys
from pathlib import Path

kernel_path = Path(os.environ.get("W_EGRESS_KERNEL", ""))
audit_path = Path(os.environ.get("W_EGRESS_AUDIT", ""))
registry_path = Path(os.environ.get("W_EGRESS_REGISTRY", ""))

def parse_sockaddr(token):
    token = token.strip().strip('"')
    if token.lower().startswith("saddr="):
        token = token.split("=", 1)[1]
    host = re.search(r"host:([0-9A-Fa-f:.]+)", token)
    serv = re.search(r"serv:([0-9]+)", token)
    if host and serv:
        return host.group(1), serv.group(1)
    if not re.fullmatch(r"[0-9A-Fa-f]+", token) or len(token) < 16 or len(token) % 2:
        return None
    raw = bytes.fromhex(token)
    if len(raw) < 8:
        return None
    family = int.from_bytes(raw[0:2], "little")
    port = str(int.from_bytes(raw[2:4], "big"))
    if family == 2 and len(raw) >= 8:
        ip = ".".join(str(b) for b in raw[4:8])
        return ip, port
    if family == 10 and len(raw) >= 24:
        return str(ipaddress.IPv6Address(raw[8:24])), port
    return None

def canon(addr):
    try:
        return str(ipaddress.ip_address(addr))
    except ValueError:
        return addr

def normalize(exe):
    text = exe.strip()
    suffix = " (deleted)"
    if text.endswith(suffix):
        text = text[: -len(suffix)]
    return text

held = set()
if registry_path.is_file():
    for raw in registry_path.read_text(errors="replace").splitlines():
        parts = raw.split("\t")
        if len(parts) < 5:
            continue
        for path in (parts[3], parts[4]):
            if path.startswith("/"):
                held.add(path)

def is_suspect(exe):
    path = normalize(exe)
    if path.startswith("/tmp/") or path.startswith("/var/tmp/") or path.startswith("/dev/shm/"):
        return True
    return path in held

events = {}
order = []
audit_text = audit_path.read_text(errors="replace") if audit_path.is_file() else ""
for raw in audit_text.splitlines():
    line = raw.strip()
    msg = re.search(r"msg=audit\(([^)]+)\):", line)
    if not msg:
        continue
    key = msg.group(1)
    if key not in events:
        events[key] = {}
        order.append(key)
    event = events[key]
    if line.startswith("type=SYSCALL"):
        exe = re.search(r'exe="([^"]+)"', line) or re.search(r"exe=(\S+)", line)
        if exe:
            event["exe"] = exe.group(1)
    if "saddr=" in line or "host:" in line:
        sock = re.search(r"saddr=(\S+)", line)
        parsed = parse_sockaddr(sock.group(1) if sock else line)
        if parsed:
            event["dst"] = (canon(parsed[0]), parsed[1])

flows = {}
for key in order:
    event = events[key]
    dst = event.get("dst")
    exe = event.get("exe", "")
    if not dst or not exe or not is_suspect(exe):
        continue
    flows.setdefault(dst, exe)

field_re = {
    "PROTO": re.compile(r"\bPROTO=(\S+)"),
    "DST": re.compile(r"\bDST=(\S+)"),
    "DPT": re.compile(r"\bDPT=([0-9]+)"),
}
if kernel_path.is_file():
    for raw in kernel_path.read_text(errors="replace").splitlines():
        line = raw.rstrip("\n")
        if "w-egress" not in line:
            continue
        found = {name: rx.search(line) for name, rx in field_re.items()}
        if not all(found.values()):
            continue
        proto = found["PROTO"].group(1).upper()
        if proto not in {"TCP", "UDP"}:
            continue
        dst = canon(found["DST"].group(1))
        dpt = found["DPT"].group(1)
        exe = flows.get((dst, dpt))
        if not exe:
            continue
        sys.stdout.write("\t".join([proto, dst, dpt, normalize(exe), line]) + "\n")
PY
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
list_egress_suspects "${found}" "${audit_tmp}" "${W_BASE}/cron/quarantine.registry" > "${suspects}" || true
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
if declare -F format_egress_body >/dev/null 2>&1; then
    format_egress_body "${blocked_lines}" "${audit_tmp}" >> "${LOG_FILE}" || true
else
    cat "${blocked_lines}" >> "${LOG_FILE}"
fi
log_alert "$(get_text watchdog.flow-outbound-suspicious-blocked)"
exit 0
