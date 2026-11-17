#!/usr/bin/env python3
# =============================================================================
# File       : python/clamav-kind.py
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Classify a ClamAV log as infected, error, or ok.
# Note       : The word is written with no trailing newline.
# -----------------------------------------------------------------------------


import re
import sys
from pathlib import Path

ACCESS_RE = re.compile(
    r"Access denied|Can't access|Can't open file|Permission denied|No such file",
    re.I,
)
SUMMARY_RE = re.compile(
    r"Known viruses:|Infected files:|Engine version:|Scanned directories:|"
    r"Scanned files:|Data scanned:|Data read:|^Time:|Start Date:|End Date:"
)


def read_log(argument):
    if not argument:
        return ""
    path = Path(argument)
    if not path.is_file():
        return ""
    return path.read_text(errors="replace")


def line_is_noise(line):
    # The footer, a refused file, and the clock line are the scanner talking, not a fault.
    if not line:
        return True
    if SUMMARY_RE.search(line) or ACCESS_RE.search(line):
        return True
    if line.startswith("-----------"):
        return True
    if re.match(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T", line):
        return True
    return False


def kind_of(text):
    # FOUND is a detection. It wins over a later error line.
    if re.search(r" FOUND$", text, re.M):
        return "infected"
    real = False
    for raw in text.splitlines():
        line = raw.strip()
        if line_is_noise(line):
            continue
        if re.search(r"ERROR:|LibClamAV", line):
            real = True
    if real:
        return "error"
    return "ok"


argument = sys.argv[1] if len(sys.argv) > 1 else ""
sys.stdout.write(kind_of(read_log(argument)))
