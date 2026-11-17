#!/usr/bin/env python3
# =============================================================================
# File       : python/egress-body.py
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Turn kernel and audit lines into one egress report.
# Note       : The watch report understands an IPv6 hex address. The core report does not.
# -----------------------------------------------------------------------------


import ipaddress
import os
import re
import sys
from pathlib import Path


def bare_sockaddr(token):
    token = token.strip().strip('"')
    if token.lower().startswith("saddr="):
        token = token.split("=", 1)[1]
    return token


def sockaddr_text(token):
    host = re.search(r"host:([0-9A-Fa-f:.]+)", token)
    serv = re.search(r"serv:([0-9]+)", token)
    if host and serv:
        return host.group(1), serv.group(1)
    return None


def hex_bytes(token):
    if not re.fullmatch(r"[0-9A-Fa-f]+", token) or len(token) < 16 or len(token) % 2:
        return None
    raw = bytes.fromhex(token)
    if len(raw) < 8:
        return None
    return raw


def ipv4_sockaddr(raw):
    family = int.from_bytes(raw[0:2], "little")
    port = str(int.from_bytes(raw[2:4], "big"))
    if family == 2 and len(raw) >= 8:
        ip = ".".join(str(byte) for byte in raw[4:8])
        return ip, port
    return None


def ipv6_sockaddr(raw):
    family = int.from_bytes(raw[0:2], "little")
    port = str(int.from_bytes(raw[2:4], "big"))
    if family == 10 and len(raw) >= 24:
        return str(ipaddress.IPv6Address(raw[8:24])), port
    return None


def parse_sockaddr_watch(token):
    token = bare_sockaddr(token)
    found = sockaddr_text(token)
    if found:
        return found
    raw = hex_bytes(token)
    if raw is None:
        return None
    found = ipv4_sockaddr(raw)
    if found:
        return found
    return ipv6_sockaddr(raw)


def parse_sockaddr_core(token):
    token = bare_sockaddr(token)
    found = sockaddr_text(token)
    if found:
        return found
    raw = hex_bytes(token)
    if raw is None:
        return None
    return ipv4_sockaddr(raw)


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


def held_paths(registry_path):
    held = set()
    if not registry_path.is_file():
        return held
    for raw in registry_path.read_text(errors="replace").splitlines():
        parts = raw.split("\t")
        if len(parts) < 5:
            continue
        for path in (parts[3], parts[4]):
            if path.startswith("/"):
                held.add(path)
    return held


def is_suspect(exe, held):
    path = normalize(exe)
    if path.startswith("/tmp/") or path.startswith("/var/tmp/") or path.startswith("/dev/shm/"):
        return True
    return path in held


def read_events(text, remember):
    events = {}
    order = []
    for raw in text.splitlines():
        line = raw.strip()
        msg = re.search(r"msg=audit\(([^)]+)\):", line)
        if not msg:
            continue
        key = msg.group(1)
        if key not in events:
            events[key] = {}
            order.append(key)
        remember(events[key], line)
    return events, order


def watch_exe(line):
    exe = re.search(r'exe="([^"]+)"', line) or re.search(r"exe=(\S+)", line)
    if exe:
        return exe.group(1)
    return ""


def watch_dst(line):
    if "saddr=" not in line and "host:" not in line:
        return None
    sock = re.search(r"saddr=(\S+)", line)
    token = line if sock is None else sock.group(1)
    parsed = parse_sockaddr_watch(token)
    if not parsed:
        return None
    return canon(parsed[0]), parsed[1]


def remember_watch(event, line):
    if line.startswith("type=SYSCALL"):
        exe = watch_exe(line)
        if exe:
            event["exe"] = exe
    dst = watch_dst(line)
    if dst:
        event["dst"] = dst


def watch_flows(order, events, held):
    flows = {}
    for key in order:
        event = events[key]
        dst = event.get("dst")
        exe = event.get("exe", "")
        if not dst or not exe or not is_suspect(exe, held):
            continue
        flows.setdefault(dst, exe)
    return flows


def watch_hit(line, field_re, flows):
    if "w-egress" not in line:
        return ""
    found = {name: rx.search(line) for name, rx in field_re.items()}
    if not all(found.values()):
        return ""
    proto = found["PROTO"].group(1).upper()
    if proto not in {"TCP", "UDP"}:
        return ""
    dst = canon(found["DST"].group(1))
    dpt = found["DPT"].group(1)
    exe = flows.get((dst, dpt))
    if not exe:
        return ""
    return "\t".join([proto, dst, dpt, normalize(exe), line])


