#!/usr/bin/env python3
# =============================================================================
# File       : python/check-advice.py
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Check that the advice catalog has every expected record.
# Note       : The command body sits between the two command marks.
# -----------------------------------------------------------------------------


import re
import sys
from pathlib import Path

FIELD_RE = re.compile(r"^(title|benign|malicious)=(\S+)\s*$", re.M)
KEYS = ("title=", "tool=", "match=", "command<<", "command>>", "benign=", "malicious=")


def expected_ids():
    return """
aide.snap-mount aide.snap-apparmor aide.kernel-boot aide.modules aide.firmware
aide.python aide.locale aide.dbus aide.polkit aide.accounts aide.shells
aide.sudoers aide.ssh-keys aide.sshd aide.preload aide.ldso aide.resolved
aide.systemd aide.cron aide.udev aide.pam aide.alternatives aide.certs
aide.letsencrypt aide.hosts aide.timezone aide.apt aide.netplan aide.wireguard
aide.ufw aide.fail2ban aide.crowdsec aide.grub aide.sysctl aide.modules-load
aide.product aide.machine-id aide.removed aide.package aide.conffile aide.unknown
chk.bpfdoor chk.preload chk.binary chk.worm-string chk.sniffer chk.promisc
chk.wtmp chk.lkm chk.bindshell chk.php chk.aliens chk.crontab chk.inetd
chk.history chk.unknown
rk.preload rk.empty-password rk.accounts rk.mirrors rk.script rk.properties
rk.hidden-proc rk.hidden rk.deleted rk.dev rk.sniffer rk.promisc rk.ports
rk.ssh rk.startup rk.apps rk.writable rk.immutable rk.module rk.inetd rk.hosts
rk.named rk.unknown
""".split()


def require_ids(ids, expected):
    if ids == expected:
        return
    print("ids", len(ids), "expected", len(expected))
    print("missing", [item for item in expected if item not in ids])
    print("extra", [item for item in ids if item not in expected])
    sys.exit(1)


def records_of(text):
    found = []
    for rec in re.split(r"(?=^\[)", text, flags=re.M):
        if rec.startswith("["):
            found.append(rec)
    return found


def blank_record(command, benign, malicious, title):
    if not command:
        return True
    if "." not in benign or "." not in malicious or "." not in title:
        return True
    return False


def require_record(rec):
    for key in KEYS:
        if key not in rec:
            print(rec.splitlines()[0], "sans", key)
            sys.exit(1)
    command = rec.split("command<<", 1)[1].split("command>>", 1)[0].strip()
    fields = {name: value for name, value in FIELD_RE.findall(rec)}
    benign = fields.get("benign", "")
    malicious = fields.get("malicious", "")
    title = fields.get("title", "")
    if blank_record(command, benign, malicious, title):
        print(rec.splitlines()[0], "texte vide")
        sys.exit(1)


def check_advice():
    text = Path(sys.argv[1]).read_text(encoding="utf-8")
    ids = re.findall(r"^\[([^\]]+)\]", text, re.M)
    require_ids(ids, expected_ids())
    for rec in records_of(text):
        require_record(rec)
    sys.exit(0)


check_advice()
