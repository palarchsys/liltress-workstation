#!/usr/bin/env python3
# =============================================================================
# File       : python/alert-advice.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

"""Render the false-positive advice for one AIDE, chkrootkit or rkhunter log."""

import os
import re
import shlex
import sys

KEY_RE = re.compile(r"^[a-z][a-z0-9-]*(?:\.[a-z0-9-]+)+$")
RECORD_RE = re.compile(r"^\[([a-z][a-z0-9-]*(?:\.[a-z0-9-]+)+)\]$")


def read_text_dir(directory, data):
    if not directory or not os.path.isdir(directory):
        return
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".txt"):
            continue
        path = os.path.join(directory, name)
        if not os.path.isfile(path):
            continue
        key = ""
        value = []

        def store():
            nonlocal key, value
            if not key:
                return
            text = "\n".join(value)
            while text.endswith("\n"):
                text = text[:-1]
            data[key] = text

        with open(path, encoding="utf-8", errors="replace") as handle:
            for raw in handle:
                line = raw.rstrip("\n")
                match = RECORD_RE.match(line)
                if match:
                    store()
                    key = match.group(1)
                    value = []
                    continue
                if key:
                    value.append(line)
            store()


def load_dirs(spec):
    data = {}
    for directory in (spec or "").split(":"):
        if directory:
            read_text_dir(directory, data)
    return data


LANG_TEXT = load_dirs(os.environ.get("TEXT_LANG_DIRS", ""))
EN_TEXT = load_dirs(os.environ.get("TEXT_EN_DIRS", ""))


def text_get(key):
    chosen = LANG_TEXT.get(key)
    if chosen:
        return chosen
    chosen = EN_TEXT.get(key)
    if chosen:
        return chosen
    return key


def apply_text(text, *args):
    def repl(match):
        num = int(match.group(1))
        if 1 <= num <= len(args):
            return str(args[num - 1])
        return match.group(0)

    return re.sub(r"\{(\d+)\}", repl, text)


def resolve(value):
    if not value or "\n" in value:
        return value or ""
    if KEY_RE.match(value):
        return text_get(value)
    return value

LATE = {
    "aide.removed",
    "aide.package",
    "aide.conffile",
    "aide.unknown",
    "chk.unknown",
    "rk.unknown",
}
UNKNOWN = {
    "aide": "aide.unknown",
    "chkrootkit": "chk.unknown",
    "rkhunter": "rk.unknown",
}
LOOP_VARS = {
    "paths": "p",
    "cmds": "c",
    "pids": "pid",
    "bins": "b",
    "ports": "port",
    "ifaces": "iface",
}
BINARIES = {
    "amd", "basename", "biff", "chfn", "chsh", "cron", "date", "du", "dirname",
    "echo", "egrep", "env", "find", "fingerd", "gpm", "grep", "hdparm", "su",
    "ifconfig", "inetd", "identd", "init", "killall", "login", "ls", "lsof",
    "mail", "mingetty", "netstat", "named", "passwd", "pidof", "pop2", "pop3",
    "ps", "pstree", "rpcinfo", "rlogind", "rshd", "slogin", "sendmail", "sshd",
    "syslogd", "tar", "tcpd", "tcpdump", "top", "telnetd", "timed", "traceroute",
    "vdir", "w", "write",
}
APP_PAIRS = (
    ("openssh", "openssh-server"),
    ("openssl", "openssl"),
    ("exim", "exim4"),
    ("apache", "apache2"),
    ("nginx", "nginx"),
    ("proftpd", "proftpd-basic"),
    ("vsftpd", "vsftpd"),
    ("sendmail", "sendmail"),
    ("bind9", "bind9"),
    ("named", "bind9"),
    ("ssh", "openssh-server"),
)
AIDE_ENTRY = re.compile(
    r"^(?:[fdlcbpsDP!?][+.\-:=> <?A-Za-z]*:\s+\S|(?:added|removed|changed):\s+\S)"
)
AIDE_HEAD = re.compile(
    r"^(?:file|directory|fifo|link|block device|character device|"
    r"socket|door|port|unknown file type):\s+\S",
    re.I,
)
AIDE_DIFF = re.compile(r"^entry \S+ in databases has different attributes\b", re.I)
AIDE_DB = re.compile(r"^the attributes of the \(uncompressed\) database\b", re.I)
AIDE_PATH = re.compile(
    r"^(?:[fdlcbpsDP!?][+.\-:=> <?A-Za-z]*|(?:added|removed|changed)|"
    r"(?:File|Directory|FIFO|Link|Block device|Character device|Socket|Door|Port|"
    r"Unknown file type)):\s+(\S.*)$",
    re.I,
)
AIDE_ENTRY_PATH = re.compile(
    r"^Entry (\S+) in databases has different attributes\b",
    re.I,
)
REMOVED_LINE = re.compile(r"^(?:removed:\s+\S|[fdlcbpsDP!?][-]{3,}:\s+\S)")
PATH_TOKEN = re.compile(
    r"(?<![A-Za-z0-9])(/(?:[\w.+@=-]|\\x[0-9A-Fa-f]{2})+"
    r"(?:/(?:[\w.+@=-]|\\x[0-9A-Fa-f]{2})+)*)"
)


