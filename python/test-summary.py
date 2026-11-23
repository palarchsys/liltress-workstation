#!/usr/bin/env python3
# =============================================================================
# File       : python/test-summary.py
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Write the bench totals and result rows as one JSON file.
# -----------------------------------------------------------------------------


import json
import sys


def rows_of(tsv_path):
    # A blank line is a gap in the journal, not a result.
    items = []
    with open(tsv_path, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line:
                continue
            status, ident, message = line.split("\t", 2)
            items.append({"status": status, "id": ident, "message": message})
    return items


def write_summary(out_path, passed, failed, warned, skipped, profile, tsv_path):
    payload = {
        "profile": profile,
        "pass": int(passed),
        "fail": int(failed),
        "warn": int(warned),
        "skip": int(skipped),
        "ok": int(failed) == 0,
        "results": rows_of(tsv_path),
    }
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


if __name__ == "__main__":
    write_summary(*sys.argv[1:8])
