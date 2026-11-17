#!/usr/bin/env python3
# =============================================================================
# File       : python/aide-home.py
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Place the home account block into one AIDE configuration.
# Note       : The server keeps a path only when that path is a file.
# -----------------------------------------------------------------------------


import sys
from pathlib import Path

SERVER_BEGIN = "# BEGIN Liltress account"
SERVER_END = "# END Liltress account"
WORK_BEGIN = "# BEGIN Liltress Workstation account"
WORK_END = "# END Liltress Workstation account"
OLD_BEGIN = "# BEGIN High-Fortress User account"
OLD_END = "# END High-Fortress User account"


def drop_marked(text, starts, ends):
    # A marker line is dropped. Lines inside the pair are dropped too.
    out = []
    skip = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped in starts:
            skip = True
            continue
        if stripped in ends:
            skip = False
            continue
        if not skip:
            out.append(line)
    return out


def server_names(home):
    return [
        f"{home}/.ssh/authorized_keys",
        f"{home}/.bashrc",
        f"{home}/.profile",
        f"{home}/.bash_profile",
    ]


def workstation_names(home):
    return server_names(home) + [
        f"{home}/.config/autostart",
        f"{home}/.config/systemd/user",
    ]


def write_server(path, home):
    out = drop_marked(path.read_text(), (SERVER_BEGIN,), (SERVER_END,))
    existing = [name for name in server_names(home) if Path(name).is_file()]
    if existing:
        block = [SERVER_BEGIN]
        block.extend(f"{name} All" for name in existing)
        block.append(SERVER_END)
        out.extend(block)
    path.write_text("\n".join(out) + "\n")


def write_workstation(path, home):
    out = drop_marked(path.read_text(), (WORK_BEGIN, OLD_BEGIN), (WORK_END, OLD_END))
    block = [WORK_BEGIN]
    block.extend(f"{name} All" for name in workstation_names(home))
    block.append(f"!{home}/.ssh/known_hosts")
    block.append(f"!{home}/.ssh/known_hosts.old")
    block.append(WORK_END)
    out.extend(block)
    path.write_text("\n".join(out) + "\n")


def run_aide_home():
    mode = sys.argv[1]
    sys.argv = [sys.argv[0]] + sys.argv[2:]
    if mode == "server":
        write_server(Path(sys.argv[1]), sys.argv[2].rstrip("/"))
        return
    if mode == "workstation":
        write_workstation(Path(sys.argv[1]), sys.argv[2].rstrip("/"))
        return
    sys.exit("mode python refusé")


run_aide_home()
