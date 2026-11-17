#!/usr/bin/env python3
# =============================================================================
# File       : python/alert-excerpt.py
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Build a short watchdog excerpt from one log.
# Note       : Secrets are masked before line selection.
# -----------------------------------------------------------------------------


import os
import re
import sys
from pathlib import Path

import text_redact

EXCERPT_MORE = os.environ.get(
    "TEXT_EXCERPT_MORE",
    "... {1} ligne(s) supplémentaire(s) non recopiées",
)
EXCERPT_ATTR = os.environ.get(
    "TEXT_EXCERPT_ATTR",
    "... {1} ligne(s) d'attribut supplémentaire(s) non recopiées",
)
REDACTED = os.environ.get("TEXT_REDACTED", "[masqué]")
REDACTED_KEY = os.environ.get("TEXT_REDACTED_KEY", "[clé privée masquée]")

# Headings are matched on the trimmed line.
SUMMARY = re.compile(
    r"^(summary:|total number|added entries|removed entries|changed entries|"
    r"added, removed and changed entries|added and removed entries|"
    r"added and changed entries|removed and changed entries|"
    r"detailed information about changes|"
    r"aide found|start timestamp|end timestamp)\b",
    re.I,
)
# A type letter and the path stay. So does a plain added, removed, or changed line.
ENTRY = re.compile(r"^(?:[fdlcbpsDP!?][+.\-:=> <?A-Za-z]*:\s+\S|(?:added|removed|changed):\s+\S)")
# AIDE repeats the path on its own header, such as Link or Directory.
FILE_HEAD = re.compile(
    r"^(?:file|directory|fifo|link|block device|character device|"
    r"socket|door|port|unknown file type):\s+\S",
    re.I,
)
DIFF_ATTR = re.compile(
    r"^entry \S+ in databases has different attributes\b",
    re.I,
)
# Lines under this header describe aide.db, so the excerpt stops.
DATABASE = re.compile(
    r"^the attributes of the \(uncompressed\) database\b",
    re.I,
)
ATTR = re.compile(r"^\s+\S.*:")
CLAM_FOOTER = (
    r"Known viruses:|Infected files:|Engine version:|Scanned directories:|"
    r"Scanned files:|Data scanned:|Data read:|Time:|Start Date:|End Date:"
)
CLAM_REFUSED = r"Access denied|Can't access|Can't open file|Permission denied|No such file"


def fill_count(template, count):
    # Only {1} becomes the count. Any other brace number stays.

    def replace_found(found):
        if found.group(1) == "1":
            return str(count)
        return found.group(0)

    return re.sub(r"\{(\d+)\}", replace_found, template)


def clip_lines(lines):
    # The excerpt keeps the first 120 lines and names how many were left out.
    if len(lines) <= 120:
        return lines
    hidden = len(lines) - 120
    return lines[:120] + [fill_count(EXCERPT_MORE, hidden)]


def read_log(path):
    if path and Path(path).is_file():
        return Path(path).read_text(errors="replace")
    return ""


def redact(text):
    return text_redact.redact_excerpt(text, REDACTED, REDACTED_KEY)


def nonempty_lines(text):
    return [line.rstrip() for line in text.splitlines() if line.strip()]


def leading_clock(stripped):
    # Both scanners skip a line that opens with an ISO timestamp.
    return re.match(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T", stripped)


def aide_keep(raw, stripped):
    if SUMMARY.match(stripped):
        return True
    if ENTRY.match(raw) or FILE_HEAD.match(raw):
        return True
    return DIFF_ATTR.match(raw) is not None


def aide_row(line):
    raw = line.rstrip()
    stripped = raw.strip()
    if not stripped:
        return None
    if DATABASE.match(stripped):
        return ("database", raw)
    if aide_keep(raw, stripped):
        return ("keep", raw)
    if ATTR.match(raw):
        return ("attr", raw)
    return None


def aide_rows(text):
    rows = []
    for line in text.splitlines():
        row = aide_row(line)
        if row is None:
            continue
        if row[0] == "database":
            break
        rows.append(row)
    return rows


def limit_attrs(rows):
    # Forty attribute lines stay. The rest become one count.
    kept = []
    room = 40
    hidden = 0
    for kind, raw in rows:
        if kind == "keep":
            kept.append(raw)
        elif room > 0:
            kept.append(raw)
            room -= 1
        else:
            hidden += 1
    if hidden:
        kept.append(fill_count(EXCERPT_ATTR, hidden))
    return kept


def format_aide(text):
    return limit_attrs(aide_rows(text))


def rkhunter_drop(line, stripped):
    # A version banner is dropped, even when it also names a rootkit.
    if not stripped:
        return True
    if re.search(r"Rootkit Hunter version", line, re.I):
        return True
    return leading_clock(stripped) is not None


def rkhunter_hit(line):
    return re.search(r"warning|infected|rootkit|suspect|quarantaine", line, re.I)


def rkhunter_follow(line, stripped):
    # A hit keeps the indented lines and paths that follow it.
    return line[:1] in (" ", "\t") or stripped.startswith("/")


def format_rkhunter(text):
    # A blank line ends that group.
    picked = []
    keep = False
    for raw in text.splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        if rkhunter_drop(line, stripped):
            keep = False
            continue
        if rkhunter_hit(line):
            keep = True
            picked.append(line)
            continue
        if keep and rkhunter_follow(line, stripped):
            picked.append(line)
            continue
        keep = False
    return clip_lines(picked)


def clam_noise(line, stripped):
    # The scanner footer and refused files are noise.
    if leading_clock(stripped):
        return True
    if re.search(CLAM_FOOTER, line):
        return True
    return re.search(CLAM_REFUSED, line, re.I) is not None


def clam_hit(line, stripped):
    # A FOUND line is a hit.
    if "planté signal" in line or "contrôle arrêté" in line:
        return True
    if stripped.endswith(" FOUND") or re.search(
        r"Signature|Fichier|Emplacement|Quarantaine",
        line,
    ):
        return True
    return re.search(r"ERROR:|LibClamAV", line) is not None


def format_clam(text):
    # Noise is decided first, so a footer that also says FOUND is dropped.
    picked = []
    for raw in text.splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        if not stripped or clam_noise(line, stripped):
            continue
        if clam_hit(line, stripped):
            picked.append(line)
    return clip_lines(picked)


def format_named(name, text):
    # The file name is a substring. aide comes first, then rkhunter, then clam.
    # An empty aide selection falls back to the generic line cap.
    low = name.lower()
    if "aide" in low:
        picked = format_aide(text)
        if picked:
            return picked
        return clip_lines(nonempty_lines(text))
    if "rkhunter" in low:
        return format_rkhunter(text)
    if "clam" in low:
        return format_clam(text)
    return clip_lines(nonempty_lines(text))


def write_excerpt(path):
    raw = read_log(path)
    name = Path(path).name if path else ""
    body = format_named(name, redact(raw))
    if body:
        sys.stdout.write("\n".join(body))


write_excerpt(sys.argv[1])
