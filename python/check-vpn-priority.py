#!/usr/bin/env python3
# =============================================================================
# File       : python/check-vpn-priority.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import re
import sys
from pathlib import Path

conf = Path(sys.argv[1]).read_text(encoding="utf-8")
egress = Path(sys.argv[2]).read_text(encoding="utf-8")
lib = Path(sys.argv[3]).read_text(encoding="utf-8")
found = re.search(r"^VPN_FW_PRIORITY=(-?\d+)\s*$", conf, re.M)
if not found or found.group(1) != "-150":
    sys.exit("priorité absente")
if not re.search(r"priority 0", egress):
    sys.exit("priorité egress absente")
if "-150" not in lib:
    sys.exit("priorité absente du script")
if int(found.group(1)) >= 0:
    sys.exit("priorité non négative")
