#!/usr/bin/env python3
# =============================================================================
# File       : python/unbound-docker.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import json, sys
path, cidr = sys.argv[1], sys.argv[2]
base = cidr.split("/")[0]
gate = ".".join(base.split(".")[:3] + ["1"])
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
current = data.get("dns") or []
if current == ["127.0.0.1"]:
    raise SystemExit("refused")
data["dns"] = [gate]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
