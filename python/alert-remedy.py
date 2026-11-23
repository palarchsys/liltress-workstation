#!/usr/bin/env python3
# =============================================================================
# File       : python/alert-remedy.py
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Print the repair actions stored on one watchdog case.
# Note       : A case missing from the catalog prints nothing and exits 0.
# -----------------------------------------------------------------------------


import json
import sys


def actions_of(catalog, tool, class_id, branch):
    # The first matching case wins. A later case with the same id is ignored.
    with open(catalog, encoding="utf-8") as handle:
        data = json.load(handle)
    for dog in data.get("watchdogs", []):
        if dog.get("name") != tool:
            continue
        for case in dog.get("cases", []):
            if case.get("id") != class_id:
                continue
            return case.get(branch, [])
    return []


if __name__ == "__main__":
    for action in actions_of(*sys.argv[1:]):
        print(action)
