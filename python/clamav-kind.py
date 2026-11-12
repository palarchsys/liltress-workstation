#!/usr/bin/env python3
# =============================================================================
# File       : python/clamav-kind.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import re
import sys
from pathlib import Path

path = Path(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1] else None
text = path.read_text(errors="replace") if path and path.is_file() else ""
if re.search(r" FOUND$", text, re.M):
    sys.stdout.write("infected")
    raise SystemExit(0)
access = re.compile(
    r"Access denied|Can't access|Can't open file|Permission denied|No such file",
    re.I,
)
summary = re.compile(
    r"Known viruses:|Infected files:|Engine version:|Scanned directories:|"
    r"Scanned files:|Data scanned:|Data read:|^Time:|Start Date:|End Date:"
)
real = False
for raw in text.splitlines():
    line = raw.strip()
    if not line or summary.search(line) or access.search(line):
        continue
    if line.startswith("-----------") or re.match(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T", line):
        continue
    if re.search(r"ERROR:|LibClamAV", line):
        real = True
if real:
    sys.stdout.write("error")
else:
    sys.stdout.write("ok")
