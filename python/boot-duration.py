#!/usr/bin/env python3
# =============================================================================
# File       : python/boot-duration.py
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Convert one systemd time span into whole milliseconds.
# Note       : The word infinity and any other unit count as zero.
# -----------------------------------------------------------------------------


import sys


def milliseconds_of(span):
    # systemd writes ms, us, or s. Anything else is not a duration.
    text = span.strip()
    if text.endswith("ms"):
        return int(round(float(text[:-2])))
    if text.endswith("us"):
        return int(round(float(text[:-2]) / 1000.0))
    if text.endswith("s") and text != "infinity":
        return int(round(float(text[:-1]) * 1000.0))
    return 0


print(milliseconds_of(sys.argv[1]))
