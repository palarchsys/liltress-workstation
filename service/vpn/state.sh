#!/usr/bin/env bash
# =============================================================================
# File       : service/vpn/state.sh
# Updated at : 2026-11-05
# Creator    : palarchsys
# =============================================================================

get_vpn_state_path() {
    printf '%s/vpn.json\n' "$(get_vpn_home)"
}

run_vpn_state() {
    python3 - "$@" << 'PY'
import json
import os
import sys
from datetime import datetime, timezone

cmd = sys.argv[1]
path = sys.argv[2]
args = sys.argv[3:]

def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def blank():
    return {"mode": "off", "active": "", "profiles": []}

def load():
    try:
        with open(path, encoding="utf-8") as handle:
            raw = json.load(handle)
    except (OSError, json.JSONDecodeError, UnicodeError):
        return blank(), False
    if not isinstance(raw, dict):
        return blank(), False
    mode = raw.get("mode")
    if mode not in ("on", "off"):
        mode = "off"
    active = raw.get("active")
    if not isinstance(active, str):
        active = ""
    profiles = raw.get("profiles")
    clean = []
    if isinstance(profiles, list):
        for item in profiles:
            if not isinstance(item, dict):
                continue
            name = item.get("name")
            proto = item.get("proto")
            if not isinstance(name, str) or not name:
                continue
            if proto not in ("wireguard", "openvpn"):
                proto = "wireguard"
            def text(key):
                value = item.get(key)
                return value if isinstance(value, str) else ""
            clean.append({
                "name": name,
                "proto": proto,
                "valid": item.get("valid") is True,
                "validated_at": text("validated_at"),
                "observed_at": text("observed_at"),
                "tested_at": text("tested_at"),
            })
    return {"mode": mode, "active": active, "profiles": clean}, True

def save(data):
    parent = os.path.dirname(path)
    os.makedirs(parent, mode=0o755, exist_ok=True)
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)

def find(data, name):
    for item in data["profiles"]:
        if item["name"] == name:
            return item
    return None

def empty_profile(name, proto):
    return {
        "name": name,
        "proto": proto,
        "valid": False,
        "validated_at": "",
        "observed_at": "",
        "tested_at": "",
    }

data, readable = load()

if cmd == "read":
    if not readable:
        data = blank()
    print(data["mode"])
    print(data["active"])
elif cmd == "init":
    if not os.path.exists(path):
        save(blank())
elif cmd == "mode":
    data["mode"] = "on" if args and args[0] == "on" else "off"
    save(data)
elif cmd == "active":
    data["active"] = args[0] if args else ""
    save(data)
elif cmd == "attempt":
    name, proto, flag = args
    item = find(data, name)
    if item is None:
        item = empty_profile(name, proto)
        data["profiles"].append(item)
    stamp = now()
    item["proto"] = proto if proto in ("wireguard", "openvpn") else item["proto"]
    item["observed_at"] = stamp
    item["tested_at"] = stamp
    if flag == "1":
        item["valid"] = True
        item["validated_at"] = stamp
    else:
        item["valid"] = False
    save(data)
elif cmd == "observe":
    item = find(data, args[0])
    if item is not None:
        item["observed_at"] = now()
        save(data)
elif cmd == "valid":
    item = find(data, args[0])
    sys.exit(0 if item and item["valid"] else 1)
elif cmd == "any-valid":
    sys.exit(0 if any(item["valid"] for item in data["profiles"]) else 1)
elif cmd == "had-valid":
    sys.exit(0 if any(item["validated_at"] for item in data["profiles"]) else 1)
elif cmd == "candidates":
    names = [item["name"] for item in data["profiles"] if item["valid"]]
    names.sort(key=lambda name: find(data, name)["tested_at"], reverse=True)
    active = data["active"]
    if active in names:
        names.remove(active)
        names.insert(0, active)
    for name in names:
        print(name)
elif cmd == "show":
    item = find(data, args[0])
    if item is None:
        sys.exit(1)
    print("true" if item["valid"] else "false")
    print(item["validated_at"])
    print(item["observed_at"])
    print(item["tested_at"])
elif cmd == "ensure":
    name, proto = args
    if proto not in ("wireguard", "openvpn"):
        proto = "wireguard"
    if find(data, name) is None:
        data["profiles"].append(empty_profile(name, proto))
        save(data)
