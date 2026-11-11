#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/excerpt.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================


get_alert_excerpt() {
    load_text "${LANGUAGE:-en}"
    TEXT_EXCERPT_MORE="$(get_text alert.excerpt.more)" \
    TEXT_EXCERPT_ATTR="$(get_text alert.excerpt.attr)" \
    TEXT_REDACTED="$(get_text mail.redacted)" \
    TEXT_REDACTED_KEY="$(get_text mail.redacted-key)" \
    python3 - "${1:-}" << 'PY'
import os
import re
import sys
from pathlib import Path

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

def fill_count(template, count):
    def repl(match):
        if match.group(1) == "1":
            return str(count)
        return match.group(0)

    return re.sub(r"\{(\d+)\}", repl, template)

path = sys.argv[1]
raw = ""
if path and Path(path).is_file():
    raw = Path(path).read_text(errors="replace")

def redact(text):
    text = re.sub(
        r"(?is)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----",
        lambda _match: REDACTED_KEY,
        text,
    )
    text = re.sub(
        r"(?i)\b(password|passwd|token|secret|api[_-]?key|authorization|bearer)\b(\s*[:=]\s*)\S+",
        lambda match: match.group(1) + match.group(2) + REDACTED,
        text,
    )
    text = re.sub(
        r"(?i)\bbearer\s+[A-Za-z0-9._~+/-]{8,}",
        lambda _match: "Bearer " + REDACTED,
        text,
    )
    return text

def clip(lines, limit=120):
    if len(lines) <= limit:
        return lines
    hidden = len(lines) - limit
    return lines[:limit] + [fill_count(EXCERPT_MORE, hidden)]

def format_aide(text):
    summary = re.compile(
        r"^(summary:|total number|added entries|removed entries|changed entries|"
        r"added, removed and changed entries|added and removed entries|"
        r"added and changed entries|removed and changed entries|"
        r"detailed information about changes|"
        r"aide found|start timestamp|end timestamp)\b",
        re.I,
    )
    # Type letter plus the summary field, or the plain added/removed/changed form.
    # The whole line is the path. A path line is never dropped.
    entry = re.compile(
        r"^(?:[fdlcbpsDP!?][+.\-:=> <?A-Za-z]*:\s+\S|(?:added|removed|changed):\s+\S)"
    )
    # Detail header. AIDE names the path again: "Link: /path", "Directory: /path".
    file_head = re.compile(
        r"^(?:file|directory|fifo|link|block device|character device|"
        r"socket|door|port|unknown file type):\s+\S",
        re.I,
    )
    diff_attrs = re.compile(
        r"^entry \S+ in databases has different attributes\b",
        re.I,
    )
    # Lines after this header describe aide.db, not a watched path.
    database = re.compile(
        r"^the attributes of the \(uncompressed\) database\b",
        re.I,
    )
    attr = re.compile(r"^\s+\S.*:")
    rows = []
    for line in text.splitlines():
        raw = line.rstrip()
        stripped = raw.strip()
        if not stripped:
            continue
        if database.match(stripped):
            break
        if (
            summary.match(stripped)
            or entry.match(raw)
            or file_head.match(raw)
            or diff_attrs.match(raw)
        ):
            rows.append(("keep", raw))
        elif attr.match(raw):
            rows.append(("attr", raw))
    out = []
    attr_left = 40
    hidden_attr = 0
    for kind, raw in rows:
        if kind == "keep":
            out.append(raw)
        elif attr_left > 0:
            out.append(raw)
            attr_left -= 1
        else:
            hidden_attr += 1
    if hidden_attr:
        out.append(fill_count(EXCERPT_ATTR, hidden_attr))
    return out

def format_named(name, text):
    low = name.lower()
    lines = [ln.rstrip() for ln in text.splitlines() if ln.strip()]
    if "aide" in low:
        picked = format_aide(text)
        return picked or clip(lines)
    if "rkhunter" in low:
        picked = []
        keep = False
        for raw in text.splitlines():
            line = raw.rstrip()
            stripped = line.strip()
            if not stripped:
                keep = False
                continue
            if re.search(r"Rootkit Hunter version", line, re.I):
                keep = False
                continue
            if re.match(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T", stripped):
                keep = False
                continue
            if re.search(r"warning|infected|rootkit|suspect|quarantaine", line, re.I):
                keep = True
                picked.append(line)
                continue
            if keep and (line[:1] in (" ", "\t") or stripped.startswith("/")):
                picked.append(line)
                continue
            keep = False
        return clip(picked)
    if "clam" in low:
        picked = []
        for raw in text.splitlines():
            line = raw.rstrip()
            stripped = line.strip()
            if not stripped:
                continue
            if re.match(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T", stripped):
                continue
            if re.search(
                r"Known viruses:|Infected files:|Engine version:|Scanned directories:|"
                r"Scanned files:|Data scanned:|Data read:|Time:|Start Date:|End Date:",
                line,
            ):
                continue
            if re.search(
                r"Access denied|Can't access|Can't open file|Permission denied|No such file",
                line,
                re.I,
            ):
                continue
            if "planté signal" in line or "contrôle arrêté" in line:
                picked.append(line)
                continue
            if stripped.endswith(" FOUND") or re.search(
                r"Signature|Fichier|Emplacement|Quarantaine", line
            ):
                picked.append(line)
                continue
            if re.search(r"ERROR:|LibClamAV", line):
                picked.append(line)
        return clip(picked)
    return clip(lines)

name = Path(path).name if path else ""
body = format_named(name, redact(raw))
if body:
    sys.stdout.write("\n".join(body))
PY
}
