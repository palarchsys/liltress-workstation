#!/usr/bin/env python3
# =============================================================================
# File       : python/install-render.py
# Updated at : 2026-11-17
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Render one product installer from the shared template.
# -----------------------------------------------------------------------------


import pathlib
import sys

REPOS = {
    "workstation": "liltress-workstation",
    "server": "liltress-server",
}
REPO_TOKEN = "__HF_TEMPLATE_REPO__"
MARKERS = (
    "# TEMPLATE_WORKSTATION_SAVE_BEGIN",
    "# TEMPLATE_WORKSTATION_SAVE_END",
    "# TEMPLATE_WORKSTATION_RESTORE_BEGIN",
    "# TEMPLATE_WORKSTATION_RESTORE_END",
)
PAIRS = {
    MARKERS[0]: MARKERS[1],
    MARKERS[2]: MARKERS[3],
}


def read_template(path):
    raw = pathlib.Path(path).read_text(encoding="utf-8").splitlines(keepends=True)
    start = None
    end = None
    for cursor, line in enumerate(raw):
        if line.startswith("cat <<'END_TEMPLATE'") or line.startswith("cat << 'END_TEMPLATE'"):
            start = cursor + 1
        elif start is not None and line.rstrip("\n") == "END_TEMPLATE":
            end = cursor
            break
    if start is None or end is None:
        print("modèle illisible", file=sys.stderr)
        sys.exit(1)
    return "".join(raw[start:end])


def replace_repo(text, product):
    if text.count(REPO_TOKEN) < 1:
        print("jeton de dépôt absent", file=sys.stderr)
        sys.exit(1)
    return text.replace(REPO_TOKEN, REPOS[product])


def open_marker(token_line, product, seen):
    seen.add(token_line)
    if product == "server":
        return PAIRS[token_line], False
    return None, False


def close_marker(token_line, waiting, seen):
    if token_line == waiting:
        seen.add(token_line)
        return None, False
    return waiting, False


def marker_action(line, product, waiting, seen):
    token_line = line.strip()
    if waiting is None and token_line in PAIRS:
        return open_marker(token_line, product, seen)
    if waiting is not None:
        return close_marker(token_line, waiting, seen)
    if product == "workstation" and token_line in PAIRS.values():
        seen.add(token_line)
        return None, False
    return waiting, True


def strip_markers(text, product):
    if not any(marker in text for marker in MARKERS):
        return text
    out = []
    waiting = None
    seen = set()
    for line in text.splitlines(keepends=True):
        waiting, keep = marker_action(line, product, waiting, seen)
        if keep:
            out.append(line)
    if waiting is not None or seen != set(MARKERS):
        print("marqueurs du poste incomplets", file=sys.stderr)
        sys.exit(1)
    return "".join(out)


def refuse_leftover(text, product):
    if "TEMPLATE" in text or REPO_TOKEN in text:
        print("jeton encore présent", file=sys.stderr)
        sys.exit(1)
    if product in REPOS and "scan-skip.paths" not in text:
        print("liste scan-skip absente", file=sys.stderr)
        sys.exit(1)


def write_dest(text, dest):
    if not text.endswith("\n"):
        text += "\n"
    data = text.encode("utf-8")
    if dest == "-":
        sys.stdout.buffer.write(data)
        return
    pathlib.Path(dest).write_bytes(data)


def render_product():
    template_path, product, dest = sys.argv[1:]
    if product not in REPOS:
        print(f"produit refusé : {product}", file=sys.stderr)
        sys.exit(1)
    text = replace_repo(read_template(template_path), product)
    text = strip_markers(text, product)
    refuse_leftover(text, product)
    write_dest(text, dest)


render_product()
