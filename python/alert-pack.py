#!/usr/bin/env python3
# =============================================================================
# File       : python/alert-pack.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import os
import zipfile
from pathlib import Path

import text_redact

phase, state_dir, log_dir, dest = sys_parts = __import__("sys").argv[1:5]
state = Path(state_dir)
logs = Path(log_dir) if log_dir else None
target = Path(dest)
secret_names = {"secrets.conf", "id_ed25519", "id_ed25519.pub"}


def redact(text):
    return text_redact.redact_pack(text)


def allowed(path):
    name = path.name
    if name in secret_names or name.endswith(".key") or name.startswith("id_ed25519"):
        return False
    return True


def add_text(archive, arcname, text):
    archive.writestr(arcname, redact(text))


with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    chunks = [f"phase: {phase}"]
    for name in ("status", "services.txt", "files.txt", "actions.txt", "rows.tsv"):
        path = state / name
        if path.is_file():
            chunks.append("")
            chunks.append(f"== {name}")
            chunks.append(path.read_text(errors="replace"))
    add_text(archive, "manifest.txt", "\n".join(chunks).rstrip() + "\n")
    if logs and logs.is_dir():
        for path in sorted(logs.iterdir()):
            if path.is_file() and allowed(path) and not path.name.startswith("alert-"):
                add_text(archive, f"logs/{path.name}", path.read_text(errors="replace"))
    for chunk in (os.environ.get("WATCHDOG_EXCLUDES") or "").split(":"):
        if not chunk:
            continue
        exclude = Path(chunk)
        if exclude.is_file() and allowed(exclude):
            add_text(archive, f"exclude/{exclude.name}", exclude.read_text(errors="replace"))
    for label, candidate in (
        ("apt-history.txt", Path("/var/log/apt/history.log")),
        ("dpkg.log", Path("/var/log/dpkg.log")),
    ):
        if not candidate.is_file():
            continue
        lines = candidate.read_text(errors="replace").splitlines()
        add_text(archive, label, "\n".join(lines[-400:]) + "\n")
