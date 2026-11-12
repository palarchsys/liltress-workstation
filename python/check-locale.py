#!/usr/bin/env python3
# =============================================================================
# File       : python/check-locale.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import sys

mode = sys.argv[1]
sys.argv = [sys.argv[0]] + sys.argv[2:]

if mode == 'keys':
    import re
    import sys
    from pathlib import Path

    key_re = re.compile(r"^\[([a-z][a-z0-9-]*(?:\.[a-z0-9-]+)+|LABEL_[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*)\]$")

    def keys_of(root):
        found = {}
        base = Path(root)
        for lang in ("en", "fr", "de", "es"):
            bag = set()
            folder = base / lang
            if not folder.is_dir():
                return None
            for path in folder.glob("*.txt"):
                for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
                    match = key_re.match(line)
                    if match:
                        bag.add(match.group(1))
            found[lang] = bag
        return found

    def check(root):
        found = keys_of(root)
        if found is None:
            sys.exit("missing language directory in " + root)
        base = found["en"]
        for lang, bag in found.items():
            if bag != base:
                missing = sorted(base - bag)[:8]
                extra = sorted(bag - base)[:8]
                sys.exit(root + " " + lang + " missing=" + str(missing) + " extra=" + str(extra))

    check(sys.argv[1])
elif mode == 'hardening':
    import re, sys
    from pathlib import Path
    key_re = re.compile(r"^\[(hardening\.[a-z0-9.-]+)\]$")
    def bag(lang):
        found = set()
        for path in (Path(sys.argv[1]) / lang).glob("*.txt"):
            for line in path.read_text(encoding="utf-8").splitlines():
                match = key_re.match(line)
                if match:
                    found.add(match.group(1))
        return found
    base = bag("en")
    if not base:
        sys.exit("vide")
    for lang in ("fr", "de", "es"):
        if bag(lang) != base:
            sys.exit(lang)
elif mode == 'keys':
    import re
    import sys
    from pathlib import Path

    key_re = re.compile(r"^\[([a-z][a-z0-9-]*(?:\.[a-z0-9-]+)+|LABEL_[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*)\]$")

    def keys_of(root):
        found = {}
        base = Path(root)
        for lang in ("en", "fr", "de", "es"):
            bag = set()
            folder = base / lang
            if not folder.is_dir():
                return None
            for path in folder.glob("*.txt"):
                for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
                    match = key_re.match(line)
                    if match:
                        bag.add(match.group(1))
            found[lang] = bag
        return found

    def check(root):
        found = keys_of(root)
        if found is None:
            sys.exit("missing language directory in " + root)
        base = found["en"]
        for lang, bag in found.items():
            if bag != base:
                missing = sorted(base - bag)[:8]
                extra = sorted(bag - base)[:8]
                sys.exit(root + " " + lang + " missing=" + str(missing) + " extra=" + str(extra))

    check(sys.argv[1])
elif mode == 'vpn':
    import re
    import sys
    from pathlib import Path

    key_re = re.compile(r"^\[(vpn\.[a-z0-9-]+(?:\.[a-z0-9-]+)*)\]$")

    def bag(root, lang):
        found = set()
        folder = Path(root) / lang
        for path in folder.glob("*.txt"):
            for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
                match = key_re.match(line)
                if match and match.group(1).startswith("vpn."):
                    found.add(match.group(1))
        return found

    locale = Path(sys.argv[1])
    base = bag(locale, "en")
    if not base:
        sys.exit("aucune clé")
    for lang in ("en", "fr", "de", "es"):
        found = bag(locale, lang)
        if found != base:
            sys.exit(f"{lang} missing={sorted(base-found)[:6]} extra={sorted(found-base)[:6]}")
else:
    sys.exit('mode python refusé')
