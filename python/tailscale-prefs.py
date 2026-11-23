#!/usr/bin/env python3
# =============================================================================
# File       : python/tailscale-prefs.py
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Exit 0 when Tailscale is up as an SSH transport only.
# -----------------------------------------------------------------------------


import json
import subprocess
import sys


def prefs_ok(prefs):
    routes = prefs.get("AdvertiseRoutes") or []
    mode = prefs.get("NetfilterMode")
    if prefs.get("RunSSH"):
        return False
    if prefs.get("ExitNodeID") or prefs.get("ExitNodeIP"):
        return False
    if routes:
        return False
    if prefs.get("CorpDNS") or prefs.get("RouteAll"):
        return False
    if mode not in (0, "off", "Off"):
        return False
    return bool(prefs.get("WantRunning"))


def run_tailscale_prefs():
    try:
        raw = subprocess.check_output(["tailscale", "debug", "prefs"], text=True)
        prefs = json.loads(raw)
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):  # fmt: skip
        return 1
    return 0 if prefs_ok(prefs) else 1


sys.exit(run_tailscale_prefs())
