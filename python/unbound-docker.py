#!/usr/bin/env python3
# =============================================================================
# File       : python/unbound-docker.py
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Point a Docker daemon at the Unbound address of its network.
# Note       : A daemon that already uses 127.0.0.1 is left unchanged.
# -----------------------------------------------------------------------------


import json
import sys


def gateway_of(cidr):
    # Unbound listens on the .1 address of the Docker network.
    base = cidr.split("/")[0]
    return ".".join(base.split(".")[:3] + ["1"])


def write_dns(path, cidr):
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    current = data.get("dns") or []
    if current == ["127.0.0.1"]:
        raise SystemExit("refused")
    data["dns"] = [gateway_of(cidr)]
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")


if __name__ == "__main__":
    write_dns(sys.argv[1], sys.argv[2])
