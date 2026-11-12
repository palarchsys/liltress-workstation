#!/usr/bin/env python3
# =============================================================================
# File       : python/debsums-reset.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import hashlib
import io
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

log_path = Path(sys.argv[1])
name_re = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.+-]*(?::[A-Za-z0-9]+)?$")
pkg_re = re.compile(
    r"\(from ([A-Za-z0-9][A-Za-z0-9.+-]*(?::[A-Za-z0-9]+)?) package\)\s*$"
)
path_re = re.compile(r"^debsums: changed file (.+?) \(from ")

def package_of(path):
    try:
        out = subprocess.check_output(
            ["dpkg", "-S", path], text=True, stderr=subprocess.DEVNULL
        )
    except (subprocess.CalledProcessError, OSError):
        return ""
    token = out.split(":", 1)[0].split(",")[0].strip()
    return token if name_re.match(token) else ""

packages = []
seen = set()
leftover = []
for raw in log_path.read_text(errors="replace").splitlines():
    line = raw.strip()
    if not line:
        continue
    named = pkg_re.search(line)
    if named and named.group(1) not in seen:
        seen.add(named.group(1))
        packages.append(named.group(1))
        continue
    found = path_re.match(line)
    path = found.group(1).strip() if found else (line if line.startswith("/") else "")
    pkg = package_of(path) if path else ""
    if pkg and pkg not in seen:
        seen.add(pkg)
        packages.append(pkg)
        continue
    if line not in leftover:
        leftover.append(line)

def run(cmd):
    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    env["NEEDRESTART_MODE"] = "l"
    env["APT_LISTCHANGES_FRONTEND"] = "none"
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)

cache_dir = None

def purge_cache():
    # Une différence ne repasse pas par le cache apt. Il est purgé avant le téléchargement.
    run(["apt-get", "clean"])
    for root in (Path("/var/cache/apt/archives"), Path("/var/cache/apt/archives/partial")):
        if not root.is_dir():
            continue
        try:
            entries = list(root.iterdir())
        except OSError:
            continue
        for path in entries:
            if path.is_file() and ".deb" in path.name:
                try:
                    path.unlink()
                except OSError:
                    pass

def private_cache():
    global cache_dir
    if cache_dir is None:
        cache_dir = Path(tempfile.mkdtemp(prefix="hf-apt-"))
        (cache_dir / "partial").mkdir()
    return cache_dir

def reinstall(pkg):
    archives = private_cache()
    return run([
        "apt-get", "-o", f"Dir::Cache::archives={archives}/",
        "install", "--reinstall", "-y", "--", pkg,
    ])

def fresh_debs(pkg):
    if cache_dir is None or not cache_dir.is_dir():
        return []
    prefix = pkg.split(":", 1)[0] + "_"
    found = []
    try:
        entries = list(cache_dir.iterdir())
    except OSError:
        return []
    for path in entries:
        if path.is_file() and path.suffix == ".deb" and path.name.startswith(prefix):
            found.append(path)
    return found

def sums_ok(check):
    return check.returncode == 0 and not check.stdout.strip()

def failing_paths(text):
    found = []
    pattern = re.compile(r"(?:changed|missing) file (\S+)")
    for raw in text.splitlines():
        line = raw.strip()
        named = pattern.search(line)
        if named:
            found.append(named.group(1))
        elif line.startswith("/"):
            found.append(line.split()[0])
    return found

def archive_member(deb, rel):
    proc = subprocess.run(
        ["dpkg-deb", "--fsys-tarfile", str(deb)],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if proc.returncode != 0:
        return None
    want = rel.lstrip("/")
    try:
        tf = tarfile.open(fileobj=io.BytesIO(proc.stdout), mode="r|*")
    except tarfile.TarError:
        return None
    while True:
        try:
            member = tf.next()
        except tarfile.TarError:
            return None
        if member is None:
            return None
        if member.name.lstrip("./") != want:
            continue
        if member.issym() or member.islnk():
            return ("link", member.linkname)
        if member.isfile():
            extracted = tf.extractfile(member)
            return ("file", extracted.read() if extracted else b"")
        return None

def disk_matches_archive(deb, path):
    member = archive_member(deb, path)
    disk = Path(path)
    if member is None:
        return not disk.exists()
    kind, payload = member
    if kind == "link":
        return disk.is_symlink() and os.readlink(disk) == payload
    if disk.is_symlink() or not disk.is_file():
        return False
    return hashlib.md5(disk.read_bytes()).hexdigest() == hashlib.md5(payload).hexdigest()

def archive_explains(pkg, text):
    try:
        paths = failing_paths(text)
        debs = fresh_debs(pkg)
        if not paths or not debs:
            return False
        deb = max(debs, key=lambda path: path.stat().st_mtime)
        return all(disk_matches_archive(deb, path) for path in paths)
    except OSError:
        return False

blocks = []
restored = []
failed = []
try:
    if packages:
        purge_cache()
    for pkg in packages:
        apt = reinstall(pkg)
        if apt.returncode != 0:
            failed.append(pkg)
            err = next((ln.strip() for ln in reversed(apt.stdout.splitlines()) if ln.strip()), "apt-get a échoué")
            blocks.extend([f"{pkg} : réinstallation échouée.", err, ""])
            continue
        check = run(["debsums", "-s", pkg])
        if sums_ok(check):
            restored.append(pkg)
            blocks.extend([f"{pkg} réinstallé.", "La somme correspond.", ""])
        elif archive_explains(pkg, check.stdout):
            continue
        else:
            failed.append(pkg)
            detail = [
                ln.strip()
                for ln in check.stdout.splitlines()
                if ln.strip() and (" file " in ln or ln.strip().startswith("/"))
            ]
            blocks.extend([f"{pkg} réinstallé.", "La somme reste différente.", *detail, ""])
    for line in leftover:
        failed.append(line)
        blocks.extend([line, ""])

    report = "\n".join(blocks).rstrip()
    log_path.write_text((report + "\n") if report else "")
    if restored and not failed:
        if len(restored) == 1:
            sys.stdout.write(f"debsums : {restored[0]} réinstallé, somme rétablie")
        else:
            sys.stdout.write(f"debsums : {len(restored)} paquets réinstallés, sommes rétablies")
    elif restored or failed:
        sys.stdout.write("debsums : correction incomplète")
finally:
    if cache_dir is not None:
        shutil.rmtree(cache_dir, ignore_errors=True)
