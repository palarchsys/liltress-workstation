#!/usr/bin/env python3
# =============================================================================
# File       : python/debsums-reset.py
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Reinstall packages cited by one debsums log and record what is still different.
# Note       : The apt cache is cleared before that reinstall.
# -----------------------------------------------------------------------------


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


NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.+-]*(?::[A-Za-z0-9]+)?$")
PKG_RE = re.compile(r"\(from ([A-Za-z0-9][A-Za-z0-9.+-]*(?::[A-Za-z0-9]+)?) package\)\s*$")
PATH_RE = re.compile(r"^debsums: changed file (.+?) \(from ")
FAIL_RE = re.compile(r"(?:changed|missing) file (\S+)")
ARCHIVE_ROOT = Path("/var/cache/apt/archives")

cache_dir = None


def run_command(cmd):
    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    env["NEEDRESTART_MODE"] = "l"
    env["APT_LISTCHANGES_FRONTEND"] = "none"
    return subprocess.run(
        cmd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=env,
    )


def package_of(path):
    # Package lookup keeps the caller environment. Apt commands replace three variables.
    try:
        out = subprocess.check_output(
            ["dpkg", "-S", path],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, OSError):  # fmt: skip
        return ""
    token = out.split(":", 1)[0].split(",")[0].strip()
    if NAME_RE.match(token):
        return token
    return ""


def remember(pkg, packages, seen):
    if not pkg or pkg in seen:
        return False
    seen.add(pkg)
    packages.append(pkg)
    return True


def line_path(line):
    found = PATH_RE.match(line)
    if found:
        return found.group(1).strip()
    if line.startswith("/"):
        return line
    return ""


def take_named(line, packages, seen):
    named = PKG_RE.search(line)
    if not named:
        return False
    return remember(named.group(1), packages, seen)


def take_path(line, packages, seen):
    path = line_path(line)
    if not path:
        return False
    return remember(package_of(path), packages, seen)


def collect_lines(text):
    # A package name already stored does not stop the path lookup.
    packages = []
    seen = set()
    leftover = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if take_named(line, packages, seen):
            continue
        if take_path(line, packages, seen):
            continue
        if line not in leftover:
            leftover.append(line)
    return packages, leftover


def unlink_debs(root):
    if not root.is_dir():
        return
    try:
        entries = list(root.iterdir())
    except OSError:
        return
    for path in entries:
        if path.is_file() and ".deb" in path.name:
            try:
                path.unlink()
            except OSError:
                pass


def purge_cache():
    # A changed file must not reuse the apt cache. The cache is cleared before the download.
    run_command(["apt-get", "clean"])
    unlink_debs(ARCHIVE_ROOT)
    unlink_debs(ARCHIVE_ROOT / "partial")


def private_cache():
    global cache_dir
    if cache_dir is None:
        cache_dir = Path(tempfile.mkdtemp(prefix="hf-apt-"))
        (cache_dir / "partial").mkdir()
    return cache_dir


def remove_cache():
    if cache_dir is not None:
        shutil.rmtree(cache_dir, ignore_errors=True)


def reinstall(pkg):
    archives = private_cache()
    # The bench searches this command as one unbroken list.
    # fmt: off
    return run_command([
        "apt-get", "-o", f"Dir::Cache::archives={archives}/",
        "install", "--reinstall", "-y", "--", pkg,
    ])
    # fmt: on


def fresh_debs(pkg):
    # The name must end in .deb. Text before a colon is the file prefix.
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
    for raw in text.splitlines():
        line = raw.strip()
        named = FAIL_RE.search(line)
        if named:
            found.append(named.group(1))
        elif line.startswith("/"):
            found.append(line.split()[0])
    return found


