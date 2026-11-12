#!/usr/bin/env python3
# =============================================================================
# File       : python/alert-remedy.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import json, sys
path, tool, class_id, branch = sys.argv[1:]
data = json.loads(open(path, encoding="utf-8").read())
for dog in data.get("watchdogs", []):
    if dog.get("name") != tool:
        continue
    for case in dog.get("cases", []):
        if case.get("id") != class_id:
            continue
        for action in case.get(branch, []):
            print(action)
        sys.exit(0)
sys.exit(0)
