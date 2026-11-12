#!/usr/bin/env python3
# =============================================================================
# File       : python/name-list.py
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

import csv
import os
import re
from collections import defaultdict
from pathlib import Path

root = Path(os.environ["NAMES_ROOT"])
roots = ("share", "scripts", "agents", "workstation", "server")
skip_dirs = {".git", "logs", "node_modules", ".venv", "next_step", "__pycache__"}
# The generators are not product code. The schema JSON stays in the count.
skip_files = {
    "scripts/list-names.sh",
    "scripts/list-config.sh",
    "name-variables.csv",
    "name-functions.csv",
    "name-comments.csv",
    "name-references.csv",
}
prefix_var = {"W": "W_", "S": "S_", "T": "T_", "n": ""}
prefix_fn = {"g": "g_", "w": "w_", "s": "s_", "t": "t_", "n": ""}
scope_of = {
    "W": "workstation", "S": "server", "T": "test",
    "g": "shared", "w": "workstation", "s": "server", "t": "test",
    "n": "shared",
}
shared_vars = """
ACCOUNT_SNAPSHOT ACCOUNT_USER AIDE_REFRESH ANTIBOT_HMAC_SECRET API_BASE_URL
ARTIFACTS BANNER_MESSAGE BASE BEHAVIOR_WATCH BOOT_ACCURACY BOOT_ON_BOOT_SEC
BRANCH CHKROOTKIT_IGNORE CLAMAV_DEFER CLAMAV_EVENT_FILE CLAMAV_EVENT_KIND
CLAMAV_EVENT_MAIL CLAMAV_EVENT_VIRUS CLAMAV_KILL CLAMAV_QUARANTINE
CLAMAV_QUARANTINE_DIR CLAMAV_RESPONSE_STAMP
CLAMAV_TEMPORARY_DIRECTORY CLAMAV_VIRUS_EVENT_PRESERVE CLAMONACC_BIN
CLAMONACC_LOG CLAMONACC_RESTART CLAMONACC_RESTART_SEC CLAM_BATCH CLAM_MODE
CLAM_STOP COMMIT_MESSAGE CONFIG_BASE_DIRECTORY CONFIG_ERRORS CONFIG_MODE
CONFIG_PREPARED CONFIG_ROOT CONFIRMED_COUNT CORS_ORIGINS CRASH_LABEL CRON_USER
CROWDSEC_BAN_DURATION CURL_KO CURL_OK DDOS_HARDENING_LEVEL DEBSUMS_IGNORE
DOCKER_BASE_DIRECTORY
DOCKER_DIRECTORY_LIVEKIT DOCKER_DIRECTORY_MATRIX DOCKER_DIRECTORY_SECURITY
DOCKER_DIRECTORY_WIREGUARD DOCKER_LOG_COMPRESS DOCKER_LOG_DRIVER
DOCKER_LOG_MAX_FILE DOCKER_LOG_MAX_SIZE DOCKER_NETWORK_PRODUCTION
DOCKER_NETWORK_SECURITY DOMAIN DOMAIN_ELEMENT DOMAIN_KEYCLOAK
DOMAIN_LIVEKIT_JWT DOMAIN_LIVEKIT_SFU DOMAIN_PROMETHEUS DOMAIN_SYNAPSE
DOMAIN_SYNAPSE_ADMIN DOMAIN_WEB_API DOMAIN_WIREGUARD EGRESS_AUDIT
EGRESS_AUDIT_FILE EGRESS_KERNEL EGRESS_LOG EGRESS_REGISTRY
ELEMENT_PUBLIC_BASE_URL ENV_FILE_LIVEKIT ENV_FILE_MATRIX ENV_FILE_SECURITY
ENV_FILE_WEB ENV_FILE_WIREGUARD FAILLOCK_DENY FAILLOCK_FAIL_INTERVAL
FAILLOCK_UNLOCK HOSTNAME_LIVEKIT HOSTNAME_MATRIX HOSTNAME_WIREGUARD
HOURLY_ACCURACY HOURLY_EVERY HOURLY_ON_BOOT_SEC IDLE_ACCURACY IDLE_EVERY
INSTALL_DIRECTORY INSTALL_LOG_DIR INSTALL_LOG_FILE INSTALL_ROOT JWT_URL
KEYCLOAK_CLIENT KEYCLOAK_PUBLIC_BASE_URL KEYCLOAK_REALM LANGUAGE LIMIT_WRAP
LIVEKIT_URL LOGS_COLLECTED LOG_SYS LYNIS_MIN_SCORE
MAIL_ABOUT MAIL_ACTIONS MAIL_ALERTS MAIL_ATTACH MAIL_BLOCK_ACTIONS MAIL_BLOCK_FILES MAIL_BLOCK_IGNORE MAIL_BLOCK_SERVICES MAIL_FILES MAIL_FOOTER MAIL_IGNORE MAIL_REDACT MAIL_REQUIRE_FLAG MAIL_SERVICES MAIL_SUBTITLE MAIL_TEMPLATE
MAIL_TEMPLATE_FILE MAIN_GROUP MAIN_USER MATRIX_ADMIN_ACCESS_TOKEN
MATRIX_ADMIN_PASSWORD MATRIX_ADMIN_USER MATRIX_PUBLIC_BASE_URL
MATRIX_REGISTRATION_SHARED_SECRET MATRIX_SERVER_NAME MODE_DEV MODE_TEST
MOVED_COUNT MOVE_ACTION MOVE_STORED NET_ISOLATE NET_ISOLATE_SEC
NGINX_ADMIN_USER NGINX_CERTBOT_MAIL_ADDRESS NGINX_HTPASSWD_PATH
NGINX_HTPASSWD_REALM ONACCESS_EXCLUDE_ROOTUID ONACCESS_EXCLUDE_UNAME
ONACCESS_EXTRA_SCANNING ONACCESS_FIXED ONACCESS_FIXED_EXCLUDE ONACCESS_MARKER
ONACCESS_MAX_FILE_SIZE ONACCESS_MOUNTS ONACCESS_PREVENTION OS_ID OS_VERSION
PAM_PASSWORD_MIN_LENGTH PERIODIC_ACCURACY PERIODIC_EVERY PERIODIC_ON_BOOT_SEC
PORT_CROWDSEC_LAPI PORT_ELEMENT PORT_KEYCLOAK PORT_LIVEKIT_JWT
PORT_LIVEKIT_REDIS PORT_LIVEKIT_SFU PORT_PROMETHEUS PORT_SYNAPSE
PORT_SYNAPSE_ADMIN PORT_SYNAPSE_POSTGRESQL PORT_WEB_API PORT_WEB_UI
PORT_WIREGUARD_UDP PORT_WIREGUARD_UI POSTFIX_MAIL_ADDRESS
POSTFIX_MAIL_PASSWORD POSTFIX_MAIL_SMTP POSTFIX_SMTP_LOGIN
POSTGRES_KEYCLOAK_DB POSTGRES_KEYCLOAK_PASSWORD POSTGRES_KEYCLOAK_USER
POSTGRES_SYNAPSE_DB POSTGRES_SYNAPSE_PASSWORD POSTGRES_SYNAPSE_USER
POSTGRES_WEB_DB POSTGRES_WEB_PASSWORD POSTGRES_WEB_USER PRODUCT_ROOT
PROJECT_NAME PROJECT_SLUG PROJECT_VERSION PUBLIC_BASE_URL QUARANTINE_COMM
QUARANTINE_PID RCLONE REBOOT_ACCURACY REBOOT_EVERY REPO_URL RKHUNTER_REFRESH
ROUTE_ROOT RUN_LOG SCAN_SKIP_BAD SCAN_SKIP_FILE SCAN_SKIP_HOME SCAN_SKIP_VALID
SECRET_DIRECTORY SECRET_PREPARED SEEN SENT SERVER_TYPE SSH_BANNER_PATH
SSH_CLIENT_ALIVE_COUNT_MAX SSH_CLIENT_ALIVE_INTERVAL SSH_LOGIN_GRACE_TIME
SSH_MAX_AUTH_TRIES SSH_PORT SSH_SERVICE_NAME SWAP_FILE SWAP_MAPPER_NAME
SWAP_SIZE TEMPLATE TEMPLATE_WORKSTATION_RESTORE_BEGIN
TEMPLATE_WORKSTATION_RESTORE_END TEMPLATE_WORKSTATION_SAVE_BEGIN
TEMPLATE_WORKSTATION_SAVE_END TEXT_DIR TEXT_DIR_LOADED TEXT_ENGLISH
TEXT_EN_DIRS TEXT_EXCERPT_ATTR TEXT_EXCERPT_MORE TEXT_LANGUAGE TEXT_LANG_DIRS
TEXT_READY TEXT_REDACTED TEXT_REDACTED_KEY TEXT_SELECTED TEXT_TEMPLATE_NO_PRE
TEXT_TEMPLATE_UNREADABLE TIMER_PERSISTENT TURNSTILE_SECRET_KEY
TURNSTILE_SITE_KEY UBUNTU_PRO_TOKEN UFW_DEFAULT_INCOMING UFW_DEFAULT_OUTGOING
UFW_DEFAULT_ROUTED UFW_FORWARD_POLICY UFW_IPT_EXTRA UFW_IPV6 UFW_LINK_LOCAL
UFW_LOGGING UFW_SSH_COMMENT_LAN UFW_SSH_COMMENT_OPEN
UNBOUND_FORWARDERS USBGUARD_ENABLE USER VERIFY_BASENAME
VERIFY_FAIL VERIFY_LAUNCH_DIRECTORY VERIFY_PASS VERIFY_REPORT_MD
VERIFY_REPORT_TSV VERIFY_REPORT_TXT VERIFY_SKIP VERIFY_STAMP VERIFY_WARN
VPN_ACTIVE VPN_BOOT_PROFILE VPN_FAILOVER_TIMEOUT VPN_FAILOVER_TRIES
VPN_FW_PRIORITY VPN_HANDSHAKE_TIMEOUT VPN_IFACE_OVPN VPN_IFACE_WG VPN_MODE
VPN_ON_BOOT VPN_RULE_PRIO_BYPASS_FROM VPN_RULE_PRIO_BYPASS_TO
VPN_RULE_PRIO_ENDPOINT VPN_RULE_PRIO_SSH VPN_RULE_PRIO_TUNNEL VPN_SSH_MARK
VPN_TABLE_ID VPN_TABLE_NAME WATCHDOG_CPU_LIMIT WATCHDOG_HOLD_MAIL WATCHDOG_LIMIT_IO_NICE
WATCHDOG_LIMIT_NICE WATCHDOG_MAIL WEB_IMAGE_BACKEND WEB_IMAGE_FRONTEND
WEB_IMAGE_TAG WEB_REGISTRY WEB_UPDATE_SCRIPT WIREGUARD_ADMIN_PASSWORD
WIREGUARD_ALLOWED_IP WIREGUARD_DEFAULT_ADDRESS WIREGUARD_DEFAULT_DNS
WIREGUARD_HOST WIREGUARD_UI_URL
""".split()
var_re = re.compile(
    r"\b((?:W|S|T)_[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*|"
    + "|".join(sorted(shared_vars, key=len, reverse=True))
    + r")\b"
)
fn_re = re.compile(r"\b(t_[a-z][a-z0-9]*(?:_[a-z0-9]+)*)\b")
def_re = re.compile(r"^[ \t]*([a-z][a-z0-9_]*)\s*\(")
slug_re = re.compile(r"high-fortress\.com|liltress(?:-workstation|-server)?", re.IGNORECASE)
token_re = re.compile(r"[^\s\"'`<>()\[\]{},;]+")
cartouche_re = re.compile(r"^#(?:\s[-=]{10,}|\s(?:File|Updated at|Creator|Purpose|Note|Tool)\b)")
text_limit = 160

