#!/usr/bin/env python3
# =============================================================================
# File       : python/name-list.py
# Updated at : 2026-11-26
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Record the four name inventories under census/names.
# Note       : Shell files under a log directory are left out of the inventory.
# -----------------------------------------------------------------------------


import ast
import csv
import importlib.util
import os
import re
from pathlib import Path

root = Path(os.environ["NAMES_ROOT"])
roots = ("share", "scripts", "agents", "workstation", "server")
skip_directories = {".git", "logs", "node_modules", ".venv", "next_step", "__pycache__"}
# The generators are not product code. The schema JSON stays in the count.
skip_files = {
    "scripts/list-names.sh",
    "scripts/list-config.sh",
    "census/names/name-variables.csv",
    "census/names/name-functions.csv",
    "census/names/name-comments.csv",
    "census/names/name-references.csv",
    "scripts/quality-baseline.txt",
}
prefix_var = {"W": "W_", "S": "S_", "T": "T_", "n": ""}
prefix_fn = {"g": "g_", "w": "w_", "s": "s_", "t": "t_", "n": ""}
scope_of = {
    "W": "workstation",
    "S": "server",
    "T": "test",
    "g": "shared",
    "w": "workstation",
    "s": "server",
    "t": "test",
    "n": "shared",
}


def load_shared_head():
    return """
ACCOUNT_SNAPSHOT ACCOUNT_USER AIDE_REFRESH ANTIBOT_HMAC_SECRET API_BASE_URL
ARTIFACTS BANNER_MESSAGE BASE BOOT_ACCURACY BOOT_ON_BOOT_SEC
BRANCH CHKROOTKIT_IGNORE CLAMAV_EVENT_FILE CLAMAV_EVENT_KIND
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
INSTALL_DIRECTORY INSTALL_LOG_DIR INSTALL_LOG_FILE INSTALL_ROOT JWT_URL
KEYCLOAK_CLIENT KEYCLOAK_PUBLIC_BASE_URL KEYCLOAK_REALM LANGUAGE LIMIT_WRAP
LIVEKIT_URL LOGS_COLLECTED LOG_SYS LYNIS_MIN_SCORE
MAIL_ABOUT MAIL_ACTIONS MAIL_ALERTS MAIL_ATTACH MAIL_BLOCK_ACTIONS MAIL_BLOCK_FILES MAIL_BLOCK_IGNORE MAIL_BLOCK_SERVICES MAIL_FILES MAIL_FOOTER MAIL_IGNORE MAIL_REDACT MAIL_REQUIRE_FLAG MAIL_SERVICES MAIL_SUBTITLE MAIL_TEMPLATE
""".split()


def load_shared_tail():
    return """
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
SSH_MAX_AUTH_TRIES SSH_PORT SSH_SERVICE_NAME
""".split()


def load_shared_end():
    return """
SWAP_FILE SWAP_MAPPER_NAME
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
VPN_ACTIVE VPN_BOOT_PROFILE VPN_DEFAULT VPN_FAILOVER_TIMEOUT VPN_FAILOVER_TRIES
VPN_FW_PRIORITY VPN_HANDSHAKE_TIMEOUT VPN_IFACE_OVPN VPN_IFACE_WG VPN_MODE
VPN_ON_BOOT VPN_RULE_PRIO_BYPASS_FROM VPN_RULE_PRIO_BYPASS_TO
VPN_RULE_PRIO_ENDPOINT VPN_RULE_PRIO_LAN VPN_RULE_PRIO_SSH VPN_RULE_PRIO_TUNNEL
VPN_SSH_MARK VPN_TABLE_ID VPN_TABLE_NAME VPN_TUN_MTU WATCHDOG_CPU_LIMIT
WATCHDOG_HOLD_MAIL WATCHDOG_LIMIT_IO_NICE
WATCHDOG_LIMIT_NICE WATCHDOG_MAIL WEB_IMAGE_BACKEND WEB_IMAGE_FRONTEND
WEB_IMAGE_TAG WEB_REGISTRY WEB_UPDATE_SCRIPT WIREGUARD_ADMIN_PASSWORD
WIREGUARD_ALLOWED_IP WIREGUARD_DEFAULT_ADDRESS WIREGUARD_DEFAULT_DNS
WIREGUARD_HOST WIREGUARD_UI_URL
""".split()


