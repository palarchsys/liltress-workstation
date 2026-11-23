#!/usr/bin/env python3
# =============================================================================
# File       : python/vpn-state.py
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Store the workstation tunnel latch.
# Note       : A missing file stays missing until a command creates it.
# -----------------------------------------------------------------------------


import json
import os
import sys
from datetime import datetime, timezone

TUNNELS = ("wireguard", "openvpn")


def stamp_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def blank_state():
    return {"mode": "off", "active": "", "default": "", "profiles": []}


def text_value(value):
    if isinstance(value, str):
        return value
    return ""


def mode_value(raw):
    mode = raw.get("mode")
    if mode in ("on", "off"):
        return mode
    return "off"


def profile_row(item):
    # A profile counts only when its flag is exactly true.
    if not isinstance(item, dict):
        return None
    name = item.get("name")
    if not isinstance(name, str) or not name:
        return None
    proto = item.get("proto")
    if proto not in TUNNELS:
        proto = "wireguard"
    return {
        "name": name,
        "proto": proto,
        "valid": item.get("valid") is True,
        "validated_at": text_value(item.get("validated_at")),
        "observed_at": text_value(item.get("observed_at")),
        "tested_at": text_value(item.get("tested_at")),
    }


def profile_rows(raw):
    profiles = raw.get("profiles")
    if not isinstance(profiles, list):
        return []
    rows = []
    for item in profiles:
        row = profile_row(item)
        if row is None:
            continue
        rows.append(row)
    return rows


def load_state():
    try:
        with open(path, encoding="utf-8") as handle:
            raw = json.load(handle)
    except (OSError, json.JSONDecodeError, UnicodeError):  # fmt: skip
        return blank_state(), False
    if not isinstance(raw, dict):
        return blank_state(), False
    data = {
        "mode": mode_value(raw),
        "active": text_value(raw.get("active")),
        "default": text_value(raw.get("default")),
        "profiles": profile_rows(raw),
    }
    return data, True


def store_state(data):
    # The latch file stays private to its owner.
    parent = os.path.dirname(path)
    os.makedirs(parent, mode=0o755, exist_ok=True)
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def locate_profile(data, name):
    for item in data["profiles"]:
        if item["name"] == name:
            return item
    return None


def fresh_profile(name, proto):
    return {
        "name": name,
        "proto": proto,
        "valid": False,
        "validated_at": "",
        "observed_at": "",
        "tested_at": "",
    }


def command_read():
    # An unreadable file is shown as an empty latch.
    shown = data
    if not readable:
        shown = blank_state()
    print(shown["mode"])
    print(shown["active"])
    print(shown["default"])


def command_init():
    if not os.path.exists(path):
        store_state(blank_state())


def command_mode():
    if args and args[0] == "on":
        data["mode"] = "on"
    else:
        data["mode"] = "off"
    store_state(data)


def command_active():
    if args:
        data["active"] = args[0]
    else:
        data["active"] = ""
    store_state(data)


def command_default():
    if args:
        data["default"] = args[0]
    else:
        data["default"] = ""
    store_state(data)


def remember_attempt(item, proto, flag, stamp):
    # A failed attempt keeps the previous validation time.
    # An unknown kind does not replace the stored kind.
    if proto in TUNNELS:
        item["proto"] = proto
    item["observed_at"] = stamp
    item["tested_at"] = stamp
    if flag == "1":
        item["valid"] = True
        item["validated_at"] = stamp
        return
    item["valid"] = False


def command_attempt():
    name, proto, flag = args
    item = locate_profile(data, name)
    if item is None:
        item = fresh_profile(name, proto)
        data["profiles"].append(item)
    remember_attempt(item, proto, flag, stamp_now())
    store_state(data)


def command_observe():
    item = locate_profile(data, args[0])
    if item is None:
        return
    item["observed_at"] = stamp_now()
    store_state(data)


def command_valid():
    item = locate_profile(data, args[0])
    if item and item["valid"]:
        sys.exit(0)
    sys.exit(1)


def command_any_valid():
    for item in data["profiles"]:
        if item["valid"]:
            sys.exit(0)
    sys.exit(1)


def command_had_valid():
    for item in data["profiles"]:
        if item["validated_at"]:
            sys.exit(0)
    sys.exit(1)


def place_first(names, chosen):
    if chosen not in names:
        return
    names.remove(chosen)
    names.insert(0, chosen)


def tested_stamp(name):
    return locate_profile(data, name)["tested_at"]


def command_candidates():
    # The startup name is placed ahead of the live name.
    names = []
    for item in data["profiles"]:
        if item["valid"]:
            names.append(item["name"])
    names.sort(key=tested_stamp, reverse=True)
    place_first(names, data["active"])
    place_first(names, data["default"])
    for name in names:
        print(name)


def command_show():
    item = locate_profile(data, args[0])
    if item is None:
        sys.exit(1)
    if item["valid"]:
        print("true")
    else:
        print("false")
    print(item["validated_at"])
    print(item["observed_at"])
    print(item["tested_at"])


def command_ensure():
    name, proto = args
    if proto not in TUNNELS:
        proto = "wireguard"
    if locate_profile(data, name) is not None:
        return
    data["profiles"].append(fresh_profile(name, proto))
    store_state(data)


def command_drop_missing():
    keep = set(args)
    kept = []
    for item in data["profiles"]:
        if item["name"] in keep:
            kept.append(item)
    data["profiles"] = kept
    if data["active"] not in keep:
        data["active"] = ""
    if data["default"] not in keep:
        data["default"] = ""
    store_state(data)


def command_remove():
    name = args[0]
    kept = []
    for item in data["profiles"]:
        if item["name"] != name:
            kept.append(item)
    data["profiles"] = kept
    if data["active"] == name:
        data["active"] = ""
    if data["default"] == name:
        data["default"] = ""
    store_state(data)


COMMANDS = {
    "read": command_read,
    "init": command_init,
    "mode": command_mode,
    "active": command_active,
    "default": command_default,
    "attempt": command_attempt,
    "observe": command_observe,
    "valid": command_valid,
    "any-valid": command_any_valid,
    "had-valid": command_had_valid,
    "candidates": command_candidates,
    "show": command_show,
    "ensure": command_ensure,
    "drop-missing": command_drop_missing,
    "remove": command_remove,
}


def run_state():
    global data, readable
    data, readable = load_state()
    command = COMMANDS.get(cmd)
    if command is None:
        sys.exit(2)
    command()


cmd = sys.argv[1]
path = sys.argv[2]
args = sys.argv[3:]
run_state()