class Finding:
    def __init__(self, lines, paths):
        self.lines = lines
        self.paths = paths


def parse_catalog(text):
    records = []
    current = None
    mode = None
    buf = []

    def flush_mode():
        nonlocal mode, buf
        if current is not None and mode:
            current[mode] = "\n".join(buf).strip("\n")
        mode = None
        buf = []

    for raw in text.splitlines():
        if mode:
            if raw == mode + ">>":
                flush_mode()
            else:
                buf.append(raw)
            continue
        if not raw.strip() or raw.startswith("#"):
            continue
        if raw.startswith("[") and raw.endswith("]"):
            if current:
                records.append(current)
            current = {"id": raw[1:-1]}
            continue
        if current is None:
            continue
        if raw.endswith("<<"):
            mode = raw[: -2]
            buf = []
            continue
        if "=" in raw:
            key, value = raw.split("=", 1)
            current[key.strip()] = value.strip()
    if current:
        records.append(current)
    for rec in records:
        rec["regex"] = re.compile(rec.get("match") or r"$^")
        rec["hold"] = rec.get("hold", "0")
        if rec.get("hold_if"):
            rec["hold_re"] = re.compile(rec["hold_if"])
        else:
            rec["hold_re"] = None
    return records


def normalize_tool(tool):
    key = (tool or "").strip().lower()
    if key in {"aide", "chkrootkit", "rkhunter"}:
        return key
    return ""


def aide_path(line):
    stripped = line.strip()
    match = AIDE_ENTRY_PATH.match(stripped)
    if match:
        return match.group(1).strip()
    match = AIDE_PATH.match(stripped)
    if match:
        return match.group(1).strip()
    return ""


def aide_findings(text):
    findings = []
    for raw in text.splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        if not stripped:
            continue
        if AIDE_DB.match(stripped):
            break
        if line[:1] in (" ", "\t"):
            continue
        if not (AIDE_ENTRY.match(line) or AIDE_HEAD.match(stripped) or AIDE_DIFF.match(stripped)):
            continue
        path = aide_path(line)
        findings.append(Finding([line], [path] if path else []))
    return findings


def is_noise(line):
    stripped = line.strip()
    if re.match(r"^\d{4}-\d{2}-\d{2}T", stripped):
        return True
    if re.search(r"Rootkit Hunter version", stripped, re.I):
        return True
    if re.search(r"\[ (?:OK|Not found|None found|Skipped) \]", stripped):
        return True
    if re.match(
        r"(?i)^(start timestamp|end timestamp|summary:|total number of|"
        r"added entries|removed entries|changed entries|detailed information|"
        r"aide found|looking for|checking rkhunter data)",
        stripped,
    ):
        return True
    return False


