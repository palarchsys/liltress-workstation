#!/usr/bin/env python3
# =============================================================================
# File       : python/response-render.py
# Updated at : 2026-11-26
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Render one readable service file for each installation.
# Note       : The model is census/response/service.md.
# -----------------------------------------------------------------------------


import csv
import re
import sys
from pathlib import Path

FIELDS = ("product", "slug", "service", "rhythm", "silence", "detection", "automatic", "mail", "zones")
MARKS = ("service", "rhythm", "silence", "detection", "automatic", "mail", "zones")
ZONE_SLUGS = ("aide", "clamav-walk", "clamav-access", "fingerprint", "auditd")
ZONE_LABELS = ("AIDE", "Parcours", "Accès", "Empreinte", "Audit")
FRESH = (
    "/bin",
    "/boot",
    "/dev",
    "/etc",
    "/home",
    "/home/<compte>",
    "/lib",
    "/lib64",
    "/media",
    "/mnt",
    "/opt",
    "/proc",
    "/root",
    "/run",
    "/sbin",
    "/srv",
    "/sys",
    "/tmp",
    "/usr",
    "/usr/bin",
    "/usr/sbin",
    "/usr/lib",
    "/usr/lib64",
    "/usr/local",
    "/var",
    "/var/cache",
    "/var/log",
    "/var/tmp",
    "/var/www",
)
SLUG = re.compile(r"^[a-z][a-z0-9-]*$")


def fail(message):
    sys.stderr.write(message + "\n")
    raise SystemExit(1)


def read_rows(path):
    with path.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        fail("empty " + str(path))
    missing = [name for name in FIELDS if name not in rows[0]]
    if missing:
        fail("columns " + " ".join(missing))
    return rows


def fill_service(template, row):
    text = template
    for mark in MARKS:
        text = text.replace("{{" + mark + "}}", row[mark].strip())
    if "{{" in text:
        fail("placeholder " + row["slug"])
    if not text.endswith("\n"):
        text += "\n"
    return text


def products_of(product):
    if product == "both":
        return ("workstation", "server")
    if product in ("workstation", "server"):
        return (product,)
    fail("product " + product)


def collect_documents(template, rows):
    documents = {}
    for row in rows:
        slug = row["slug"].strip()
        if SLUG.fullmatch(slug) is None:
            fail("slug " + slug)
        body = fill_service(template, row)
        for product in products_of(row["product"].strip()):
            rel = f"census/response/{product}/{slug}.md"
            if rel in documents:
                fail("duplicate " + rel)
            documents[rel] = body
    return documents


def extra_files(root, documents):
    found = []
    for product in ("workstation", "server"):
        folder = root / "census" / "response" / product
        if not folder.is_dir():
            continue
        for path in sorted(folder.glob("*.md")):
            rel = path.relative_to(root).as_posix()
            if rel not in documents:
                found.append(rel)
    return found


def report_stale(root, documents):
    stale = list(extra_files(root, documents))
    for rel, text in documents.items():
        path = root / rel
        current = path.read_text(encoding="utf-8") if path.is_file() else None
        if current != text:
            stale.append(rel)
    if stale:
        fail("stale " + " ".join(stale))


def emit_documents(root, documents):
    for rel in extra_files(root, documents):
        (root / rel).unlink()
    for rel, text in documents.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")


def zone_paths(text):
    found = []
    for line in text.splitlines():
        line = line.strip().rstrip("/")
        if line.startswith("/"):
            found.append(line)
    return found


def cover_path(path, zones):
    if path == "/":
        return "partie" if zones else "non"
    if any(path == zone or path.startswith(zone + "/") for zone in zones):
        return "oui"
    if any(zone.startswith(path + "/") for zone in zones):
        return "partie"
    return "non"


def tree_nodes(paths):
    found = {"/"}
    for path in list(paths) + list(FRESH):
        current = path
        while current not in ("", "/"):
            found.add(current)
            current = current.rsplit("/", 1)[0]
    return sorted(found, key=lambda item: [piece for piece in item.split("/")])


def render_tree(product, zones):
    title = "poste" if product == "workstation" else "serveur"
    lines = [
        f"# Arborescence — {title}",
        "",
        "Installation fraîche. Les fichiers d'exclusion ne retirent aucun chemin.",
        "",
        "oui : le chemin est dans la zone. partie : seule une partie l'est. non : dehors.",
        "",
        "| Chemin | " + " | ".join(ZONE_LABELS) + " |",
        "|---| " + " | ".join("---" for _ in ZONE_LABELS) + " |",
    ]
    nodes = tree_nodes([path for slug in ZONE_SLUGS for path in zones.get(slug, [])])
    for path in nodes:
        marks = [cover_path(path, zones.get(slug, [])) for slug in ZONE_SLUGS]
        depth = 0 if path == "/" else path.count("/")
        label = "/" if path == "/" else ("  " * (depth - 1)) + path.rsplit("/", 1)[-1]
        lines.append("| " + label + " | " + " | ".join(marks) + " |")
    lines.append("")
    return "\n".join(lines)


def trees_of(rows):
    by_product = {"workstation": {}, "server": {}}
    documents = {}
    for row in rows:
        if row["slug"] not in ZONE_SLUGS:
            continue
        paths = zone_paths(row["zones"])
        for product in products_of(row["product"].strip()):
            by_product[product][row["slug"]] = paths
    for product, zones in by_product.items():
        documents[f"census/response/{product}/tree.md"] = render_tree(product, zones)
    return documents


def run_response_render():
    root = Path(sys.argv[1])
    mode = sys.argv[2]
    base = root / "census" / "response"
    template = (base / "service.md").read_text(encoding="utf-8")
    rows = read_rows(base / "services.csv")
    documents = collect_documents(template, rows)
    documents.update(trees_of(rows))
    if mode == "check":
        report_stale(root, documents)
        return
    if mode != "write":
        fail("mode")
    emit_documents(root, documents)


if __name__ == "__main__":
    run_response_render()
