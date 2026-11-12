#!/usr/bin/env python3
# =============================================================================
# File       : python/alert-quarantine.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import re
import sys
from pathlib import Path

source = sys.argv[1]
log_path = Path(sys.argv[2])
text = log_path.read_text(errors="replace") if log_path.is_file() else ""
path_re = re.compile(r"(/[^\s<>|,;]+)")
seen = []
for raw in text.splitlines():
    line = raw.rstrip()
    if source == "rkhunter":
        if "Rootkit Hunter" in line:
            hit = "INFECTED" in line
        else:
            hit = ("INFECTED" in line) or ("Rootkit" in line)
    else:
        hit = "INFECTED" in line
    if not hit:
        continue
    for match in path_re.findall(line):
        path = match.rstrip(".,:)")
        if path not in seen:
            seen.append(path)
if seen:
    sys.stdout.write("\n".join(seen) + "\n")
