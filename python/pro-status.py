#!/usr/bin/env python3
# =============================================================================
# File       : python/pro-status.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import json
import sys

data = json.load(sys.stdin)
wanted = ("esm-infra", "esm-apps", "livepatch")
for svc in data.get("services") or []:
    name = svc.get("name")
    if name not in wanted:
        continue
    detail = svc.get("status_details") or ""
    warning = svc.get("warning") or {}
    if isinstance(warning, dict) and warning.get("message"):
        detail = warning["message"]
    detail = detail.replace("\t", " ").replace("\n", " ")
    print("%s\t%s\t%s" % (name, svc.get("status") or "", detail))
