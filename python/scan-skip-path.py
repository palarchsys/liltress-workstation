#!/usr/bin/env python3
# =============================================================================
# File       : python/scan-skip-path.py
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Normalize one absolute skip path, or drop one path from the skip file.
# Note       : The skip file always ends with a newline.
# -----------------------------------------------------------------------------


import os
import sys
from pathlib import Path


def drop_path(dest, target):
    kept = []
    for raw in dest.read_text(errors="replace").splitlines():
        if raw.strip() == target:
            continue
        kept.append(raw)
    text = "\n".join(kept)
    # An empty file still ends with a newline, so the next append stays on its own line.
    if not text.endswith("\n"):
        text += "\n"
    dest.write_text(text)


def normal_path(raw):
    # A relative path would point somewhere else after cron changes directory.
    text = raw.strip()
    if not text.startswith("/"):
        sys.exit(1)
    print(os.path.normpath(text))


if __name__ == "__main__":
    mode = sys.argv[1]
    argument = sys.argv[2:]
    if mode == "edit":
        drop_path(Path(argument[0]), argument[1])
    elif mode == "norm":
        normal_path(argument[0])
    else:
        sys.exit("mode python refusé")
