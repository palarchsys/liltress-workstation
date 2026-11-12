#!/usr/bin/env python3
# =============================================================================
# File       : python/chkrootkit-filter.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import sys

mode = sys.argv[1]
sys.argv = [sys.argv[0]] + sys.argv[2:]

if mode == 'server':
    import re
    import sys
    from pathlib import Path

    raw_path, log_path, ignore_path = sys.argv[1], sys.argv[2], sys.argv[3]
    patterns = []
    ignore = Path(ignore_path)
    if ignore.is_file():
        for raw in ignore.read_text(errors="replace").splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            patterns.append(re.compile(line))

    def ignored(line):
        return any(p.search(line) for p in patterns)

    text = Path(raw_path).read_text(errors="replace") if Path(raw_path).is_file() else ""
    kept = [line for line in text.splitlines() if line.strip() and not ignored(line)]
    headers = {
        "WARNING: The following suspicious files and directories were found:",
        "WARNING: Possible Linux BPFDoor Malware installed:",
        "WARNING: output from chkwtmp:",
        "WARNING: Output from ifpromisc:",
    }
    out = []
    i = 0
    while i < len(kept):
        line = kept[i]
        if line in headers:
            body = []
            j = i + 1
            while j < len(kept) and kept[j] not in headers and not kept[j].startswith("Checking "):
                body.append(kept[j])
                j += 1
            if body:
                out.append(line)
                out.extend(body)
            i = j
            continue
        out.append(line)
        i += 1
    Path(log_path).write_text(("\n".join(out) + "\n") if out else "")
elif mode == 'ignore':
    import re
    import sys
    from pathlib import Path

    base = Path(sys.argv[1]).resolve()
    log_path = Path(sys.argv[2]).resolve()
    logs = (base / "cron" / "security_logs").resolve()
    local = base / "cron" / "chkrootkit.local.ignore"
    shipped = base / "src" / "config" / "chkrootkit" / "patterns.ignore"
    legacy = base / "cron" / "bin" / "chkrootkit.ignore"
    if not shipped.is_file():
        shipped = legacy

    try:
        log_path.relative_to(logs)
    except ValueError:
        sys.stderr.write("Ce journal n'est pas un relevé chkrootkit du poste.\n")
        sys.exit(1)
    if not log_path.name.startswith("chkrootkit-") or log_path.suffix != ".log":
        sys.stderr.write("Le fichier attendu se nomme chkrootkit-DATE.log.\n")
        sys.exit(1)

    headers = {
        "WARNING: The following suspicious files and directories were found:",
        "WARNING: Possible Linux BPFDoor Malware installed:",
        "WARNING: output from chkwtmp:",
        "WARNING: Output from ifpromisc:",
    }

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
        if not line or line.startswith("#") or line in headers:
            continue
        if re.match(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T", line):
            continue
        if line.startswith("chkrootkit a produit une sortie"):
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
    block = ["", "# Détections acceptées depuis un e-mail chkrootkit."]
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
    import re
    import sys
    from pathlib import Path

    log_path = sys.argv[1]
    patterns = []
    for ignore_path in sys.argv[2:]:
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

    def ignored(line):
        return any(p.search(line) for p in patterns)

    kept = [line for line in Path(log_path).read_text(errors="replace").splitlines() if line.strip() and not ignored(line)]
    headers = {
        "WARNING: The following suspicious files and directories were found:",
        "WARNING: Possible Linux BPFDoor Malware installed:",
        "WARNING: output from chkwtmp:",
        "WARNING: Output from ifpromisc:",
    }
    out = []
    i = 0
    while i < len(kept):
        line = kept[i]
        if line in headers:
            body = []
            j = i + 1
            while j < len(kept) and kept[j] not in headers and not kept[j].startswith("Checking "):
                body.append(kept[j])
                j += 1
            if body:
                out.append(line)
                out.extend(body)
            i = j
            continue
        out.append(line)
        i += 1
    Path(log_path).write_text(("\n".join(out) + "\n") if out else "")
else:
    sys.exit('mode python refusé')
