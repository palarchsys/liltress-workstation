#!/usr/bin/env python3
# =============================================================================
# File       : python/check-yaml.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import sys
try:
    import yaml
except ImportError:
    yaml = None

def load(path):
    text = open(path, encoding="utf-8").read()
    if yaml is not None:
        yaml.safe_load(text)
        return
    if "\t" in text:
        raise SystemExit(f"tab in {path}")
    if ":" not in text:
        raise SystemExit(f"no yaml keys in {path}")

for p in sys.argv[1:]:
    load(p)
