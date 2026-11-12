#!/usr/bin/env python3
# =============================================================================
# File       : python/debsums-filter.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import sys

mode = sys.argv[1]
sys.argv = [sys.argv[0]] + sys.argv[2:]

if mode == 'server':
    import hashlib
    import re
    import sys
    from pathlib import Path

    log_path = Path(sys.argv[1])
    stamp = Path(sys.argv[2]) / "cron" / "rkhunter-mirrors.sha256"
    mirror = Path("/var/lib/rkhunter/db/mirrors.dat")
    saved = ""
    current = ""
    if stamp.is_file() and mirror.is_file():
        parts = stamp.read_text(errors="replace").split()
        saved = parts[0] if parts else ""
        current = hashlib.sha256(mirror.read_bytes()).hexdigest()
    accepted = bool(saved) and current == saved
    pattern = re.compile(
        r"^(?:debsums: changed file )?(/var/lib/rkhunter/db/mirrors\.dat)(?: \(from rkhunter package\))?\s*$"
    )
    unicore = re.compile(
        r"^(?:debsums: changed file )?(/usr/lib/\S+/perl-base/unicore/\S+)(?: \(from perl-base package\))?\s*$"
    )

    kept = []
    for raw in log_path.read_text(errors="replace").splitlines():
        stripped = raw.strip()
        if accepted and pattern.match(stripped):
            continue
        if unicore.match(stripped):
            continue
        kept.append(raw)
    log_path.write_text(("\n".join(kept) + "\n") if kept else "")
elif mode == 'ignore':
    import re
    import sys
    from pathlib import Path

    base = Path(sys.argv[1]).resolve()
    log_path = Path(sys.argv[2]).resolve()
    logs = (base / "cron" / "security_logs").resolve()
    local = base / "cron" / "debsums.local.ignore"
    shipped = base / "cron" / "bin" / "debsums.ignore"

    try:
        log_path.relative_to(logs)
    except ValueError:
        sys.stderr.write("Ce journal n'est pas un relevé debsums du poste.\n")
        sys.exit(1)
    if not log_path.name.startswith("debsums-") or log_path.suffix != ".log":
        sys.stderr.write("Le fichier attendu se nomme debsums-DATE.log.\n")
        sys.exit(1)

    def load_patterns(path):
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

    known = load_patterns(shipped) + load_patterns(local)
    known_text = {text for text, _ in known}

    def already(line):
        return any(pat.search(line) for _, pat in known)

    added = []
    for raw in log_path.read_text(errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if re.match(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T", line):
            continue
        if line.startswith("debsums : fichiers") or line.startswith("debsums OK"):
            continue
        if already(line):
            continue
        pattern = "^" + re.escape(line) + "$"
        if pattern in known_text or pattern in added:
            continue
        added.append(pattern)

    if not added:
        print("Aucune nouvelle détection à enregistrer.")
        sys.exit(0)

    local.parent.mkdir(parents=True, exist_ok=True)
    block = ["", "# Détections acceptées depuis un e-mail debsums."]
    block.extend(added)
    existing = local.read_text(errors="replace") if local.is_file() else (
        "# Faux positifs ajoutés par l'administrateur du poste.\n"
        "# Une expression Python par ligne. Pas de ligne vide.\n"
    )
    text = existing.rstrip("\n") + "\n" + "\n".join(block).lstrip("\n")
    if not text.endswith("\n"):
        text += "\n"
    tmp = local.with_suffix(".ignore.tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(local)
    print(f"{len(added)} détection(s) enregistrée(s) dans {local}")
    for pattern in added:
        print(pattern)
elif mode == 'workstation':
    import hashlib
    import re
    import sys
    from pathlib import Path

    log_path = Path(sys.argv[1])
    base = Path(sys.argv[4])
    patterns = []
    for ignore_path in sys.argv[2:4]:
        path = Path(ignore_path)
        if not path.is_file():
            continue
        for raw in path.read_text(errors="replace").splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            try:
                patterns.append(re.compile(line))
            except re.error:
                continue

    stamp = base / "cron" / "rkhunter-mirrors.sha256"
    mirror = Path("/var/lib/rkhunter/db/mirrors.dat")
    saved = ""
    current = ""
    if stamp.is_file() and mirror.is_file():
        parts = stamp.read_text(errors="replace").split()
        saved = parts[0] if parts else ""
        current = hashlib.sha256(mirror.read_bytes()).hexdigest()

    def ignored(line):
        if any(p.search(line) for p in patterns):
            return True
        if saved and current == saved and re.search(
            r"^debsums: changed file /var/lib/rkhunter/db/mirrors\.dat \(from rkhunter package\)\s*$",
            line,
        ):
            return True
        if re.search(
            r"^debsums: changed file /usr/lib/\S+/perl-base/unicore/\S+ \(from perl-base package\)\s*$",
            line,
        ):
            return True
        return False

    kept = [
        line
        for line in log_path.read_text(errors="replace").splitlines()
        if line.strip() and not ignored(line)
    ]
    log_path.write_text(("\n".join(kept) + "\n") if kept else "")
else:
    sys.exit('mode python refusé')