def open_archive(deb):
    proc = subprocess.run(
        ["dpkg-deb", "--fsys-tarfile", str(deb)],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if proc.returncode != 0:
        return None
    try:
        return tarfile.open(fileobj=io.BytesIO(proc.stdout), mode="r|*")
    except tarfile.TarError:
        return None


def next_member(archive):
    try:
        return archive.next()
    except tarfile.TarError:
        return None


def payload_of(member, archive):
    if member.issym() or member.islnk():
        return ("link", member.linkname)
    if member.isfile():
        extracted = archive.extractfile(member)
        if extracted:
            return ("file", extracted.read())
        return ("file", b"")
    return None


def member_payload(archive, rel):
    # Leading dots and slashes on the member name are ignored.
    want = rel.lstrip("/")
    while True:
        member = next_member(archive)
        if member is None:
            return None
        if member.name.lstrip("./") != want:
            continue
        return payload_of(member, archive)


def archive_member(deb, rel):
    archive = open_archive(deb)
    if archive is None:
        return None
    return member_payload(archive, rel)


def disk_matches_archive(deb, path):
    # No archive member is fine when that path is already absent.
    member = archive_member(deb, path)
    disk = Path(path)
    if member is None:
        return not disk.exists()
    kind, payload = member
    if kind == "link":
        return disk.is_symlink() and os.readlink(disk) == payload
    if disk.is_symlink() or not disk.is_file():
        return False
    disk_sum = hashlib.md5(disk.read_bytes()).hexdigest()
    payload_sum = hashlib.md5(payload).hexdigest()
    return disk_sum == payload_sum


def members_match(pkg, text):
    paths = failing_paths(text)
    debs = fresh_debs(pkg)
    if not paths or not debs:
        return False
    newest = max(debs, key=lambda path: path.stat().st_mtime)
    for path in paths:
        if not disk_matches_archive(newest, path):
            return False
    return True


def archive_explains(pkg, text):
    try:
        return members_match(pkg, text)
    except OSError:
        return False


def last_useful_line(text):
    for line in reversed(text.splitlines()):
        stripped = line.strip()
        if stripped:
            return stripped
    return "apt-get a échoué"


def difference_lines(text):
    found = []
    for raw in text.splitlines():
        line = raw.strip()
        if line and (" file " in line or line.startswith("/")):
            found.append(line)
    return found


def note_failure(pkg, text, failed, blocks):
    failed.append(pkg)
    detail = difference_lines(text)
    blocks.extend([f"{pkg} réinstallé.", "La somme reste différente.", *detail, ""])


def take_package(pkg, restored, failed, blocks):
    apt = reinstall(pkg)
    if apt.returncode != 0:
        failed.append(pkg)
        err = last_useful_line(apt.stdout)
        blocks.extend([f"{pkg} : réinstallation échouée.", err, ""])
        return
    check = run_command(["debsums", "-s", pkg])
    if sums_ok(check):
        restored.append(pkg)
        blocks.extend([f"{pkg} réinstallé.", "La somme correspond.", ""])
        return
    if archive_explains(pkg, check.stdout):
        return
    note_failure(pkg, check.stdout, failed, blocks)


def write_success(restored):
    if len(restored) == 1:
        sys.stdout.write(f"debsums : {restored[0]} réinstallé, somme rétablie")
        return
    sys.stdout.write(f"debsums : {len(restored)} paquets réinstallés, sommes rétablies")


def write_report(log_path, blocks, restored, failed):
    report = "\n".join(blocks).rstrip()
    log_path.write_text((report + "\n") if report else "")
    if restored and not failed:
        write_success(restored)
        return
    if restored or failed:
        sys.stdout.write("debsums : correction incomplète")


def reset_packages(log_path, packages, leftover):
    restored = []
    failed = []
    blocks = []
    try:
        if packages:
            purge_cache()
        for pkg in packages:
            take_package(pkg, restored, failed, blocks)
        for line in leftover:
            failed.append(line)
            blocks.extend([line, ""])
        write_report(log_path, blocks, restored, failed)
    finally:
        remove_cache()


if __name__ == "__main__":
    log_path = Path(sys.argv[1])
    packages, leftover = collect_lines(log_path.read_text(errors="replace"))
    reset_packages(log_path, packages, leftover)