def shorten(text):
    flat = " ".join(text.strip().split())
    if len(flat) <= text_limit:
        return flat
    return flat[: text_limit - 3] + "..."

def rewrite(value):
    return value

def clean_token(raw):
    return raw.strip(".,:;)")

def reference_kind(value):
    lower = value.casefold()
    if "://" in lower or lower.startswith("http"):
        return "url"
    if "/" in value:
        return "path"
    if re.fullmatch(r"[ws]-[a-z0-9-]+\.(?:service|timer|path)", lower):
        return "unit"
    if lower in {"liltress", "liltress-workstation", "liltress-server", "high-fortress.com"}:
        return "slug"
    return "filename"

def comment_kind(rel, line):
    stripped = line.lstrip()
    if cartouche_re.match(stripped):
        return "cartouche"
    name = rel.rsplit("/", 1)[-1]
    if name == "README.md" or (("/docs/" in f"/{rel}" or "/doc/" in f"/{rel}") and rel.endswith(".md")):
        return "readme"
    if stripped.startswith("#") and not stripped.startswith("#!"):
        return "comment"
    if rel.endswith(".html"):
        return "display"
    if rel.endswith(".md"):
        return "comment"
    if re.search(r"\bhf_log_(?:info|success|warn|error|debug|title)\b", line):
        return "display"
    if re.match(r"^\s*(echo|printf)\b", line):
        return "display"
    return ""

