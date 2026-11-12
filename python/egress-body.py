#!/usr/bin/env python3
# =============================================================================
# File       : python/egress-body.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import sys

mode = sys.argv[1]
sys.argv = [sys.argv[0]] + sys.argv[2:]

if mode == 'watch':
    import ipaddress
    import os
    import re
    import sys
    from pathlib import Path

    kernel_path = Path(os.environ.get("EGRESS_KERNEL", ""))
    audit_path = Path(os.environ.get("EGRESS_AUDIT", ""))
    registry_path = Path(os.environ.get("EGRESS_REGISTRY", ""))

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
elif mode == 'core':
    import os
    import re
    import sys
    from pathlib import Path

    kernel_path = Path(sys.argv[1])
    audit_path = os.environ.get("EGRESS_AUDIT_FILE", "")
    kernel_lines = []
    seen = set()
    if kernel_path.is_file():
        for raw in kernel_path.read_text(errors="replace").splitlines():
            line = raw.rstrip("\n")
            if not line.strip() or line in seen:
                continue
            seen.add(line)
            kernel_lines.append(line)

    audit_text = ""
    if audit_path and Path(audit_path).is_file():
        audit_text = Path(audit_path).read_text(errors="replace")

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
        return None

    events = {}
    order = []
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
            comm = re.search(r'comm="([^"]+)"', line) or re.search(r"comm=(\S+)", line)
            pid = re.search(r"\bpid=([0-9]+)", line)
            uid = re.search(r"\buid=([0-9]+)", line)
            if comm:
                event["comm"] = comm.group(1)
            if pid:
                event["pid"] = pid.group(1)
            if uid:
                event["uid"] = uid.group(1)
        if "saddr=" in line or "host:" in line:
            sock = re.search(r"saddr=(\S+)", line)
            parsed = parse_sockaddr(sock.group(1) if sock else line)
            if parsed:
                event["dst"] = parsed

    flows = {}
    for key in order:
        event = events[key]
        dst = event.get("dst")
        if not dst or "pid" not in event:
            continue
        flows[dst] = (event.get("comm") or "inconnu", event["pid"], event.get("uid") or "0")

    def emit_plain(lines):
        chosen = lines[:40]
        if chosen:
            sys.stdout.write("\n".join(chosen) + "\n")

    if not flows:
        emit_plain(kernel_lines)
        raise SystemExit(0)

    groups = []
    index = {}
    unmatched = []
    for line in kernel_lines:
        dst = re.search(r"\bDST=(\S+)", line)
        dpt = re.search(r"\bDPT=([0-9]+)", line)
        proc = None
        if dst and dpt:
            proc = flows.get((dst.group(1), dpt.group(1)))
        if proc is None:
            unmatched.append(line)
            continue
        label = "Processus : %s (pid %s) uid %s" % (proc[0], proc[1], proc[2])
        if label not in index:
            if len(groups) >= 40:
                continue
            index[label] = len(groups)
            groups.append([label, []])
        groups[index[label]][1].append(line)

    if unmatched and len(groups) < 40:
        groups.append(["Processus : non associé", unmatched])

    blocks = []
    for label, lines in groups:
        blocks.append(label)
        for line in lines:
            blocks.append(" → " + line)
    if blocks:
        sys.stdout.write("\n".join(blocks) + "\n")
else:
    sys.exit('mode python refusé')