shared_vars = load_shared_head() + load_shared_tail() + load_shared_end()
var_re = re.compile(
    r"\b((?:W|S|T)_[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*|" + "|".join(sorted(shared_vars, key=len, reverse=True)) + r")\b"
)
fn_re = re.compile(r"\b(t_[a-z][a-z0-9]*(?:_[a-z0-9]+)*)\b")
def_re = re.compile(r"^[ \t]*([a-z][a-z0-9_]*)\s*\(\s*\)")
slug_re = re.compile(r"high-fortress\.com|liltress(?:-workstation|-server)?", re.IGNORECASE)
token_re = re.compile(r"[^\s\"'`<>()\[\]{},;]+")
cartouche_re = re.compile(r"^#(?:\s[-=]{10,}|\s(?:File|Updated at|Creator|Purpose|Note|Tool)\b)")
text_limit = 160


def shorten(text):
    flat = " ".join(text.strip().split())
    if len(flat) <= text_limit:
        return flat
    return flat[: text_limit - 3] + "..."


# A semantic signature is the normalized intent plus the callees.
# Same text on two names is the proximity signal used before a merge.
branch_re = re.compile(r"(^|[^A-Za-z0-9_])(if|elif|while|until|for|case)([^A-Za-z0-9_]|$)")
word_re = re.compile(r"\b[a-z_][a-z0-9_]*\b")
metrics = {}
python_mod = None


def shell_skip_words():
    return {
        "if",
        "elif",
        "while",
        "until",
        "for",
        "case",
        "in",
        "fi",
        "do",
        "done",
        "esac",
        "then",
        "else",
        "time",
        "coproc",
        "select",
        "function",
        "local",
        "return",
        "export",
        "declare",
        "typeset",
        "readonly",
        "eval",
        "exec",
    }


def maintainability(span, complexity):
    value = 100 - 50 * (span / 40) - 50 * (complexity / 8)
    if value <= 0:
        return "0"
    if value >= 100:
        return "100"
    return str(int(value + 0.5))


def remember_metric(name, language, span, complexity, signature):
    metrics.setdefault(name, []).append(
        {
            "language": language,
            "complexity": complexity,
            "maintainability": maintainability(span, complexity),
            "signature": signature,
        }
    )


def signature_text(intent, calls, verb):
    names = ",".join(sorted(set(calls)))
    if intent and names:
        text = intent + " :: " + names
    elif intent:
        text = intent
    elif names:
        text = names
    else:
        text = verb
    return shorten(text)


def metric_columns(name):
    rows = metrics.get(name, [])
    if not rows:
        return ["", "", "", ""]
    languages = ";".join(sorted({row["language"] for row in rows}))
    complexity = max(row["complexity"] for row in rows)
    score = min(int(row["maintainability"]) for row in rows)
    signatures = []
    for row in rows:
        if row["signature"] not in signatures:
            signatures.append(row["signature"])
    return [languages, str(complexity), str(score), shorten(" || ".join(signatures))]