def first_mark(line):
    marks = []
    for cre in (var_re, fn_re, slug_re):
        found = cre.search(line)
        if found:
            marks.append((found.start(), found.group(0)))
    if not marks:
        return ""
    marks.sort(key=lambda item: item[0])
    return marks[0][1]

variables = {}
functions = {}
comments = []
references = {}

def add_name(table, name, prefix_map):
    prefix = name.split("_", 1)[0]
    if prefix not in prefix_map:
        prefix = "n"
    row = table.get(name)
    if row is None:
        if prefix == "n":
            rest = name
            target = name
            verb = name.split("_", 1)[0]
        else:
            rest = name[len(prefix) + 1 :]
            target = prefix_map[prefix] + rest
            verb = rest.split("_", 1)[0]
        row = {
            "name": name,
            "scope": scope_of[prefix],
            "prefix": prefix,
            "target": target,
            "count": 0,
            "files": set(),
        }
        if prefix in prefix_fn and prefix.islower():
            row["verb"] = verb
        table[name] = row
    return row

defined = set()
for base in roots:
    start = root / base
    if not start.is_dir():
        continue
    for dirpath, dirnames, filenames in os.walk(start):
        dirnames[:] = sorted(
            name for name in dirnames
            if name not in skip_dirs and not (Path(dirpath) / name).is_symlink()
        )
        for filename in filenames:
            if not filename.endswith(".sh"):
                continue
            path = Path(dirpath) / filename
            if path.is_symlink():
                continue
            rel = path.relative_to(root).as_posix()
            if "/log/" in f"/{rel}" or "/log/test/" in f"/{rel}":
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            for line in text.splitlines():
                match = def_re.match(line)
                if match and not match.group(1).startswith("t_"):
                    defined.add(match.group(1))
