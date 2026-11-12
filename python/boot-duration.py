#!/usr/bin/env python3
# =============================================================================
# File       : python/boot-duration.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import sys
s = sys.argv[1].strip()
if s.endswith("ms"):
    print(int(round(float(s[:-2]))))
elif s.endswith("us"):
    print(int(round(float(s[:-2]) / 1000.0)))
elif s.endswith("s") and s != "infinity":
    print(int(round(float(s[:-1]) * 1000.0)))
else:
    print(0)
