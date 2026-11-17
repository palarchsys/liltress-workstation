#!/usr/bin/env python3
# =============================================================================
# File       : python/vpn-dns.py
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Resolve one tunnel name with one DNS server.
# Note       : An empty label refuses the command. A broken reply is skipped.
# -----------------------------------------------------------------------------


import socket
import sys

name = sys.argv[1]
server = sys.argv[2]
MARKER = b"\x4c\x54"


def encode_label(part):
    # An empty label is refused. A label past 63 bytes is refused too.
    raw = part.encode("idna")
    if not raw or len(raw) > 63:
        raise SystemExit(2)
    return bytes([len(raw)]) + raw


def build(qname, qtype):
    # The first two bytes are the marker. One question follows.
    header = (0x4C54).to_bytes(2, "big") + b"\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00"
    labels = b""
    for part in qname.rstrip(".").split("."):
        labels += encode_label(part)
    tail = qtype.to_bytes(2, "big") + (1).to_bytes(2, "big")
    return header + labels + b"\x00" + tail


def skip_name(data, cursor):
    # A compressed name takes two bytes and its target stays unread.
    # Thirty hops end the walk.
    hops = 0
    while hops < 30:
        if cursor >= len(data):
            raise ValueError("short")
        length = data[cursor]
        if length == 0:
            return cursor + 1
        if length & 0xC0 == 0xC0:
            return cursor + 2
        if length & 0xC0:
            raise ValueError("label")
        cursor += 1 + length
        hops += 1
    raise ValueError("loop")


def read_header(data):
    if len(data) < 12 or data[0:2] != MARKER:
        return None
    questions = int.from_bytes(data[4:6], "big")
    answers = int.from_bytes(data[6:8], "big")
    return questions, answers


def skip_questions(data, cursor, questions):
    for _ in range(questions):
        cursor = skip_name(data, cursor)
        cursor += 4
    return cursor


def read_answer(data, cursor):
    cursor = skip_name(data, cursor)
    kind = int.from_bytes(data[cursor : cursor + 2], "big")
    cursor += 8
    length = int.from_bytes(data[cursor : cursor + 2], "big")
    cursor += 2
    body = data[cursor : cursor + length]
    return cursor + length, kind, length, body


def format_answer(kind, length, body):
    if kind == 1 and length == 4:
        return "A " + socket.inet_ntoa(body)
    if kind == 28 and length == 16:
        return "AAAA " + socket.inet_ntop(socket.AF_INET6, body)
    return ""


def collect_answers(data, cursor, answers):
    found = []
    for _ in range(answers):
        cursor, kind, length, body = read_answer(data, cursor)
        text = format_answer(kind, length, body)
        if text:
            found.append(text)
    return found


def query(qtype):
    packet = build(name, qtype)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(3)
    try:
        sock.sendto(packet, (server, 53))
        data, _addr = sock.recvfrom(4096)
    finally:
        sock.close()
    header = read_header(data)
    if header is None:
        return []
    questions, answers = header
    cursor = skip_questions(data, 12, questions)
    return collect_answers(data, cursor, answers)


def run_lookup():
    # One kind can be absent. The other kind is still asked.
    rows = []
    for kind in (1, 28):
        try:
            rows.extend(query(kind))
        except Exception:
            continue
    if not rows:
        raise SystemExit(1)
    print("\n".join(rows))


run_lookup()
