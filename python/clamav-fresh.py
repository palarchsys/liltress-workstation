#!/usr/bin/env python3
# =============================================================================
# File       : python/clamav-fresh.py
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Append new ClamAV hits and print those hits.
# Note       : A signature and path already stored in the seen file is skipped.
# -----------------------------------------------------------------------------


import sys
from pathlib import Path


def hit_key(line):
    if not line.endswith(" FOUND"):
        return ""
    body = line[:-6]
    if ": " not in body:
        return ""
    path, signature = body.rsplit(": ", 1)
    return signature + "\t" + path


def fresh_hits(log_lines, known):
    fresh = []
    for line in log_lines:
        key = hit_key(line)
        if not key or key in known or key in fresh:
            continue
        fresh.append(key)
    return fresh


def remember(seen_path, fresh):
    with seen_path.open("a", encoding="utf-8") as handle:
        for key in fresh:
            handle.write(key + "\n")


if __name__ == "__main__":
    log_lines = Path(sys.argv[1]).read_text(errors="replace").splitlines()
    seen_path = Path(sys.argv[2])
    known = set()
    if seen_path.is_file():
        known = {line for line in seen_path.read_text(errors="replace").splitlines() if line}
    found = fresh_hits(log_lines, known)
    if found:
        remember(seen_path, found)
        for key in found:
            print(key)
