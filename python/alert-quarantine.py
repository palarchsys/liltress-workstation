#!/usr/bin/env python3
# =============================================================================
# File       : python/alert-quarantine.py
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Print the infected paths found in one watchdog log.
# -----------------------------------------------------------------------------


import re
import sys
from pathlib import Path

PATH_RE = re.compile(r"(/[^\s<>|,;]+)")


def line_is_hit(source, line):
    # The rkhunter banner contains the word Rootkit. It is a finding only with INFECTED.
    if source == "rkhunter" and "Rootkit Hunter" in line:
        return "INFECTED" in line
    if source == "rkhunter":
        return ("INFECTED" in line) or ("Rootkit" in line)
    return "INFECTED" in line


def infected_paths(source, log_path):
    text = log_path.read_text(errors="replace") if log_path.is_file() else ""
    seen = []
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line_is_hit(source, line):
            continue
        for match in PATH_RE.findall(line):
            path = match.rstrip(".,:)")
            if path not in seen:
                seen.append(path)
    return seen


if __name__ == "__main__":
    found = infected_paths(sys.argv[1], Path(sys.argv[2]))
    if found:
        sys.stdout.write("\n".join(found) + "\n")