def python_quality():
    global python_mod
    if python_mod is not None:
        return python_mod
    path = root / "scripts" / "quality-python.py"
    spec = importlib.util.spec_from_file_location("quality_python", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    python_mod = module
    return module


def python_calls(node):
    names = []
    for child in ast.walk(node):
        if not isinstance(child, ast.Call):
            continue
        if isinstance(child.func, ast.Name) and child.func.id != node.name and child.func.id in defined:
            names.append(child.func.id)
    return names


def python_signature(node):
    intent = ast.get_docstring(node) or ""
    return signature_text(intent, python_calls(node), node.name.split("_", 1)[0])


def shell_comment(lines, index):
    picked = []
    cursor = index - 1
    while cursor >= 0 and lines[cursor].strip() == "":
        cursor -= 1
    while cursor >= 0 and lines[cursor].lstrip().startswith("#"):
        text = lines[cursor].lstrip()[1:].strip()
        if text.startswith("!") or text.startswith(("====", "----", "File", "Updated", "Creator", "Purpose", "Note")):
            break
        if text:
            picked.append(text)
        cursor -= 1
    picked.reverse()
    return " ".join(picked)


def take_heredoc(line, index, state):
    cursor = index + 2
    tabs = False
    if cursor < len(line) and line[cursor] == "-":
        tabs = True
        cursor += 1
    word, cursor = heredoc_word(line, cursor)
    if word:
        state["heredoc"] = word
        state["tabs"] = tabs
    return cursor


def heredoc_word(line, cursor):
    if cursor < len(line) and line[cursor] in "'\"":
        return quoted_heredoc_word(line, cursor)
    return bare_heredoc_word(line, cursor)


def quoted_heredoc_word(line, cursor):
    quote = line[cursor]
    cursor += 1
    word = ""
    while cursor < len(line) and line[cursor] != quote:
        word += line[cursor]
        cursor += 1
    return word, cursor + 1


def bare_heredoc_word(line, cursor):
    word = ""
    while cursor < len(line) and (line[cursor].isalnum() or line[cursor] == "_"):
        word += line[cursor]
        cursor += 1
    return word, cursor


def shell_plain(line, state):
    if state["heredoc"]:
        token = line.lstrip("\t") if state["tabs"] else line
        if token.strip() == state["heredoc"]:
            state["heredoc"] = ""
        return "", True
    return plain_shell_code(line, state), False


def plain_shell_code(line, state):
    out = []
    index = 0
    while index < len(line):
        index, piece, stop = plain_shell_step(line, index, state)
        if stop:
            break
        if piece:
            out.append(piece)
    return "".join(out)


def plain_shell_step(line, index, state):
    char = line[index]
    nxt = line[index + 1] if index + 1 < len(line) else ""
    if state["single"] or state["double"]:
        return quoted_shell_step(line, index, state)
    if char == "#":
        return index, "", True
    if char in "'\"":
        state["single"] = char == "'"
        state["double"] = char == '"'
        return index + 1, "", False
    return code_shell_step(line, index, char, nxt, state)


def quoted_shell_step(line, index, state):
    if state["single"]:
        state["single"] = line[index] != "'"
        return index + 1, "", False
    return skip_double(line, index, state), "", False


def code_shell_step(line, index, char, nxt, state):
    if char == "$" and nxt == "#":
        return index + 2, " ", False
    if char == "$" and nxt == "{":
        return skip_braces(line, index + 2), " ", False
    if char == "<" and nxt == "<":
        return redirect_step(line, index, state)
    return index + 1, char, False


def redirect_step(line, index, state):
    third = line[index + 2] if index + 2 < len(line) else ""
    if third == "<":
        return index + 3, " ", False
    return take_heredoc(line, index, state), " ", False


def skip_double(line, index, state):
    char = line[index]
    if char == "\\" and index + 1 < len(line):
        return index + 2
    if char == '"':
        state["double"] = False
    return index + 1


def skip_braces(line, index):
    nest = 1
    while index < len(line) and nest:
        if line[index] == "{":
            nest += 1
        elif line[index] == "}":
            nest -= 1
        index += 1
    return index


def shell_calls(plain, name):
    found = []
    skipped = shell_skip_words()
    for call in word_re.findall(plain):
        if call == name or call in skipped or call not in defined:
            continue
        found.append(call)
    return found


def close_shell_frame(stack, index):
    frame = stack.pop()
    span = index - frame["start"] + 1
    intent = frame["intent"]
    signature = signature_text(intent, frame["calls"], frame["name"].split("_", 1)[0])
    remember_metric(frame["name"], "bash", span, frame["score"], signature)


def language_words():
    return {
        "if",
        "elif",
        "else",
        "fi",
        "then",
        "for",
        "while",
        "until",
        "case",
        "esac",
        "do",
        "done",
        "in",
        "function",
        "index",
        "match",
        "split",
        "sub",
        "gsub",
    }


def shell_header(lines, index):
    found = def_re.match(lines[index])
    if not found or found.group(1) in language_words():
        return ""
    if "{" not in lines[index].split("#", 1)[0] and not next_brace(lines, index):
        return ""
    return found.group(1)


def next_brace(lines, index):
    cursor = index + 1
    while cursor < len(lines) and lines[cursor].strip() == "":
        cursor += 1
    return cursor < len(lines) and lines[cursor].strip() == "{"


def open_shell_frame(stack, line, index, lines, depth, plain):
    name = shell_header(lines, index)
    if not name or f"{name}()" not in plain:
        return
    defined.add(name)
    stack.append(
        {
            "name": name,
            "start": index,
            "base": depth,
            "opened": False,
            "score": 1,
            "calls": [],
            "intent": shell_comment(lines, index),
        }
    )


def note_shell_frame(frame, plain):
    frame["score"] += len(branch_re.findall(plain))
    frame["score"] += plain.count("&&")
    frame["score"] += plain.count("||")
    frame["calls"].extend(shell_calls(plain, frame["name"]))


def move_shell_depth(frame, plain, depth):
    for char in plain:
        if char == "{":
            depth += 1
            frame["opened"] = True
        elif char == "}" and depth > 0:
            depth -= 1
    return depth


def measure_shell(path):
    try:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    except OSError:
        return
    measure_shell_lines(lines)


def measure_shell_lines(lines):
    state = {"single": False, "double": False, "heredoc": "", "tabs": False}
    depth = 0
    stack = []
    for index, line in enumerate(lines):
        plain, interior = shell_plain(line, state)
        if interior:
            continue
        open_shell_frame(stack, line, index, lines, depth, plain)
        for frame in stack:
            note_shell_frame(frame, plain)
        if not stack:
            continue
        depth = move_shell_depth(stack[-1], plain, depth)
        if stack[-1]["opened"] and depth <= stack[-1]["base"]:
            close_shell_frame(stack, index)
    while stack:
        close_shell_frame(stack, max(len(lines) - 1, 0))


def measure_hidden(start, missing):
    for dirpath, dirnames, filenames in os.walk(start):
        dirnames[:] = child_directories(dirpath, dirnames)
        for filename in sorted(filenames):
            if not filename.endswith(".sh"):
                continue
            path = Path(dirpath) / filename
            if path.is_symlink():
                continue
            rel = path.relative_to(root).as_posix()
            if log_path(rel) or skip_path(rel):
                continue
            read_hidden(path, missing)


def read_hidden(path, missing):
    try:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    except OSError:
        return
    for index, _line in enumerate(lines):
        name = shell_header(lines, index)
        if name in missing:
            measure_shell_lines(lines[index:])


def measure_python(path):
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"))
    except OSError, SyntaxError:
        return
    mod = python_quality()
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        if not re.fullmatch(r"[a-z][a-z0-9_]*", node.name):
            continue
        span = mod.node_span(node)
        score = mod.function_score(node)
        remember_metric(node.name, "python", span, score, python_signature(node))


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


def readme_line(rel):
    name = rel.rsplit("/", 1)[-1]
    if name == "README.md":
        return True
    if not rel.endswith(".md"):
        return False
    marked = f"/{rel}"
    if "/docs/" in marked:
        return True
    return "/doc/" in marked


def spoken_kind(line):
    if re.search(r"\bhf_log_(?:info|success|warn|error|debug|title)\b", line):
        return "display"
    if re.match(r"^\s*(echo|printf)\b", line):
        return "display"
    return ""


def comment_kind(rel, line):
    stripped = line.lstrip()
    if cartouche_re.match(stripped):
        return "cartouche"
    if readme_line(rel):
        return "readme"
    if stripped.startswith("#") and not stripped.startswith("#!"):
        return "comment"
    if rel.endswith(".html"):
        return "display"
    if rel.endswith(".md"):
        return "comment"
    return spoken_kind(line)


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


def verb_names():
    text = (
        "add apply arm ask begin check clear collect copy deliver emit encode "
        "ensure fail finish get init install invoke list load locate lock log "
        "offer pass persist prompt publish quote read record refresh remove "
        "render report require reset restart run scan section send set shorten "
        "show signal skip source strip take validate wait warn write"
    )
    return set(text.split())


def verb_token(name):
    parts = name.split("_")
    # A two-digit token before the final verb marks a split body or a cyclomatic piece.
    if len(parts) < 4 or parts[-1] not in verb_names():
        return parts[0]
    if parts[-2].isdigit() and len(parts[-2]) == 2:
        return parts[-1]
    return parts[0]


def add_name(table, name, prefix_map):
    prefix = name.split("_", 1)[0]
    if prefix not in prefix_map:
        prefix = "n"
    row = table.get(name)
    if row is None:
        if prefix == "n":
            rest = name
            target = name
            verb = verb_token(name)
        else:
            rest = name[len(prefix) + 1 :]
            target = prefix_map[prefix] + rest
            verb = verb_token(rest)
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


def child_directories(dirpath, dirnames):
    kept = []
    for name in dirnames:
        if name in skip_directories:
            continue
        if (Path(dirpath) / name).is_symlink():
            continue
        kept.append(name)
    return sorted(kept)


def log_path(rel):
    marked = f"/{rel}"
    if "/log/" in marked:
        return True
    return "/log/test/" in marked


def shell_defs(path):
    try:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    except OSError:
        return
    for index, _line in enumerate(lines):
        name = shell_header(lines, index)
        if name:
            defined.add(name)


def python_defs(path):
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"))
    except OSError, SyntaxError:
        return
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        if re.fullmatch(r"[a-z][a-z0-9_]*", node.name):
            defined.add(node.name)


def walk_shell(start):
    for dirpath, dirnames, filenames in os.walk(start):
        dirnames[:] = child_directories(dirpath, dirnames)
        for filename in filenames:
            if not filename.endswith(".sh"):
                continue
            path = Path(dirpath) / filename
            if path.is_symlink():
                continue
            rel = path.relative_to(root).as_posix()
            if log_path(rel):
                continue
            shell_defs(path)


def walk_python(start):
    for dirpath, dirnames, filenames in os.walk(start):
        dirnames[:] = child_directories(dirpath, dirnames)
        for filename in sorted(filenames):
            if not filename.endswith(".py"):
                continue
            path = Path(dirpath) / filename
            if path.is_symlink():
                continue
            rel = path.relative_to(root).as_posix()
            if log_path(rel) or skip_path(rel):
                continue
            python_defs(path)


def collect_defined():
    for base in roots:
        start = root / base
        if not start.is_dir():
            continue
        walk_shell(start)
        walk_python(start)


def measure_tree(start):
    for dirpath, dirnames, filenames in os.walk(start):
        dirnames[:] = child_directories(dirpath, dirnames)
        for filename in sorted(filenames):
            path = Path(dirpath) / filename
            if path.is_symlink():
                continue
            rel = path.relative_to(root).as_posix()
            if log_path(rel) or skip_path(rel):
                continue
            if filename.endswith(".sh"):
                measure_shell(path)
            elif filename.endswith(".py"):
                measure_python(path)


def collect_metrics():
    for base in roots:
        start = root / base
        if not start.is_dir():
            continue
        measure_tree(start)
        missing = {name for name in defined if name not in metrics}
        measure_hidden(start, missing)


def compile_functions():
    global fn_re
    if not defined:
        return
    names = sorted(defined, key=len, reverse=True)
    body = "|".join(re.escape(name) for name in names)
    pattern = r"\b(" + body + r")\b"
    fn_re = re.compile(pattern)


def output_pruned(current):
    if "test" not in current.parts:
        return False
    return "output" in current.parts


def skip_path(rel):
    if rel in skip_files:
        return True
    marked = f"/{rel}"
    if "/logs/" in marked:
        return True
    if "/log/" in marked:
        return True
    return "/log/test/" in marked


def note_vars(text, rel):
    for found in var_re.finditer(text):
        row = add_name(variables, found.group(1), prefix_var)
        row["count"] += 1
        row["files"].add(rel)


def note_fns(text, rel):
    for found in fn_re.finditer(text):
        row = add_name(functions, found.group(1), prefix_fn)
        row["count"] += 1
        row["files"].add(rel)


def note_comment(rel, number, line):
    found = first_mark(line)
    if not found:
        return
    kind = comment_kind(rel, line)
    if not kind:
        return
    comments.append((rel, number, kind, found, shorten(line)))


def keep_ref(token):
    if not token:
        return False
    lower = token.casefold()
    if "liltress" in lower:
        return True
    if "high-fortress.com" in lower:
        return True
    return bool(re.match(r"[ws]-", lower))


def note_refs(line, rel):
    for raw in token_re.findall(line):
        token = clean_token(raw)
        if not keep_ref(token):
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


def scan_text(rel, text):
    note_vars(text, rel)
    note_fns(text, rel)
    for number, line in enumerate(text.splitlines(), start=1):
        note_comment(rel, number, line)
        note_refs(line, rel)


def read_scan(path, rel):
    try:
        data = path.read_bytes()
    except OSError:
        return
    if b"\0" in data:
        return
    scan_text(rel, data.decode("utf-8", errors="ignore"))


def scan_directory(start):
    for dirpath, dirnames, filenames in os.walk(start):
        dirnames[:] = child_directories(dirpath, dirnames)
        current = Path(dirpath)
        if output_pruned(current):
            dirnames[:] = []
            continue
        for filename in sorted(filenames):
            path = current / filename
            if path.is_symlink():
                continue
            rel = path.relative_to(root).as_posix()
            if skip_path(rel):
                continue
            read_scan(path, rel)


def scan_tree():
    for base in roots:
        start = root / base
        if not start.is_dir():
            continue
        scan_directory(start)


def files_of(row):
    return ";".join(sorted(row["files"]))


def write_csv(name, header, rows):
    # The repository root stays free of descriptive tables.
    dest = root / "census" / "names" / name
    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)


