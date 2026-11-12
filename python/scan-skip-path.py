#!/usr/bin/env python3
# =============================================================================
# File       : python/scan-skip-path.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import sys

mode = sys.argv[1]
sys.argv = [sys.argv[0]] + sys.argv[2:]

if mode == 'edit':
    import sys
    from pathlib import Path

    dest = Path(sys.argv[1])
    target = sys.argv[2]
    kept = []
    for raw in dest.read_text(errors="replace").splitlines():
        line = raw.strip()
        if line == target:
            continue
        kept.append(raw)
    text = "\n".join(kept)
    if text and not text.endswith("\n"):
        text += "\n"
    if not text.endswith("\n"):
        text += "\n"
    dest.write_text(text)
elif mode == 'norm':
    import os
    import sys
    raw = sys.argv[1].strip()
    if not raw.startswith("/"):
        sys.exit(1)
    print(os.path.normpath(raw))
else:
    sys.exit('mode python refusé')
