#!/usr/bin/env python3
# =============================================================================
# File       : python/test-summary.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import json, sys
out, p, f, w, s, profile, tsv = sys.argv[1:8]
items = []
with open(tsv, encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        status, ident, msg = line.split("\t", 2)
        items.append({"status": status, "id": ident, "message": msg})
payload = {
    "profile": profile,
    "pass": int(p),
    "fail": int(f),
    "warn": int(w),
    "skip": int(s),
    "ok": int(f) == 0,
    "results": items,
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