def is_header(tool, line):
    stripped = line.strip()
    if tool == "chkrootkit":
        return bool(
            re.search(
                r"(?i)(INFECTED|PACKET SNIFFER|ifpromisc|deletion|"
                r"ld\.so\.preload|bpfdoor|haldrund|Checking\s+[`'\"]|"
                r"bindshell|wtmp|lastlog|\butmp\b|hidden|PROMISC)",
                stripped,
            )
        )
    return bool(
        re.search(
            r"(?i)(^warning:|replaced by a script|possible rootkit|promiscuous|"
            r"packet sniffer|hidden (?:file|directory|process)|uid of 0|"
            r"no password|empty password|mirrors\.dat modifié|startup file|"
            r"world-writable|world writable|immutable|deleted|listening port|"
            r"hidden port|ld\.so\.preload|\binetd\b|suspect|out of date|"
            r"rootkit|trojan|malware)",
            stripped,
        )
    )


def is_cont(line):
    if line[:1] in (" ", "\t"):
        return True
    stripped = line.strip()
    if stripped.startswith("/"):
        return True
    if re.match(r"(?i)^file:\s+\S", stripped):
        return True
    if re.match(r"(?i)^INFECTED\b", stripped):
        return True
    return False


def looks_like(line):
    stripped = line.strip()
    if stripped.startswith("/"):
        return True
    return bool(re.search(r"(?i)INFECTED|^warning:", stripped))


def extract_paths(text):
    found = []
    for line in text.splitlines():
        match = re.match(r"^\s*(?:File|Directory|Link):\s+(\S.*)$", line, re.I)
        if match:
            path = match.group(1).strip()
            if path not in found:
                found.append(path)
            continue
        for path in PATH_TOKEN.findall(line):
            if path.startswith("/proc/"):
                continue
            if path not in found:
                found.append(path)
    return found


def other_findings(tool, text):
    findings = []
    current = None

    def flush():
        nonlocal current
        if not current:
            return
        paths = extract_paths("\n".join(current))
        findings.append(Finding(current, paths))
        current = None

    for raw in text.splitlines():
        line = raw.rstrip()
        if not line.strip():
            flush()
            continue
        if is_noise(line):
            continue
        if current is not None and is_cont(line):
            current.append(line)
            continue
        if is_header(tool, line) or looks_like(line):
            flush()
            current = [line]
            continue
    flush()
    return findings


def is_pkg_path(path):
    return bool(re.match(r"^/(?:bin|sbin|usr|lib|lib64|boot)(?:/|$)", path or ""))


def is_etc_path(path):
    return path == "/etc" or (path or "").startswith("/etc/")


def quote_join(values, limit=40):
    # One quoted word per line. A single line of many paths exceeds 998
    # characters and the mail fold splits a path in the middle.
    shown = [shlex.quote(value) for value in list(values)[:limit]]
    if len(shown) <= 1:
        return shown[0] if shown else ""
    return " \\\n  ".join(shown)


def drop_empty_loops(script, present):
    for token, var in LOOP_VARS.items():
        if present.get(token):
            continue
        script = re.sub(
            rf"for {var} in \{{{token}\}}; do\n.*?^done\n?",
            "",
            script,
            flags=re.S | re.M,
        )
        script = script.replace("{" + token + "}", "")
    return script


def apply_tokens(script, present):
    script = drop_empty_loops(script, present)
    for token, value in present.items():
        if value:
            script = script.replace("{" + token + "}", value)
    if not present.get("raw_lines"):
        script = re.sub(r"^printf '%s\\n' \{raw_lines\}\n?", "", script, flags=re.M)
        script = script.replace("{raw_lines}", "")
    else:
        script = script.replace("{raw_lines}", present["raw_lines"])
    script = re.sub(r"sudo bash << 'EOF'\n\s*EOF\n?", "", script)
    script = re.sub(r"\n{3,}", "\n\n", script)
    return script.strip()


def extract_cmds(text):
    found = []
    for name in re.findall(r"Checking\s+[`'\"]([A-Za-z0-9_.+-]+)[`'\"]", text):
        if name in BINARIES and name not in found:
            found.append(name)
    return found


def extract_pids(text):
    found = []
    patterns = (
        r"(?i)\bpid[=: ]+(\d+)",
        r"\[(\d+)\]",
        r"/proc/(\d+)\b",
        r"(?i)\bprocess(?: id)?[=: ]+(\d+)",
    )
    for pattern in patterns:
        for number in re.findall(pattern, text):
            if number != "0" and number not in found:
                found.append(number)
    return found