elif cmd == "drop-missing":
    keep = set(args)
    data["profiles"] = [item for item in data["profiles"] if item["name"] in keep]
    if data["active"] not in keep:
        data["active"] = ""
    save(data)
elif cmd == "remove":
    name = args[0]
    data["profiles"] = [item for item in data["profiles"] if item["name"] != name]
    if data["active"] == name:
        data["active"] = ""
    save(data)
else:
    sys.exit(2)
PY
}

read_vpn_state() {
    local line
    W_VPN_MODE=off
    W_VPN_ACTIVE=
    line="$(run_vpn_state read "$(get_vpn_state_path)" 2>/dev/null || true)"
    W_VPN_MODE="${line%%$'\n'*}"
    if [[ "${line}" == *$'\n'* ]]; then
        W_VPN_ACTIVE="${line#*$'\n'}"
    fi
    W_VPN_ACTIVE="${W_VPN_ACTIVE//$'\n'/}"
    [[ "${W_VPN_MODE}" == "on" ]] || W_VPN_MODE=off
}

write_vpn_state() {
    local path
    path="$(get_vpn_state_path)"
    if [[ $# -eq 0 ]]; then
        run_vpn_state init "${path}"
        return 0
    fi
    run_vpn_state mode "${path}" "$1"
    if [[ $# -ge 2 ]]; then
        run_vpn_state active "${path}" "$2"
    fi
}

record_vpn_attempt() {
    local name="$1" flag="$2" proto
    proto="$(get_vpn_meta "${name}" proto 2>/dev/null || true)"
    [[ "${proto}" == "wireguard" || "${proto}" == "openvpn" ]] || proto="wireguard"
    run_vpn_state attempt "$(get_vpn_state_path)" "${name}" "${proto}" "${flag}"
}

record_vpn_status() {
    run_vpn_state observe "$(get_vpn_state_path)" "$1"
}

check_vpn_profile_valid() {
    run_vpn_state valid "$(get_vpn_state_path)" "$1"
}

check_vpn_any_valid() {
    run_vpn_state any-valid "$(get_vpn_state_path)"
}

check_vpn_had_valid() {
    run_vpn_state had-valid "$(get_vpn_state_path)"
}

list_vpn_failover_names() {
    run_vpn_state candidates "$(get_vpn_state_path)"
}

show_vpn_profile_state() {
    run_vpn_state show "$(get_vpn_state_path)" "$1"
}

remove_vpn_state() {
    run_vpn_state remove "$(get_vpn_state_path)" "$1"
}

set_vpn_state_mode() {
    run_vpn_state mode "$(get_vpn_state_path)" "$1"
}

set_vpn_state_active() {
    run_vpn_state active "$(get_vpn_state_path)" "$1"
}

refresh_vpn_state() {
    local home name proto kind dir
    local -a names=()
    home="$(get_vpn_home)"
    [[ -d "${home}" ]] || return 0
    shopt -s nullglob
    for kind in wireguard openvpn profiles; do
        for dir in "${home}/${kind}"/*/; do
            [[ -d "${dir}" ]] || continue
            name="$(basename -- "${dir}")"
            check_vpn_name "${name}" || continue
            proto="$(get_vpn_meta "${name}" proto 2>/dev/null || true)"
            [[ "${proto}" == "wireguard" || "${proto}" == "openvpn" ]] || proto="wireguard"
            run_vpn_state ensure "$(get_vpn_state_path)" "${name}" "${proto}"
            names+=("${name}")
        done
    done
    shopt -u nullglob
    if (( ${#names[@]} == 0 )); then
        run_vpn_state drop-missing "$(get_vpn_state_path)"
        return 0
    fi
    run_vpn_state drop-missing "$(get_vpn_state_path)" "${names[@]}"
}

restart_vpn_services() {
    local unit
    for unit in unbound.service systemd-resolved.service; do
        if systemctl cat "${unit}" >/dev/null 2>&1; then
            systemctl try-restart "${unit}" >/dev/null 2>&1 || true
        fi
    done
    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl flush-caches >/dev/null 2>&1 || true
    fi
    if declare -F log_info >/dev/null 2>&1; then
        log_info "${INSTALL_WATCHER:-BASH}" "vpn.service.restart"
    fi
}
