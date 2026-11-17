#!/usr/bin/env python3
# =============================================================================
# File       : python/alert-pack.py
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Build the zip attached to one watchdog alert.
# Note       : Secret files stay out, and the host package logs keep their last 400 lines.
# -----------------------------------------------------------------------------


import os
import sys
import zipfile
from pathlib import Path

import text_redact

SECRET_NAMES = {"secrets.conf", "id_ed25519", "id_ed25519.pub"}
STATE_NAMES = ("status", "services.txt", "files.txt", "actions.txt", "rows.tsv")
HOST_LOGS = (
    ("apt-history.txt", Path("/var/log/apt/history.log")),
    ("dpkg.log", Path("/var/log/dpkg.log")),
)
TAIL_LINES = 400


def redact(text):
    return text_redact.redact_pack(text)


def allowed(path):
    # A private key file stays out of the archive.
    name = path.name
    if name in SECRET_NAMES:
        return False
    if name.endswith(".key"):
        return False
    if name.startswith("id_ed25519"):
        return False
    return True


def add_text(archive, arcname, text):
    archive.writestr(arcname, redact(text))


def manifest_text(phase, state):
    # Each present state file gets a blank line and a heading.
    # Whitespace at the end of the manifest collapses to one newline.
    chunks = [f"phase: {phase}"]
    for name in STATE_NAMES:
        path = state / name
        if path.is_file():
            chunks.append("")
            chunks.append(f"== {name}")
            chunks.append(path.read_text(errors="replace"))
    return "\n".join(chunks).rstrip() + "\n"


def log_kept(path):
    # A name that begins with alert- comes from a later detection.
    if not path.is_file():
        return False
    if not allowed(path):
        return False
    if path.name.startswith("alert-"):
        return False
    return True


def add_logs(archive, logs):
    # Names follow sorted order.
    if logs is None or not logs.is_dir():
        return
    for path in sorted(logs.iterdir()):
        if log_kept(path):
            add_text(archive, f"logs/{path.name}", path.read_text(errors="replace"))


def add_excludes(archive):
    # An empty item is skipped. A directory is left aside.
    raw = os.environ.get("WATCHDOG_EXCLUDES") or ""
    for chunk in raw.split(":"):
        if not chunk:
            continue
        exclude = Path(chunk)
        if not exclude.is_file():
            continue
        if not allowed(exclude):
            continue
        add_text(
            archive,
            f"exclude/{exclude.name}",
            exclude.read_text(errors="replace"),
        )


def tail_text(path):
    # Only the last 400 lines of a host log are kept.
    lines = path.read_text(errors="replace").splitlines()
    return "\n".join(lines[-TAIL_LINES:]) + "\n"


def add_host_logs(archive):
    for label, candidate in HOST_LOGS:
        if not candidate.is_file():
            continue
        add_text(archive, label, tail_text(candidate))


def build_pack(phase, state_dir, log_dir, dest):
    state = Path(state_dir)
    logs = Path(log_dir) if log_dir else None
    target = Path(dest)
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        add_text(archive, "manifest.txt", manifest_text(phase, state))
        add_logs(archive, logs)
        add_excludes(archive)
        add_host_logs(archive)


phase, state_dir, log_dir, dest = sys.argv[1:5]
build_pack(phase, state_dir, log_dir, dest)
