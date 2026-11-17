#!/usr/bin/env python3
# =============================================================================
# File       : python/check-yaml.py
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Exit when a file is not readable as YAML.
# Note       : Without PyYAML, a tab or a file with no key is refused.
# -----------------------------------------------------------------------------


import sys

try:
    import yaml
except ImportError:
    yaml = None


def load_yaml(path):
    text = open(path, encoding="utf-8").read()
    if yaml is not None:
        yaml.safe_load(text)
        return
    if "\t" in text:
        raise SystemExit(f"tab in {path}")
    if ":" not in text:
        raise SystemExit(f"no yaml keys in {path}")


for path in sys.argv[1:]:
    load_yaml(path)
