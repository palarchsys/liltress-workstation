#!/usr/bin/env bash
# =============================================================================
# File       : core/watchdog/pack.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

# -----------------------------------------------------------------------------
# Purpose    : Write the zip a real watchdog detection attaches to the mail.
# Note       : The archive keeps only the logs of this pass. Later passes stay out.
# -----------------------------------------------------------------------------

write_watchdog_pack() {
    local phase="$1"
    local state_dir="$2"
    local log_dir="$3"
    local base stamp dest excludes
    base="$(get_product_base)"
    stamp="$(date '+%Y%m%d-%H%M%S')"
    mkdir -p -- "${base}/log"
    dest="${base}/log/alert-${phase}-${stamp}.zip"
    excludes="$(read_watchdog_exclude | awk 'NR > 1 { printf ":" } { printf "%s", $0 }')"
    WATCHDOG_EXCLUDES="${excludes}" \
    python3 - "${phase}" "${state_dir}" "${log_dir}" "${dest}" << 'PY'
import os
import zipfile
from pathlib import Path

phase, state_dir, log_dir, dest = sys_parts = __import__("sys").argv[1:5]
state = Path(state_dir)
logs = Path(log_dir) if log_dir else None
target = Path(dest)
secret_names = {"secrets.conf", "id_ed25519", "id_ed25519.pub"}


def redact(text):
    import re
    text = re.sub(
        r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----",
        "[private key redacted]",
        text,
        flags=re.S,
    )
    text = re.sub(
        r"(?i)\b(password|passwd|token|secret|api[_-]?key|authorization|bearer)\b(\s*[:=]\s*)\S+",
        lambda match: match.group(1) + match.group(2) + "[redacted]",
        text,
    )
    return text


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
PY
    chmod 600 "${dest}" 2>/dev/null || true
    printf '%s\n' "${dest}"
}
