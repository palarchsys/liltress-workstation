#!/usr/bin/env python3
# =============================================================================
# File       : python/check-locale.py
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Check that locale catalogs share the same keys.
# -----------------------------------------------------------------------------


import re
import sys
from pathlib import Path

LANGS = ("en", "fr", "de", "es")
KEY_RE = re.compile(r"^\[([a-z][a-z0-9-]*(?:\.[a-z0-9-]+)+|LABEL_[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*)\]$")
HARD_RE = re.compile(r"^\[(hardening\.[a-z0-9.-]+)\]$")
VPN_RE = re.compile(r"^\[(vpn\.[a-z0-9-]+(?:\.[a-z0-9-]+)*)\]$")


def keys_of(root):
    found = {}
    base = Path(root)
    for lang in LANGS:
        bag = set()
        folder = base / lang
        if not folder.is_dir():
            return None
        for path in folder.glob("*.txt"):
            for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
                match = KEY_RE.match(line)
                if match:
                    bag.add(match.group(1))
        found[lang] = bag
    return found


def check_keys(root):
    found = keys_of(root)
    if found is None:
        sys.exit("missing language directory in " + root)
    base = found["en"]
    for lang, bag in found.items():
        if bag != base:
            missing = sorted(base - bag)[:8]
            extra = sorted(bag - base)[:8]
            sys.exit(root + " " + lang + " missing=" + str(missing) + " extra=" + str(extra))


def hardening_bag(root, lang):
    found = set()
    for path in (Path(root) / lang).glob("*.txt"):
        for line in path.read_text(encoding="utf-8").splitlines():
            match = HARD_RE.match(line)
            if match:
                found.add(match.group(1))
    return found


def check_hardening(root):
    base = hardening_bag(root, "en")
    if not base:
        sys.exit("vide")
    for lang in ("fr", "de", "es"):
        if hardening_bag(root, lang) != base:
            sys.exit(lang)


def vpn_bag(root, lang):
    found = set()
    folder = Path(root) / lang
    for path in folder.glob("*.txt"):
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            match = VPN_RE.match(line)
            if match and match.group(1).startswith("vpn."):
                found.add(match.group(1))
    return found


def check_vpn(root):
    base = vpn_bag(root, "en")
    if not base:
        sys.exit("aucune clé")
    for lang in LANGS:
        found = vpn_bag(root, lang)
        if found != base:
            sys.exit(f"{lang} missing={sorted(base - found)[:6]} extra={sorted(found - base)[:6]}")


def run_check_locale():
    mode = sys.argv[1]
    sys.argv = [sys.argv[0]] + sys.argv[2:]
    if mode == "keys":
        check_keys(sys.argv[1])
        return
    if mode == "hardening":
        check_hardening(sys.argv[1])
        return
    if mode == "vpn":
        check_vpn(sys.argv[1])
        return
    sys.exit("mode python refusé")


run_check_locale()