def extract_ports(text):
    found = []
    for number in re.findall(r"(?i)ports?\D{0,16}(\d{1,5})\b", text):
        if number != "0" and number not in found:
            found.append(number)
    return found


def extract_ifaces(text):
    found = []
    pattern = (
        r"\b((?:docker0|virbr\d+|veth[A-Za-z0-9]+|br-[A-Za-z0-9]+|"
        r"tun\d+|tap\d+|wg\d+|tailscale\d+|"
        r"en(?:o|p|s|x)[A-Za-z0-9]+|wl[a-z]*\d+[A-Za-z0-9]*|eth\d+))\b"
    )
    for name in re.findall(pattern, text):
        if name not in found:
            found.append(name)
    return found


def extract_bins(text):
    found = []
    for path in re.findall(r"\((/[^()\s]+)\[\d+\]\)", text):
        if path not in found:
            found.append(path)
    return found


def extract_pkgs(text):
    found = []
    lower = text.lower()
    for needle, package in APP_PAIRS:
        if needle in lower and package not in found:
            found.append(package)
    if not found:
        found = ["openssh-server", "openssl"]
    return found


def build_snap(paths):
    files = []
    snaps = []
    for path in paths:
        base = os.path.basename(path)
        match = re.search(r"(snap-.+\.mount)$", base)
        if not match:
            continue
        filename = match.group(1)
        if filename not in files:
            files.append(filename)
        decoded = re.sub(r"(?i)\\x2d", "-", filename)
        name_match = re.match(r"snap-(.+)-(\d+)\.mount$", decoded)
        snap = name_match.group(1) if name_match else ""
        if snap and snap not in snaps:
            snaps.append(snap)
    lines = []
    chosen = files
    if not chosen:
        chosen = [os.path.basename(path) for path in paths if path]
    for filename in chosen:
        lines.append(
            "sudo find /etc/systemd/system -name "
            + shlex.quote(filename)
            + " -printf '%y %m %u:%g %p\\n'"
        )
    if snaps:
        for snap in snaps:
            lines.append("snap info " + shlex.quote(snap))
    else:
        lines.append("echo " + shlex.quote(text_get("alert.snap.unrecognized")))
    lines.append("snap changes")
    return "\n".join(lines)


def command_for(rec, paths, raw_lines, text):
    kind = rec.get("kind") or ""
    if kind == "snap" or rec["id"] == "aide.snap-mount":
        return build_snap(paths)
    present = {
        "paths": quote_join(paths),
        "cmds": quote_join(extract_cmds(text)),
        "pids": quote_join(extract_pids(text)),
        "bins": quote_join(extract_bins(text) or [path for path in paths if not path.endswith("/")]),
        "ports": quote_join(extract_ports(text)),
        "ifaces": quote_join(extract_ifaces(text)),
        "pkgs": quote_join(extract_pkgs(text) if kind == "apps" or "{pkgs}" in rec.get("command", "") else []),
        "raw_lines": quote_join(raw_lines),
    }
    # bins should stay empty when the template has no real binary path.
    if not extract_bins(text):
        present["bins"] = ""
    if kind != "apps" and "{pkgs}" not in rec.get("command", ""):
        present["pkgs"] = ""
    script = apply_tokens(rec.get("command", ""), present)
    if kind == "promisc" and "for iface in" not in script:
        extra = "ip -d link show"
        script = (script + "\n" + extra).strip() if script else extra
    if re.search(r"\{[a-z_]+\}", script):
        script = script + "\necho " + shlex.quote(text_get("alert.command.missing"))
    return script.strip()