def function_header():
    return [
        "name",
        "scope",
        "prefix",
        "verb",
        "target",
        "count",
        "files",
        "language",
        "complexity",
        "maintainability",
        "semantic_signature",
    ]


def function_row(row):
    language, complexity, score, signature = metric_columns(row["name"])
    return [
        row["name"],
        row["scope"],
        row["prefix"],
        row["verb"],
        row["target"],
        row["count"],
        files_of(row),
        language,
        complexity,
        score,
        signature,
    ]


def emit_names():
    var_rows = [
        [row["name"], row["scope"], row["prefix"], row["target"], row["count"], files_of(row)]
        for row in sorted(variables.values(), key=lambda item: item["name"])
    ]
    fn_rows = [function_row(row) for row in sorted(functions.values(), key=lambda item: item["name"])]
    comment_rows = [
        [path, line, kind, found, text]
        for path, line, kind, found, text in sorted(comments, key=lambda item: (item[0], item[1], item[3]))
    ]
    ref_rows = [
        [row["kind"], row["value"], row["target"], row["count"], files_of(row)]
        for row in sorted(references.values(), key=lambda item: (item["kind"], item["value"]))
    ]
    write_csv("name-variables.csv", ["name", "scope", "prefix", "target", "count", "files"], var_rows)
    write_csv("name-functions.csv", function_header(), fn_rows)
    write_csv("name-comments.csv", ["path", "line", "kind", "match", "text"], comment_rows)
    write_csv("name-references.csv", ["kind", "value", "target", "count", "files"], ref_rows)


def run_name_list():
    global variables, functions, comments, references, defined
    metrics.clear()
    variables = {}
    functions = {}
    comments = []
    references = {}
    defined = set()
    collect_defined()
    compile_functions()
    scan_tree()
    collect_metrics()
    emit_names()


if __name__ == "__main__":
    run_name_list()