def emit_watch(kernel_path, flows):
    field_re = {
        "PROTO": re.compile(r"\bPROTO=(\S+)"),
        "DST": re.compile(r"\bDST=(\S+)"),
        "DPT": re.compile(r"\bDPT=([0-9]+)"),
    }
    if not kernel_path.is_file():
        return
    for raw in kernel_path.read_text(errors="replace").splitlines():
        hit = watch_hit(raw.rstrip("\n"), field_re, flows)
        if hit:
            sys.stdout.write(hit + "\n")


def run_watch_report():
    kernel_path = Path(os.environ.get("EGRESS_KERNEL", ""))
    audit_path = Path(os.environ.get("EGRESS_AUDIT", ""))
    registry_path = Path(os.environ.get("EGRESS_REGISTRY", ""))
    held = held_paths(registry_path)
    audit_text = audit_path.read_text(errors="replace") if audit_path.is_file() else ""
    events, order = read_events(audit_text, remember_watch)
    emit_watch(kernel_path, watch_flows(order, events, held))


def load_kernel(path):
    lines = []
    seen = set()
    if not path.is_file():
        return lines
    for raw in path.read_text(errors="replace").splitlines():
        line = raw.rstrip("\n")
        if not line.strip() or line in seen:
            continue
        seen.add(line)
        lines.append(line)
    return lines


def take_syscall(event, line):
    comm = re.search(r'comm="([^"]+)"', line) or re.search(r"comm=(\S+)", line)
    pid = re.search(r"\bpid=([0-9]+)", line)
    uid = re.search(r"\buid=([0-9]+)", line)
    if comm:
        event["comm"] = comm.group(1)
    if pid:
        event["pid"] = pid.group(1)
    if uid:
        event["uid"] = uid.group(1)


def take_core_dst(event, line):
    sock = re.search(r"saddr=(\S+)", line)
    parsed = parse_sockaddr_core(sock.group(1) if sock else line)
    if parsed:
        event["dst"] = parsed


def remember_core(event, line):
    if line.startswith("type=SYSCALL"):
        take_syscall(event, line)
    if "saddr=" in line or "host:" in line:
        take_core_dst(event, line)


def core_flows(order, events):
    flows = {}
    for key in order:
        event = events[key]
        dst = event.get("dst")
        if not dst or "pid" not in event:
            continue
        flows[dst] = (event.get("comm") or "inconnu", event["pid"], event.get("uid") or "0")
    return flows


def kernel_proc(line, flows):
    dst = re.search(r"\bDST=(\S+)", line)
    dpt = re.search(r"\bDPT=([0-9]+)", line)
    if dst and dpt:
        return flows.get((dst.group(1), dpt.group(1)))
    return None


def place_kernel_line(line, flows, groups, cursor, unmatched):
    proc = kernel_proc(line, flows)
    if proc is None:
        unmatched.append(line)
        return
    label = "Processus : %s (pid %s) uid %s" % (proc[0], proc[1], proc[2])
    if label not in cursor:
        if len(groups) >= 40:
            return
        cursor[label] = len(groups)
        groups.append([label, []])
    groups[cursor[label]][1].append(line)


def group_kernel(lines, flows):
    groups = []
    cursor = {}
    unmatched = []
    for line in lines:
        place_kernel_line(line, flows, groups, cursor, unmatched)
    if unmatched and len(groups) < 40:
        groups.append(["Processus : non associé", unmatched])
    return groups


def emit_plain(lines):
    chosen = lines[:40]
    if chosen:
        sys.stdout.write("\n".join(chosen) + "\n")


def emit_groups(groups):
    blocks = []
    for label, lines in groups:
        blocks.append(label)
        for line in lines:
            blocks.append(" → " + line)
    if blocks:
        sys.stdout.write("\n".join(blocks) + "\n")


def run_core():
    kernel_path = Path(sys.argv[1])
    audit_path = os.environ.get("EGRESS_AUDIT_FILE", "")
    kernel_lines = load_kernel(kernel_path)
    audit_text = ""
    if audit_path and Path(audit_path).is_file():
        audit_text = Path(audit_path).read_text(errors="replace")
    events, order = read_events(audit_text, remember_core)
    flows = core_flows(order, events)
    if not flows:
        emit_plain(kernel_lines)
        raise SystemExit(0)
    emit_groups(group_kernel(kernel_lines, flows))


def run_egress():
    mode = sys.argv[1]
    sys.argv = [sys.argv[0]] + sys.argv[2:]
    if mode == "watch":
        run_watch_report()
        return
    if mode == "core":
        run_core()
        return
    sys.exit("mode python refusé")


run_egress()
