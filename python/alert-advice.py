#!/usr/bin/env python3
# =============================================================================
# File       : python/alert-advice.py
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Render advice text about one integrity or malware log.
# Note       : A crash summary stays empty. The catalog still has to be readable.
# -----------------------------------------------------------------------------


import os
import re
import shlex
import sys

KEY_RE = re.compile(r"^[a-z][a-z0-9-]*(?:\.[a-z0-9-]+)+$")
RECORD_RE = re.compile(r"^\[([a-z][a-z0-9-]*(?:\.[a-z0-9-]+)+)\]$")


def store_text(data, key, value):
    if not key:
        return
    text = "\n".join(value)
    while text.endswith("\n"):
        text = text[:-1]
    data[key] = text


def load_text_file(path, data):
    key = ""
    value = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            match = RECORD_RE.match(line)
            if match:
                store_text(data, key, value)
                key = match.group(1)
                value = []
                continue
            if key:
                value.append(line)
        store_text(data, key, value)


def read_text_directory(directory, data):
    if not directory or not os.path.isdir(directory):
        return
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".txt"):
            continue
        path = os.path.join(directory, name)
        if not os.path.isfile(path):
            continue
        load_text_file(path, data)


def load_directories(spec):
    data = {}
    for directory in (spec or "").split(":"):
        if directory:
            read_text_directory(directory, data)
    return data


LANG_TEXT = load_directories(os.environ.get("TEXT_LANG_DIRS", ""))
EN_TEXT = load_directories(os.environ.get("TEXT_EN_DIRS", ""))


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


def load_late_ids():
    return {
        "aide.removed",
        "aide.package",
        "aide.conffile",
        "aide.unknown",
        "chk.unknown",
        "rk.unknown",
    }


def load_unknown_ids():
    return {
        "aide": "aide.unknown",
        "chkrootkit": "chk.unknown",
        "rkhunter": "rk.unknown",
    }


def load_loop_vars():
    return {
        "paths": "p",
        "cmds": "c",
        "pids": "pid",
        "bins": "b",
        "ports": "port",
        "ifaces": "iface",
    }


def load_binary_head():
    return {
        "amd",
        "basename",
        "biff",
        "chfn",
        "chsh",
        "cron",
        "date",
        "du",
        "dirname",
        "echo",
        "egrep",
        "env",
        "find",
        "fingerd",
        "gpm",
        "grep",
        "hdparm",
        "su",
        "ifconfig",
        "inetd",
        "identd",
        "init",
        "killall",
        "login",
        "ls",
        "lsof",
        "mail",
    }


def load_binary_tail():
    return {
        "mingetty",
        "netstat",
        "named",
        "passwd",
        "pidof",
        "pop2",
        "pop3",
        "ps",
        "pstree",
        "rpcinfo",
        "rlogind",
        "rshd",
        "slogin",
        "sendmail",
        "sshd",
        "syslogd",
        "tar",
        "tcpd",
        "tcpdump",
        "top",
        "telnetd",
        "timed",
        "traceroute",
        "vdir",
        "w",
        "write",
    }


def load_binary_names():
    names = load_binary_head()
    names.update(load_binary_tail())
    return names