def classify(tool, findings, records):
    by_id = {rec["id"]: rec for rec in records}
    specific = [
        rec for rec in records if rec.get("tool") == tool and rec["id"] not in LATE
    ]
    groups = {}
    order = []
    assigned = {}

    def take(rec, finding):
        gid = rec["id"]
        if gid not in groups:
            groups[gid] = {"rec": rec, "lines": [], "paths": []}
            order.append(gid)
        group = groups[gid]
        for line in finding.lines:
            if line not in group["lines"]:
                group["lines"].append(line)
        for path in finding.paths:
            if path and path not in group["paths"]:
                group["paths"].append(path)
                assigned[path] = gid

    for finding in findings:
        owner = None
        for path in finding.paths:
            if path in assigned:
                owner = assigned[path]
                break
        if owner:
            take(by_id[owner], finding)
            continue
        text = "\n".join(finding.lines)
        chosen = None
        for rec in specific:
            if rec["regex"].search(text):
                chosen = rec
                break
        if chosen is None and tool == "aide" and finding.lines and REMOVED_LINE.match(finding.lines[0].strip()):
            chosen = by_id.get("aide.removed")
        if (
            chosen is None
            and tool == "aide"
            and finding.paths
            and is_pkg_path(finding.paths[0])
        ):
            chosen = by_id.get("aide.package")
        if (
            chosen is None
            and tool == "aide"
            and finding.paths
            and is_etc_path(finding.paths[0])
        ):
            chosen = by_id.get("aide.conffile")
        if chosen is None:
            chosen = by_id.get(UNKNOWN[tool])
        if chosen is None:
            continue
        take(chosen, finding)
    return [groups[gid] for gid in order]


def section(group):
    rec = group["rec"]
    lines = group["lines"]
    shown = lines[:40]
    hidden = len(lines) - len(shown)
    text = "\n".join(lines)
    command = command_for(rec, group["paths"], shown, text)
    parts = ["@@BLOCK@@", "@@H@@ " + (resolve(rec.get("title")) or rec["id"])]
    notice = resolve(rec.get("notice"))
    if notice:
        parts.append(notice)
    parts.append("@@H@@ " + text_get("alert.label.lines"))
    parts.extend(shown)
    if hidden:
        parts.append(apply_text(text_get("alert.label.more"), hidden))
    parts.append("@@H@@ " + text_get("alert.label.command"))
    parts.append(command)
    parts.append("@@H@@ " + text_get("alert.label.benign"))
    parts.append(resolve(rec.get("benign", "")))
    parts.append("@@H@@ " + text_get("alert.label.malicious"))
    parts.append(resolve(rec.get("malicious", "")))
    return "\n".join(parts).rstrip()


def hold_of(groups):
    for group in groups:
        rec = group["rec"]
        if rec.get("hold") == "1":
            return 1
        if rec.get("hold_re") and rec["hold_re"].search("\n".join(group["lines"])):
            return 1
    return 0


def render(tool, log_text, summary, catalog_text):
    tool = normalize_tool(tool)
    if not tool:
        return "", 0
    if re.search(
        r"planté|crashed|abgestürzt|bloqueó|erreur rc=|error rc=|Fehler rc=|"
        r"n'est pas allé au bout|did not finish|nicht zu Ende|no llegó al final",
        summary or "",
        re.I,
    ):
        return "", 0
    records = parse_catalog(catalog_text)
    body = log_text or ""
    for mark in (
        "mirrors.dat modifié hors",
        "mirrors.dat changed outside",
        "mirrors.dat geändert außerhalb",
        "mirrors.dat modificado fuera",
    ):
        if summary and mark in summary and mark not in body:
            body = summary + "\n" + body
            break
    if tool == "aide":
        findings = aide_findings(body)
    else:
        findings = other_findings(tool, body)
    if not findings:
        return "", 0
    groups = classify(tool, findings, records)
    if not groups:
        return "", 0
    advice = "\n\n".join(section(group) for group in groups)
    return advice, hold_of(groups)


def main():
    tool = sys.argv[1] if len(sys.argv) > 1 else ""
    log_path = sys.argv[2] if len(sys.argv) > 2 else ""
    summary = sys.argv[3] if len(sys.argv) > 3 else ""
    catalog_path = sys.argv[4] if len(sys.argv) > 4 else ""
    log_text = ""
    if log_path and os.path.isfile(log_path):
        with open(log_path, encoding="utf-8", errors="replace") as handle:
            log_text = handle.read()
    with open(catalog_path, encoding="utf-8") as handle:
        catalog_text = handle.read()
    advice, hold = render(tool, log_text, summary, catalog_text)
    sys.stdout.write(f"HOLD={hold}\n---\n")
    if advice:
        sys.stdout.write(advice)
        if not advice.endswith("\n"):
            sys.stdout.write("\n")


if __name__ == "__main__":
    main()
