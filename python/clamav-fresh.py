#!/usr/bin/env python3
# =============================================================================
# File       : python/clamav-fresh.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import sys
from pathlib import Path

log = Path(sys.argv[1]).read_text(errors="replace").splitlines()
seen_path = Path(sys.argv[2])
known = set()
if seen_path.is_file():
    known = {line for line in seen_path.read_text(errors="replace").splitlines() if line}
fresh = []
for line in log:
    if not line.endswith(" FOUND"):
        continue
    body = line[:-6]
    if ": " not in body:
        continue
    path, sig = body.rsplit(": ", 1)
    key = sig + "\t" + path
    if key in known or key in fresh:
        continue
    fresh.append(key)
if fresh:
    with seen_path.open("a", encoding="utf-8") as handle:
        for key in fresh:
            handle.write(key + "\n")
    for key in fresh:
        print(key)
