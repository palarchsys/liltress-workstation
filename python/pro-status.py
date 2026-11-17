#!/usr/bin/env python3
# =============================================================================
# File       : python/pro-status.py
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Print the Ubuntu Pro services the verify report keeps.
# -----------------------------------------------------------------------------


import json
import sys

WANTED = ("esm-infra", "esm-apps", "livepatch")


def detail_of(service):
    # The warning is the sentence an operator can act on. The raw detail is the fallback.
    detail = service.get("status_details") or ""
    warning = service.get("warning") or {}
    if isinstance(warning, dict) and warning.get("message"):
        detail = warning["message"]
    return detail.replace("\t", " ").replace("\n", " ")


def rows_of(payload):
    rows = []
    for service in payload.get("services") or []:
        name = service.get("name")
        if name not in WANTED:
            continue
        status = service.get("status") or ""
        rows.append("%s\t%s\t%s" % (name, status, detail_of(service)))
    return rows


for row in rows_of(json.load(sys.stdin)):
    print(row)
