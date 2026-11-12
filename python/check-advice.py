#!/usr/bin/env python3
# =============================================================================
# File       : python/check-advice.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
ids = re.findall(r"^\[([^\]]+)\]", text, re.M)
expected = """
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
if ids != expected:
    print("ids", len(ids), "expected", len(expected))
    print("missing", [item for item in expected if item not in ids])
    print("extra", [item for item in ids if item not in expected])
    sys.exit(1)
recs = [rec for rec in re.split(r"(?=^\[)", text, flags=re.M) if rec.startswith("[")]
field_re = re.compile(r"^(title|benign|malicious)=(\S+)\s*$", re.M)
for rec in recs:
    for key in ("title=", "tool=", "match=", "command<<", "command>>", "benign=", "malicious="):
        if key not in rec:
            print(rec.splitlines()[0], "sans", key)
            sys.exit(1)
    command = rec.split("command<<", 1)[1].split("command>>", 1)[0].strip()
    fields = {name: value for name, value in field_re.findall(rec)}
    benign = fields.get("benign", "")
    malicious = fields.get("malicious", "")
    title = fields.get("title", "")
    if not command or "." not in benign or "." not in malicious or "." not in title:
        print(rec.splitlines()[0], "texte vide")
        sys.exit(1)
sys.exit(0)
