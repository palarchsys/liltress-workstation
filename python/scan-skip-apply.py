#!/usr/bin/env python3
# =============================================================================
# File       : python/scan-skip-apply.py
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Replace the workstation scan-skip block in one ClamAV configuration.
# Note       : An empty path is ignored. A repeated path stays once, in first-seen order.
# -----------------------------------------------------------------------------


import re
import sys
from pathlib import Path

BEGIN = "# BEGIN Liltress Workstation scan-skip"
END = "# END Liltress Workstation scan-skip"
OLD_BEGIN = "# BEGIN High-Fortress User scan-skip"
OLD_END = "# END High-Fortress User scan-skip"


def unique_paths(fixed, extras):
    seen = []
    for path in list(fixed) + list(extras):
        if path and path not in seen:
            seen.append(path)
    return seen


def trim_blank(lines):
    while lines and lines[-1] == "":
        lines.pop()
    return lines


def drop_old(text):
    # The previous block and a loose OnAccessExcludePath line are removed.
    out = []
    skipping = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped in (BEGIN, OLD_BEGIN):
            skipping = True
            continue
        if skipping:
            if stripped in (END, OLD_END):
                skipping = False
            continue
        if line.startswith("OnAccessExcludePath "):
            continue
        out.append(line)
    return trim_blank(out)


def skip_block(paths):
    block = [BEGIN]
    for path in paths:
        block.append("OnAccessExcludePath ^" + re.escape(path) + "$")
    block.append(END)
    return block


def apply_scan_skip():
    conf = Path(sys.argv[1])
    dest = Path(sys.argv[2])
    count = int(sys.argv[3])
    fixed = sys.argv[4 : 4 + count]
    extras = sys.argv[4 + count :]
    text = conf.read_text(errors="replace")
    out = drop_old(text)
    out.append("")
    out.extend(skip_block(unique_paths(fixed, extras)))
    new = "\n".join(out) + "\n"
    old = text if text.endswith("\n") else text + "\n"
    dest.write_text(new)
    print("changed" if new != old else "same")


if __name__ == "__main__":
    apply_scan_skip()
