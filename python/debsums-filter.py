#!/usr/bin/env python3
# =============================================================================
# File       : python/debsums-filter.py
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Drop known debsums noise, or store one accepted detection.
# Note       : The mirror file stays quiet only when its hash still matches the saved stamp.
# -----------------------------------------------------------------------------


import hashlib
import re
import sys
from pathlib import Path


MIRROR_FLEXIBLE = re.compile(
    r"^(?:debsums: changed file )?(/var/lib/rkhunter/db/mirrors\.dat)(?: \(from rkhunter package\))?\s*$"
)
UNICORE_FLEXIBLE = re.compile(
    r"^(?:debsums: changed file )?(/usr/lib/\S+/perl-base/unicore/\S+)(?: \(from perl-base package\))?\s*$"
)
MIRROR_STRICT = r"^debsums: changed file /var/lib/rkhunter/db/mirrors\.dat \(from rkhunter package\)\s*$"
UNICORE_STRICT = r"^debsums: changed file /usr/lib/\S+/perl-base/unicore/\S+ \(from perl-base package\)\s*$"
LOCAL_HEADER = (
    "# Faux positifs ajoutés par l'administrateur du poste.\n# Une expression Python par ligne. Pas de ligne vide.\n"
)


def compile_ignore(path):
    # A broken expression is skipped. The other lines still apply.
    compiled = []
    if not path.is_file():
        return compiled
    for raw in path.read_text(errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        try:
            compiled.append(re.compile(line))
        except re.error:
            continue
    return compiled


def pattern_hits(line, patterns):
    return any(pattern.search(line) for pattern in patterns)


def patterns_of(ignore_paths):
    patterns = []
    for ignore_path in ignore_paths:
        patterns.extend(compile_ignore(Path(ignore_path)))
    return patterns


def write_kept(path, lines):
    path.write_text(("\n".join(lines) + "\n") if lines else "")


def mirror_matches(stamp_path):
    # The stamp file holds one hash. The mirror file stays at its usual path.
    mirror = Path("/var/lib/rkhunter/db/mirrors.dat")
    if not stamp_path.is_file() or not mirror.is_file():
        return False
    parts = stamp_path.read_text(errors="replace").split()
    saved = parts[0] if parts else ""
    current = hashlib.sha256(mirror.read_bytes()).hexdigest()
    return bool(saved) and current == saved


def filter_server(log_path, base_text):
    # Blank lines stay. A mirror line leaves only when the saved hash still matches.
    stamp = Path(base_text) / "cron" / "rkhunter-mirrors.sha256"
    accepted = mirror_matches(stamp)
    kept = []
    for raw in Path(log_path).read_text(errors="replace").splitlines():
        stripped = raw.strip()
        if accepted and MIRROR_FLEXIBLE.match(stripped):
            continue
        if UNICORE_FLEXIBLE.match(stripped):
            continue
        kept.append(raw)
    write_kept(Path(log_path), kept)


def workstation_noise(line, patterns, accepted):
    if pattern_hits(line, patterns):
        return True
    if accepted and re.search(MIRROR_STRICT, line):
        return True
    return re.search(UNICORE_STRICT, line) is not None


def filter_workstation(log_path, ignore_paths, base_text):
    # Blank lines leave. These patterns require the full debsums sentence.
    patterns = patterns_of(ignore_paths)
    stamp = Path(base_text) / "cron" / "rkhunter-mirrors.sha256"
    accepted = mirror_matches(stamp)
    kept = []
    for line in Path(log_path).read_text(errors="replace").splitlines():
        if line.strip() and not workstation_noise(line, patterns, accepted):
            kept.append(line)
    write_kept(Path(log_path), kept)


def report_path(log_path, logs, wrong_dir, wrong_name, prefix):
    try:
        log_path.relative_to(logs)
    except ValueError:
        sys.stderr.write(wrong_dir)
        sys.exit(1)
    if not log_path.name.startswith(prefix) or log_path.suffix != ".log":
        sys.stderr.write(wrong_name)
        sys.exit(1)


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
    # The clock and the tool's own summary are not detections.
    if not line or line.startswith("#"):
        return True
    if re.match(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T", line):
        return True
    return line.startswith("debsums : fichiers") or line.startswith("debsums OK")


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
        "Ce journal n'est pas un relevé debsums du poste.\n",
        "Le fichier attendu se nomme debsums-DATE.log.\n",
        "debsums-",
    )
    local = base / "cron" / "debsums.local.ignore"
    shipped = base / "cron" / "bin" / "debsums.ignore"
    known = named_patterns(shipped) + named_patterns(local)
    added = patterns_to_add(log_path.read_text(errors="replace").splitlines(), known)
    store_accepted(local, added, "# Détections acceptées depuis un e-mail debsums.")


def run_filter():
    mode = sys.argv[1]
    rest = sys.argv[2:]
    if mode == "server":
        filter_server(rest[0], rest[1])
        return
    if mode == "ignore":
        accept_from_mail(rest[0], rest[1])
        return
    if mode == "workstation":
        filter_workstation(rest[0], rest[1:3], rest[3])
        return
    sys.exit("mode python refusé")


run_filter()
