#!/usr/bin/env python3
# =============================================================================
# File       : python/chkrootkit-filter.py
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Keep the chkrootkit lines that still deserve a mail, or store one accepted detection.
# Note       : A warning title with nothing under it is dropped.
# -----------------------------------------------------------------------------


import re
import sys
from pathlib import Path


# These four titles stay only when at least one line follows them.
HEADERS = {
    "WARNING: The following suspicious files and directories were found:",
    "WARNING: Possible Linux BPFDoor Malware installed:",
    "WARNING: output from chkwtmp:",
    "WARNING: Output from ifpromisc:",
}
LOCAL_HEADER = (
    "# Faux positifs ajoutés par l'administrateur du poste.\n# Une expression Python par ligne. Pas de ligne vide.\n"
)


def compile_ignore(path, skip_invalid):
    # The server filter lets a broken expression stop the run.
    # The workstation filter skips that expression and keeps going.
    compiled = []
    if not path.is_file():
        return compiled
    for raw in path.read_text(errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if skip_invalid:
            try:
                compiled.append(re.compile(line))
            except re.error:
                continue
        else:
            compiled.append(re.compile(line))
    return compiled


def pattern_hits(line, patterns):
    return any(pattern.search(line) for pattern in patterns)


def section_body(kept, start):
    # The body stops at the next title, or at a line that starts with "Checking ".
    body = []
    cursor = start + 1
    while cursor < len(kept) and kept[cursor] not in HEADERS and not kept[cursor].startswith("Checking "):
        body.append(kept[cursor])
        cursor += 1
    return body, cursor


def drop_empty_sections(kept):
    # A title with nothing under it is left out. The next line is checked on its own.
    chosen = []
    cursor = 0
    while cursor < len(kept):
        line = kept[cursor]
        if line in HEADERS:
            body, cursor = section_body(kept, cursor)
            if body:
                chosen.append(line)
                chosen.extend(body)
            continue
        chosen.append(line)
        cursor += 1
    return chosen


def write_kept(path, lines):
    path.write_text(("\n".join(lines) + "\n") if lines else "")


def filter_server(raw_path, log_path, ignore_path):
    # Patterns are read first, so a broken one leaves the output log untouched.
    patterns = compile_ignore(Path(ignore_path), False)
    raw = Path(raw_path)
    text = raw.read_text(errors="replace") if raw.is_file() else ""
    kept = [line for line in text.splitlines() if line.strip() and not pattern_hits(line, patterns)]
    write_kept(Path(log_path), drop_empty_sections(kept))


def filter_workstation(log_path, ignore_paths):
    patterns = []
    for ignore_path in ignore_paths:
        patterns.extend(compile_ignore(Path(ignore_path), True))
    text = Path(log_path).read_text(errors="replace")
    kept = [line for line in text.splitlines() if line.strip() and not pattern_hits(line, patterns)]
    write_kept(Path(log_path), drop_empty_sections(kept))


def report_path(log_path, logs, wrong_directory, wrong_name, prefix):
    try:
        log_path.relative_to(logs)
    except ValueError:
        sys.stderr.write(wrong_directory)
        sys.exit(1)
    if not log_path.name.startswith(prefix) or log_path.suffix != ".log":
        sys.stderr.write(wrong_name)
        sys.exit(1)


def shipped_path(base):
    shipped = base / "src" / "config" / "chkrootkit" / "patterns.ignore"
    if shipped.is_file():
        return shipped
    return base / "cron" / "bin" / "chkrootkit.ignore"


def named_patterns(path):
    # A broken expression is reported and left out of the known list.
    found = []
    if not path.is_file():
        return found
    for raw in path.read_text(errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        try:
            found.append((line, re.compile(line)))
        except re.error:
            sys.stderr.write(f"Expression ignorée, elle est invalide : {line}\n")
    return found


def noise_line(line):
    # Titles, the clock, and the tool's own banner are not detections.
    if not line or line.startswith("#") or line in HEADERS:
        return True
    if re.match(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T", line):
        return True
    return line.startswith("chkrootkit a produit une sortie")


def known_hit(line, known):
    return any(compiled.search(line) for _text, compiled in known)


def patterns_to_add(lines, known):
    # Each new detection becomes one full-line expression, stored once.
    known_text = {text for text, _compiled in known}
    added = []
    for raw in lines:
        line = raw.strip()
        if noise_line(line) or known_hit(line, known):
            continue
        pattern = "^" + re.escape(line) + "$"
        if pattern in known_text or pattern in added:
            continue
        added.append(pattern)
    return added


def store_accepted(local, added, title):
    if not added:
        print("Aucune nouvelle détection à enregistrer.")
        sys.exit(0)
    local.parent.mkdir(parents=True, exist_ok=True)
    block = ["", title]
    block.extend(added)
    if local.is_file():
        existing = local.read_text(errors="replace")
    else:
        existing = LOCAL_HEADER
    # The leading blank in the block is removed, so the new title stays on the next line.
    text = existing.rstrip("\n") + "\n" + "\n".join(block).lstrip("\n")
    if not text.endswith("\n"):
        text += "\n"
    temporary = local.with_suffix(".ignore.tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(local)
    print(f"{len(added)} détection(s) enregistrée(s) dans {local}")
    for pattern in added:
        print(pattern)


def accept_from_mail(base_text, log_text):
    # Refuse a journal that is not the dated security log before reading ignore files.
    base = Path(base_text).resolve()
    log_path = Path(log_text).resolve()
    logs = (base / "cron" / "security_logs").resolve()
    report_path(
        log_path,
        logs,
        "Ce journal n'est pas un relevé chkrootkit du poste.\n",
        "Le fichier attendu se nomme chkrootkit-DATE.log.\n",
        "chkrootkit-",
    )
    local = base / "cron" / "chkrootkit.local.ignore"
    known = named_patterns(shipped_path(base)) + named_patterns(local)
    added = patterns_to_add(log_path.read_text(errors="replace").splitlines(), known)
    store_accepted(local, added, "# Détections acceptées depuis un e-mail chkrootkit.")


def run_filter():
    mode = sys.argv[1]
    rest = sys.argv[2:]
    if mode == "server":
        filter_server(rest[0], rest[1], rest[2])
        return
    if mode == "ignore":
        accept_from_mail(rest[0], rest[1])
        return
    if mode == "workstation":
        filter_workstation(rest[0], rest[1:])
        return
    sys.exit("mode python refusé")


if __name__ == "__main__":
    run_filter()
