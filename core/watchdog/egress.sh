#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/egress.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================


render_egress_body() {
    local kernel="$1"
    local audit="${2:-}"
    EGRESS_AUDIT_FILE="${audit}" python3 - "${kernel}" << 'PY'
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
PY
}
