#!/usr/bin/env python3
# =============================================================================
# File       : python/vpn-dns.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import socket
import sys

name = sys.argv[1]
server = sys.argv[2]

def build(qname, qtype):
    header = (0x4C54).to_bytes(2, "big") + b"\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00"
    labels = b""
    for part in qname.rstrip(".").split("."):
        raw = part.encode("idna")
        if not raw or len(raw) > 63:
            raise SystemExit(2)
        labels += bytes([len(raw)]) + raw
    return header + labels + b"\x00" + qtype.to_bytes(2, "big") + (1).to_bytes(2, "big")

def skip_name(data, index):
    hops = 0
    while hops < 30:
        if index >= len(data):
            raise ValueError("short")
        length = data[index]
        if length == 0:
            return index + 1
        if length & 0xC0 == 0xC0:
            return index + 2
        if length & 0xC0:
            raise ValueError("label")
        index += 1 + length
        hops += 1
    raise ValueError("loop")

def query(qtype):
    packet = build(name, qtype)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(3)
    try:
        sock.sendto(packet, (server, 53))
        data, _addr = sock.recvfrom(4096)
    finally:
        sock.close()
    if len(data) < 12 or data[0:2] != b"\x4c\x54":
        return []
    questions = int.from_bytes(data[4:6], "big")
    answers = int.from_bytes(data[6:8], "big")
    index = 12
    for _ in range(questions):
        index = skip_name(data, index)
        index += 4
    found = []
    for _ in range(answers):
        index = skip_name(data, index)
        kind = int.from_bytes(data[index:index + 2], "big")
        index += 8
        length = int.from_bytes(data[index:index + 2], "big")
        index += 2
        body = data[index:index + length]
        index += length
        if kind == 1 and length == 4:
            found.append("A " + socket.inet_ntoa(body))
        elif kind == 28 and length == 16:
            found.append("AAAA " + socket.inet_ntop(socket.AF_INET6, body))
    return found

rows = []
for kind in (1, 28):
    try:
        rows.extend(query(kind))
    except Exception:
        continue
if not rows:
    raise SystemExit(1)
print("\n".join(rows))