def load_app_pairs():
    return (
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


def load_aide_patterns():
    global AIDE_ENTRY, AIDE_HEAD, AIDE_DIFF, AIDE_DB, AIDE_PATH, AIDE_ENTRY_PATH, REMOVED_LINE, PATH_TOKEN
    AIDE_ENTRY = re.compile(r"^(?:[fdlcbpsDP!?][+.\-:=> <?A-Za-z]*:\s+\S|(?:added|removed|changed):\s+\S)")
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


LATE = load_late_ids()
UNKNOWN = load_unknown_ids()
LOOP_VARS = load_loop_vars()
BINARIES = load_binary_names()
APP_PAIRS = load_app_pairs()
load_aide_patterns()


class Finding:
    def __init__(self, lines, paths):
        self.lines = lines
        self.paths = paths


def start_record(records, current, raw):
    if current:
        records.append(current)
    return {"id": raw[1:-1]}


def feed_field(records, current, raw):
    if not raw.strip() or raw.startswith("#"):
        return current, True
    if raw.startswith("[") and raw.endswith("]"):
        return start_record(records, current, raw), True
    return current, False


def feed_value(current, raw):
    if current is None:
        return None, []
    if raw.endswith("<<"):
        return raw[:-2], []
    if "=" in raw:
        key, value = raw.split("=", 1)
        current[key.strip()] = value.strip()
    return None, []


def feed_block(current, mode, buf, raw):
    if raw == mode + ">>":
        current[mode] = "\n".join(buf).strip("\n")
        return None, []
    buf.append(raw)
    return mode, buf


def prepare_records(records):
    for rec in records:
        rec["regex"] = re.compile(rec.get("match") or r"$^")
        rec["hold"] = rec.get("hold", "0")
        if rec.get("hold_if"):
            rec["hold_re"] = re.compile(rec["hold_if"])
        else:
            rec["hold_re"] = None
    return records


def parse_catalog(text):
    records = []
    current = None
    mode = None
    buf = []
    for raw in text.splitlines():
        if mode:
            mode, buf = feed_block(current, mode, buf, raw)
            continue
        current, taken = feed_field(records, current, raw)
        if taken:
            continue
        mode, buf = feed_value(current, raw)
    if current:
        records.append(current)
    return prepare_records(records)


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


def aide_keep(line, stripped):
    if not stripped:
        return False
    if line[:1] in (" ", "\t"):
        return False
    if AIDE_ENTRY.match(line):
        return True
    if AIDE_HEAD.match(stripped):
        return True
    return bool(AIDE_DIFF.match(stripped))


def aide_findings(text):
    findings = []
    for raw in text.splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        if AIDE_DB.match(stripped):
            break
        if not aide_keep(line, stripped):
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


def snap_file(path, files):
    base = os.path.basename(path)
    found = re.search(r"(snap-.+\.mount)$", base)
    if not found:
        return ""
    filename = found.group(1)
    if filename not in files:
        files.append(filename)
    return filename


def snap_name(filename):
    decoded = re.sub(r"(?i)\\x2d", "-", filename)
    found = re.match(r"snap-(.+)-(\d+)\.mount$", decoded)
    if not found:
        return ""
    return found.group(1)


def collect_snaps(paths):
    files = []
    snaps = []
    for path in paths:
        filename = snap_file(path, files)
        if not filename:
            continue
        snap = snap_name(filename)
        if snap and snap not in snaps:
            snaps.append(snap)
    return files, snaps


def snap_lines(files, snaps, paths):
    lines = []
    chosen = files
    if not chosen:
        chosen = [os.path.basename(path) for path in paths if path]
    for filename in chosen:
        lines.append("sudo find /etc/systemd/system -name " + shlex.quote(filename) + " -printf '%y %m %u:%g %p\\n'")
    if snaps:
        for snap in snaps:
            lines.append("snap info " + shlex.quote(snap))
    else:
        lines.append("echo " + shlex.quote(text_get("alert.snap.unrecognized")))
    lines.append("snap changes")
    return "\n".join(lines)


def build_snap(paths):
    files, snaps = collect_snaps(paths)
    return snap_lines(files, snaps, paths)


def bin_values(text):
    # bins should stay empty when the template has no real binary path.
    found = extract_bins(text)
    if found:
        return quote_join(found)
    return ""


def pkg_values(rec, text):
    kind = rec.get("kind") or ""
    command = rec.get("command", "")
    if kind == "apps" or "{pkgs}" in command:
        return quote_join(extract_pkgs(text))
    return ""


def command_present(rec, paths, raw_lines, text):
    return {
        "paths": quote_join(paths),
        "cmds": quote_join(extract_cmds(text)),
        "pids": quote_join(extract_pids(text)),
        "bins": bin_values(text),
        "ports": quote_join(extract_ports(text)),
        "ifaces": quote_join(extract_ifaces(text)),
        "pkgs": pkg_values(rec, text),
        "raw_lines": quote_join(raw_lines),
    }


def finish_command(kind, script):
    if kind == "promisc" and "for iface in" not in script:
        extra = "ip -d link show"
        script = (script + "\n" + extra).strip() if script else extra
    if re.search(r"\{[a-z_]+\}", script):
        script = script + "\necho " + shlex.quote(text_get("alert.command.missing"))
    return script.strip()


def command_for(rec, paths, raw_lines, text):
    kind = rec.get("kind") or ""
    if kind == "snap" or rec["id"] == "aide.snap-mount":
        return build_snap(paths)
    present = command_present(rec, paths, raw_lines, text)
    script = apply_tokens(rec.get("command", ""), present)
    return finish_command(kind, script)


def take_group(groups, order, assigned, rec, finding):
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


def owned_id(finding, assigned):
    for path in finding.paths:
        if path in assigned:
            return assigned[path]
    return None


def regex_hit(specific, text):
    for rec in specific:
        if rec["regex"].search(text):
            return rec
    return None


def removed_record(tool, finding, by_id):
    if tool != "aide":
        return None
    if not finding.lines:
        return None
    if not REMOVED_LINE.match(finding.lines[0].strip()):
        return None
    return by_id.get("aide.removed")


def package_record(tool, finding, by_id):
    if tool != "aide":
        return None
    if not finding.paths:
        return None
    if not is_pkg_path(finding.paths[0]):
        return None
    return by_id.get("aide.package")


def conffile_record(tool, finding, by_id):
    if tool != "aide":
        return None
    if not finding.paths:
        return None
    if not is_etc_path(finding.paths[0]):
        return None
    return by_id.get("aide.conffile")


def aide_fallback(tool, finding, by_id):
    chosen = removed_record(tool, finding, by_id)
    if chosen is not None:
        return chosen
    chosen = package_record(tool, finding, by_id)
    if chosen is not None:
        return chosen
    return conffile_record(tool, finding, by_id)


def place_finding(groups, order, assigned, by_id, specific, tool, finding):
    owner = owned_id(finding, assigned)
    if owner:
        take_group(groups, order, assigned, by_id[owner], finding)
        return
    text = "\n".join(finding.lines)
    chosen = regex_hit(specific, text)
    if chosen is None:
        chosen = aide_fallback(tool, finding, by_id)
    if chosen is None:
        chosen = by_id.get(UNKNOWN[tool])
    if chosen is None:
        return
    take_group(groups, order, assigned, chosen, finding)


def classify(tool, findings, records):
    by_id = {rec["id"]: rec for rec in records}
    specific = [rec for rec in records if rec.get("tool") == tool and rec["id"] not in LATE]
    groups = {}
    order = []
    assigned = {}
    for finding in findings:
        place_finding(groups, order, assigned, by_id, specific, tool, finding)
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


def crashed(summary):
    return bool(
        re.search(
            r"planté|crashed|abgestürzt|bloqueó|erreur rc=|error rc=|Fehler rc=|"
            r"n'est pas allé au bout|did not finish|nicht zu Ende|no llegó al final",
            summary or "",
            re.I,
        )
    )


def with_summary(body, summary):
    phrases = (
        "mirrors.dat modifié hors",
        "mirrors.dat changed outside",
        "mirrors.dat geändert außerhalb",
        "mirrors.dat modificado fuera",
    )
    for phrase in phrases:
        if summary and phrase in summary and phrase not in body:
            return summary + "\n" + body
    return body


def findings_of(tool, body):
    if tool == "aide":
        return aide_findings(body)
    return other_findings(tool, body)


def render(tool, log_text, summary, catalog_text):
    tool = normalize_tool(tool)
    if not tool:
        return "", 0
    if crashed(summary):
        return "", 0
    records = parse_catalog(catalog_text)
    body = with_summary(log_text or "", summary)
    findings = findings_of(tool, body)
    if not findings:
        return "", 0
    groups = classify(tool, findings, records)
    if not groups:
        return "", 0
    advice = "\n\n".join(section(group) for group in groups)
    return advice, hold_of(groups)


def argv_at(cursor):
    if cursor < len(sys.argv):
        return sys.argv[cursor]
    return ""


def read_log(log_path):
    if not log_path or not os.path.isfile(log_path):
        return ""
    with open(log_path, encoding="utf-8", errors="replace") as handle:
        return handle.read()


def main():
    tool = argv_at(1)
    log_path = argv_at(2)
    summary = argv_at(3)
    catalog_path = argv_at(4)
    log_text = read_log(log_path)
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