if defined:
    fn_re = re.compile(r"\b(" + "|".join(re.escape(name) for name in sorted(defined, key=len, reverse=True)) + r"|t_[a-z][a-z0-9]*(?:_[a-z0-9]+)*)\b")

for base in roots:
    start = root / base
    if not start.is_dir():
        continue
    for dirpath, dirnames, filenames in os.walk(start):
        dirnames[:] = sorted(
            name for name in dirnames
            if name not in skip_dirs and not (Path(dirpath) / name).is_symlink()
        )
        current = Path(dirpath)
        if "test" in current.parts and "output" in current.parts:
            dirnames[:] = []
            continue
        for filename in sorted(filenames):
            path = current / filename
            if path.is_symlink():
                continue
            rel = path.relative_to(root).as_posix()
            if rel in skip_files or "/logs/" in f"/{rel}" or "/log/" in f"/{rel}" or "/log/test/" in f"/{rel}":
                continue
            try:
                data = path.read_bytes()
            except OSError:
                continue
            if b"\0" in data:
                continue
            text = data.decode("utf-8", errors="ignore")
            for match in var_re.finditer(text):
                row = add_name(variables, match.group(1), prefix_var)
                row["count"] += 1
                row["files"].add(rel)
            for match in fn_re.finditer(text):
                row = add_name(functions, match.group(1), prefix_fn)
                row["count"] += 1
                row["files"].add(rel)
            for number, line in enumerate(text.splitlines(), start=1):
                mark = first_mark(line)
                kind = comment_kind(rel, line) if mark else ""
                if mark and kind:
                    comments.append((rel, number, kind, mark, shorten(line)))
                for raw in token_re.findall(line):
                    token = clean_token(raw)
                    lower = token.casefold()
                    if "liltress" not in lower and "high-fortress.com" not in lower and not re.match(r"[ws]-", lower):
                        continue
                    if not token:
                        continue
                    slot = references.get(token)
                    if slot is None:
                        slot = {
                            "kind": reference_kind(token),
                            "value": token,
                            "target": rewrite(token),
                            "count": 0,
                            "files": set(),
                        }
                        references[token] = slot
                    slot["count"] += 1
                    slot["files"].add(rel)

def files_of(row):
    return ";".join(sorted(row["files"]))

def write_csv(name, header, rows):
    dest = root / name
    with dest.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)

var_rows = [
    [row["name"], row["scope"], row["prefix"], row["target"], row["count"], files_of(row)]
    for row in sorted(variables.values(), key=lambda item: item["name"])
]
fn_rows = [
    [row["name"], row["scope"], row["prefix"], row["verb"], row["target"], row["count"], files_of(row)]
    for row in sorted(functions.values(), key=lambda item: item["name"])
]
comment_rows = [
    [path, line, kind, match, text]
    for path, line, kind, match, text in sorted(comments, key=lambda item: (item[0], item[1], item[3]))
]
ref_rows = [
    [row["kind"], row["value"], row["target"], row["count"], files_of(row)]
    for row in sorted(references.values(), key=lambda item: (item["kind"], item["value"]))
]
write_csv("name-variables.csv", ["name", "scope", "prefix", "target", "count", "files"], var_rows)
write_csv("name-functions.csv", ["name", "scope", "prefix", "verb", "target", "count", "files"], fn_rows)
write_csv("name-comments.csv", ["path", "line", "kind", "match", "text"], comment_rows)
write_csv("name-references.csv", ["kind", "value", "target", "count", "files"], ref_rows)
