#!/usr/bin/env python3
# =============================================================================
# File       : python/route-pick.py
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Pick at most two agent files that answer one query.
# -----------------------------------------------------------------------------


import os
import sys
from pathlib import Path


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


def emit_usage():
    print('Usage: bash agents/route.sh "<mots>"')
    print("       bash agents/route.sh --check")


def check_file(route, rel, root):
    path = root / rel
    if path.is_file():
        print(f"OK   {route['id']}  {rel}")
        return 0
    print(f"FAIL {route['id']}  absent : {rel}")
    return 1


def check_route(route, root):
    if not route["read"]:
        print(f"FAIL {route['id']} sans fichier")
        return 1
    missing = 0
    for rel in route["read"]:
        missing += check_file(route, rel, root)
    return missing


def check_routes(routes, root):
    missing = 0
    for route in routes:
        missing += check_route(route, root)
    return missing


def score_route(route, query):
    score = 0
    for needle in route["match"]:
        folded = needle.casefold()
        if folded and folded in query:
            score += 2 if " " in folded else 1
    return score


def score_routes(routes, query):
    scored = []
    for route in routes:
        score = score_route(route, query)
        if score:
            scored.append((score, route))
    scored.sort(key=lambda item: (-item[0], item[1]["id"]))
    return scored


def choose_paths(scored):
    chosen = []
    seen = set()
    for _score, route in scored:
        for rel in route["read"]:
            if rel in seen:
                continue
            seen.add(rel)
            chosen.append(rel)
            if len(chosen) == 2:
                return chosen
    return chosen


def show_routes(routes, args, root):
    if not args or args[0] in ("-h", "--help"):
        emit_usage()
        sys.exit(0)
    if args[0] == "--check":
        sys.exit(1 if check_routes(routes, root) else 0)
    query = " ".join(args).casefold()
    scored = score_routes(routes, query)
    if not scored:
        print("Aucune route. Lire AGENTS.md seulement.")
        sys.exit(0)
    for rel in choose_paths(scored):
        print(rel)


def run_route_pick():
    root = Path(os.environ["ROUTE_ROOT"])
    routes = parse((root / "agents" / "routing.yaml").read_text(encoding="utf-8"))
    if not routes:
        print("routing.yaml : aucune route", file=sys.stderr)
        sys.exit(1)
    show_routes(routes, sys.argv[1:], root)


run_route_pick()
