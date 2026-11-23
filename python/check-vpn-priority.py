#!/usr/bin/env python3
# =============================================================================
# File       : python/check-vpn-priority.py
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Exit when the VPN firewall priority is not below the egress rules.
# -----------------------------------------------------------------------------


import re
import sys
from pathlib import Path

# The tunnel is evaluated before egress, so its mark stays negative.
EXPECTED = "-150"


def require_priority(conf_text, egress_text, lib_text):
    found = re.search(r"^VPN_FW_PRIORITY=(-?\d+)\s*$", conf_text, re.M)
    if not found or found.group(1) != EXPECTED:
        sys.exit("priorité absente")
    if not re.search(r"priority 0", egress_text):
        sys.exit("priorité egress absente")
    if EXPECTED not in lib_text:
        sys.exit("priorité absente du script")


if __name__ == "__main__":
    require_priority(
        Path(sys.argv[1]).read_text(encoding="utf-8"),
        Path(sys.argv[2]).read_text(encoding="utf-8"),
        Path(sys.argv[3]).read_text(encoding="utf-8"),
    )
