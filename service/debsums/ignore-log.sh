#!/usr/bin/env bash
# =============================================================================
# File       : service/debsums/ignore-log.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

set -euo pipefail
W_BASE="${W_BASE:-/opt/liltress-workstation}"
if [[ "${EUID}" -ne 0 ]]; then
    printf "$(get_text log.run-this-command-with-sudo-n)" >&2
    exit 1
fi
if [[ $# -ne 1 || ! -f "$1" ]]; then
    printf "$(get_text log.enter-the-journal-debsums-named-in-l)"\''e-mail.\n' >&2
    printf "$(get_text log.example-sudo-bash-bin-debsums-ignore-log-sh-cron "${W_BASE}" "${W_BASE}")" >&2
    exit 1
fi

python3 - "${W_BASE}" "$1" << 'PY'
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
PY
