#!/usr/bin/env python3
# =============================================================================
# File       : python/route-pick.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import os
import sys
from pathlib import Path

root = Path(os.environ["ROUTE_ROOT"])
yaml_path = root / "agents" / "routing.yaml"

def parse(text):
    routes = []
    current = None
    bucket = None
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        if line.startswith("  - id:"):
            current = {"id": line.split(":", 1)[1].strip(), "match": [], "read": []}
            routes.append(current)
            bucket = None
            continue
        if current is None:
            continue
        stripped = line.strip()
        if stripped in ("match:", "read:"):
            bucket = stripped[:-1]
            continue
        if stripped.startswith("- ") and bucket:
            current[bucket].append(stripped[2:].strip().strip('"'))
    return routes

routes = parse(yaml_path.read_text(encoding="utf-8"))
if not routes:
    print("routing.yaml : aucune route", file=sys.stderr)
    sys.exit(1)

args = sys.argv[1:]
if not args or args[0] in ("-h", "--help"):
    print("Usage: bash agents/route.sh \"<mots>\"")
    print("       bash agents/route.sh --check")
    sys.exit(0 if not args else 0)

if args[0] == "--check":
    missing = 0
    for route in routes:
        if not route["read"]:
            print(f"FAIL {route['id']} sans fichier")
            missing += 1
            continue
        for rel in route["read"]:
            path = root / rel
            if path.is_file():
                print(f"OK   {route['id']}  {rel}")
            else:
                print(f"FAIL {route['id']}  absent : {rel}")
                missing += 1
    sys.exit(1 if missing else 0)

query = " ".join(args).casefold()
scored = []
for route in routes:
    score = 0
    for needle in route["match"]:
        n = needle.casefold()
        if n and n in query:
            score += 2 if " " in n else 1
    if score:
        scored.append((score, route))
scored.sort(key=lambda item: (-item[0], item[1]["id"]))
if not scored:
    print("Aucune route. Lire AGENTS.md seulement.")
    sys.exit(0)
chosen = []
seen = set()
for _score, route in scored:
    for rel in route["read"]:
        if rel in seen:
            continue
        seen.add(rel)
        chosen.append(rel)
        if len(chosen) == 2:
            break
    if len(chosen) == 2:
        break
for rel in chosen:
    print(rel)
