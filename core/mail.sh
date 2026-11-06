#!/usr/bin/env bash
# =============================================================================
# File       : core/mail.sh
# Updated at : 2026-11-06
# Creator    : palarchsys
# =============================================================================

check_mail_template_name() {
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.html$ ]]
}

log_mail_fatal() {
    if declare -F log_error >/dev/null 2>&1; then
        log_error "${INSTALL_WATCHER:-BASH}" "install.mail.error" "$*"
    fi
    printf '%s\n' "$*" >&2
    exit 1
}

install_mail_templates() {
    local dest="$1"
    local src="${INSTALL_DIRECTORY:?}/template"
    local chosen="${MAIL_TEMPLATE:-mail.html}"
    local f base n=0
    local nullglob_was=0
    [[ -d "${dest}" ]] || log_mail_fatal "$(get_text mail.directory-of-installation-of-the-mod-les-absent "${dest}")"
    [[ -d "${src}" ]] || log_mail_fatal "$(get_text mail.directory-template-absent "${src}")"
    check_mail_template_name "${chosen}" || log_mail_fatal "$(get_text mail.g-mail-template-invalid-example-mail-html "${chosen}")"

    if shopt -q nullglob; then
        nullglob_was=1
    fi
    shopt -s nullglob
    for f in "${src}/"*.html; do
        base="$(basename -- "${f}")"
        check_mail_template_name "${base}" || log_mail_fatal "$(get_text mail.name-of-template-denied-example-mail-html "${base}")"
        cp -f -- "${f}" "${dest}/${base}"
        chmod 644 "${dest}/${base}"
        n=$((n + 1))
    done
    if [[ "${nullglob_was}" -eq 0 ]]; then
        shopt -u nullglob
    fi
    [[ "${n}" -ge 1 ]] || log_mail_fatal "$(get_text mail.no-file-html-in "${src}")"
    [[ -f "${dest}/${chosen}" ]] || log_mail_fatal "$(get_text mail.template-absent-of "${chosen}" "${src}")"
}

get_mail_name() {
    local here="${1:-}"
    local conf line
    local -a confs=()
    [[ -n "${INSTALL_DIRECTORY:-}" ]] && confs+=("${INSTALL_DIRECTORY}/config/global.conf")
    [[ -n "${CONFIG_BASE_DIRECTORY:-}" ]] && confs+=("${CONFIG_BASE_DIRECTORY}/src/config/global.conf")
    if [[ -n "${here}" ]]; then
        confs+=(
            "${here}/../../src/config/global.conf"
            "${here}/../../../config/global.conf"
            "${here}/../config/global.conf"
        )
    fi
    for conf in "${confs[@]}"; do
        [[ -f "${conf}" ]] || continue
        line="$(awk -F= '/^MAIL_TEMPLATE=/{gsub(/"/,"",$2); gsub(/[[:space:]]/,"",$2); print $2; exit}' "${conf}")"
        if [[ -n "${line}" ]]; then
            printf '%s\n' "${line}"
            return 0
        fi
    done
    if [[ -n "${MAIL_TEMPLATE:-}" ]]; then
        printf '%s\n' "${MAIL_TEMPLATE}"
        return 0
    fi
    printf '%s\n' "mail.html"
}

locate_mail_template() {
    local here="${1:-}"
    local name dir
    local -a dirs=()
    name="$(get_mail_name "${here}")"
    check_mail_template_name "${name}" || return 1
    [[ -n "${INSTALL_DIRECTORY:-}" ]] && dirs+=("${INSTALL_DIRECTORY}/template")
    [[ -n "${CONFIG_BASE_DIRECTORY:-}" ]] && dirs+=("${CONFIG_BASE_DIRECTORY}/src/template")
    if [[ -n "${here}" ]]; then
        dirs+=(
            "${here}/../../src/template"
            "${here}/../../../template"
            "${here}/../template"
            "${here}"
        )
    fi
    for dir in "${dirs[@]}"; do
        if [[ -f "${dir}/${name}" ]]; then
            printf '%s\n' "${dir}/${name}"
            return 0
        fi
    done
    return 1
}

render_mail() {
    local template="$1"
    local mail_here="" mail_candidate=""
    local mail_module="" mail_redacted="" mail_redacted_key="" mail_unreadable="" mail_no_pre=""
    [[ -f "${template}" ]] || return 1
    if ! declare -F get_text >/dev/null 2>&1; then
        mail_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
        for mail_candidate in \
            "${mail_here}/log.sh" \
            "${PRODUCT_ROOT:-}/core/log.sh" \
            "${INSTALL_DIRECTORY:-}/core/log.sh" \
            "${INSTALL_DIRECTORY:-}/src/core/log.sh"
        do
            if [[ -n "${mail_candidate}" && -f "${mail_candidate}" ]]; then
                # shellcheck disable=SC1090
                source "${mail_candidate}"
                break
            fi
        done
    fi
    if declare -F get_text >/dev/null 2>&1; then
        load_text "${LANGUAGE:-en}"
        mail_module="$(get_text mail.module)"
        mail_read="$(get_text mail.read)"
        mail_seen="$(get_text mail.seen)"
        mail_check="$(get_text mail.check)"
        mail_next="$(get_text mail.next)"
        mail_redacted="$(get_text mail.redacted)"
        mail_redacted_key="$(get_text mail.redacted-key)"
        mail_unreadable="$(get_text mail.template-unreadable)"
        mail_no_pre="$(get_text mail.template-no-pre)"
    else
        mail_module="Module:"
        mail_read="The journal is at the top. Each finding then shows the command, a normal example, and a worrying example."
        mail_seen="Journal"
        mail_check="How to read the finding"
        mail_next="What to do next"
        mail_redacted="[redacted]"
        mail_redacted_key="[private key redacted]"
        mail_unreadable="unreadable template: {1}"
        mail_no_pre="template without a pre tag"
    fi
    MAIL_TEMPLATE_FILE="${template}" \
    MAIL_REDACT="${MAIL_REDACT:-0}" \
    MAIL_LANG="${LANGUAGE:-en}" \
    MAIL_MODULE="${mail_module}" \
    MAIL_READ="${mail_read}" \
    MAIL_SEEN="${mail_seen}" \
    MAIL_CHECK="${mail_check}" \
    MAIL_NEXT="${mail_next}" \
    TEXT_REDACTED="${mail_redacted}" \
    TEXT_REDACTED_KEY="${mail_redacted_key}" \
    TEXT_TEMPLATE_UNREADABLE="${mail_unreadable}" \
    TEXT_TEMPLATE_NO_PRE="${mail_no_pre}" \
    python3 - << 'PY'
import html
import os
import re
import sys
from pathlib import Path

redacted = os.environ.get("TEXT_REDACTED") or "[redacted]"
redacted_key = os.environ.get("TEXT_REDACTED_KEY") or "[private key redacted]"
token = re.escape(redacted)

def redact(text):
    text = re.sub(
        r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----",
        lambda _match: redacted_key,
        text,
        flags=re.S,
    )
    text = re.sub(
        rf"(?i)\bbearer\s+(?!{token})\S+",
        lambda _match: "Bearer " + redacted,
        text,
    )
    text = re.sub(
        rf"(?i)\b(password|passwd|token|jeton|api[_-]?key|secret|authorization|private[_-]?key|clé privée|clef privée)\b(\s*[:=]\s*)(?!{token})\S+",
        lambda match: match.group(1) + match.group(2) + redacted,
        text,
    )
    return text

redact_on = os.environ.get("MAIL_REDACT", "0") == "1"
content = os.environ.get("CONTENT", "")
note = os.environ.get("NOTE", "")
advice = os.environ.get("ADVICE", "")
if redact_on:
    content = redact(content)
    note = redact(note)
    advice = redact(advice)
note = note.strip()
advice = advice.strip()
note_cmd = os.environ.get("NOTE_CMD", "").strip()

def advice_parts(text):
    blocks = []
    title = None
    lines = []
    marked = False

    def flush():
        nonlocal title, lines
        body = "\n".join(lines).strip()
        if title is not None or body:
            blocks.append((title, body))
        title = None
        lines = []

    for line in text.splitlines():
        if line.startswith("@@H@@"):
            marked = True
            flush()
            title = line[5:].strip()
            lines = []
        elif line.strip() == "@@BLOCK@@":
            marked = True
            flush()
        else:
            lines.append(line)
    flush()
    return marked, blocks

def advice_plain(text):
    marked, blocks = advice_parts(text)
    if not marked:
        return text
    out = []
    for title, body in blocks:
        if title:
            if out and out[-1] != "":
                out.append("")
            out.append(title)
        if body:
            out.append(body)
    return "\n".join(out).strip()

def mail_heading(text):
    return (
        '<div style="margin:0 0 8px;font-size:13px;line-height:1.4;font-weight:bold;'
        'color:#93c5fd;font-family:Arial,Helvetica,sans-serif;">'
        + html.escape(text, quote=False)
        + "</div>"
    )

def mail_pre(text):
    return (
        '<pre style="margin:0 0 16px;width:100%;max-width:100%;box-sizing:border-box;'
        'display:block;background-color:#020617;border:1px solid #334155;border-radius:8px;'
        'padding:12px;color:#e2e8f0;font-family:Consolas,Courier New,monospace;font-size:13px;'
        'line-height:1.45;white-space:pre-wrap;word-wrap:break-word;word-break:break-word;overflow-wrap:break-word;overflow-x:auto;">'
        + html.escape(text, quote=False)
        + "</pre>"
    )

def advice_html(text):
    marked, blocks = advice_parts(text)
    if not marked:
        return mail_pre(text)
    chunks = []
    for title, body in blocks:
        if title:
            chunks.append(mail_heading(title))
        if body:
            chunks.append(mail_pre(body))
    return "".join(chunks)

plain_advice = advice_plain(advice)
html_advice = advice_html(advice) if advice else ""
path = Path(os.environ["MAIL_TEMPLATE_FILE"])
try:
    tpl = path.read_text(encoding="utf-8")
except OSError as exc:
    unread = os.environ.get("TEXT_TEMPLATE_UNREADABLE") or "unreadable template: {1}"
    print(unread.replace("{1}", str(exc)), file=sys.stderr)
    sys.exit(1)
for key in ("TITLE", "PROJECT_NAME", "HOSTNAME", "DATE", "MODULE_NAME", "MAIL_LANG", "MAIL_MODULE", "MAIL_READ", "MAIL_SEEN", "MAIL_CHECK", "MAIL_NEXT"):
    tpl = tpl.replace("${" + key + "}", html.escape(os.environ.get(key, ""), quote=False))
tpl = tpl.replace("${CONTENT}", html.escape(content, quote=False))
if advice:
    tpl = tpl.replace("${ADVICE}", html.escape(plain_advice, quote=False))
    tpl = tpl.replace("${ADVICE_HTML}", html_advice)
else:
    tpl = re.sub(r"<!--ADVICE_START-->.*?<!--ADVICE_END-->", "", tpl, count=1, flags=re.S)
if note and note_cmd:
    tpl = tpl.replace("${NOTE}", html.escape(note, quote=False))
    tpl = tpl.replace("${NOTE_CMD}", html.escape(note_cmd, quote=False))
else:
    tpl = re.sub(r"<!--NOTE_START-->.*?<!--NOTE_END-->", "", tpl, count=1, flags=re.S)
if "<pre" not in tpl:
    missing_pre = os.environ.get("TEXT_TEMPLATE_NO_PRE") or "template without a pre tag"
    print(missing_pre, file=sys.stderr)
    sys.exit(1)
sys.stdout.write(tpl)
PY
}

apply_postfix() {
    local line key value host
    host="$(hostname -f)"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        value="${value//__HOSTNAME__/${host}}"
        value="${value//__RELAYHOST__/${relayhost}}"
        value="${value//__PROJECT_NAME__/${PROJECT_NAME}}"
        value="${value//__SASL_TYPE__/${sasl_type}}"
        postconf -e "${key} = ${value}"
    done < "$(locate_config_file postfix/main.keys)"
}
