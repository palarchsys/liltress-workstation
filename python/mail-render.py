#!/usr/bin/env python3
# =============================================================================
# File       : python/mail-render.py
# Updated at : 2026-11-23
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Fill one mail template from the environment.
# Note       : Empty sections are removed, and secrets are masked only when asked.
# -----------------------------------------------------------------------------


import html
import os
import re
import sys
from pathlib import Path

import text_redact

REDACTED = os.environ.get("TEXT_REDACTED") or "[redacted]"
REDACTED_KEY = os.environ.get("TEXT_REDACTED_KEY") or "[private key redacted]"
BLOCK_PAIRS = (
    ("SEEN", "MAIL_SEEN"),
    ("BLOCK_SERVICES", "MAIL_SERVICES"),
    ("BLOCK_FILES", "MAIL_FILES"),
    ("BLOCK_ACTIONS", "MAIL_ACTIONS"),
    ("BLOCK_IGNORE", "MAIL_IGNORE"),
)
PLACE_KEYS = (
    "TITLE",
    "PROJECT_NAME",
    "HOSTNAME",
    "DATE",
    "MODULE_NAME",
    "MAIL_LANG",
    "MAIL_MODULE",
    "MAIL_READ",
    "MAIL_SEEN",
    "MAIL_CHECK",
    "MAIL_NEXT",
    "MAIL_SUBTITLE",
    "MAIL_FOOTER",
    "MAIL_BLOCK_SERVICES",
    "MAIL_BLOCK_FILES",
    "MAIL_BLOCK_ACTIONS",
    "MAIL_BLOCK_IGNORE",
    "MAIL_SERVICES",
    "MAIL_FILES",
    "MAIL_ACTIONS",
    "MAIL_IGNORE",
)


def redact(text):
    return text_redact.redact_mail(text, REDACTED, REDACTED_KEY)


def redacted_fields():
    # Secrets in the body are masked only when asked.
    content = os.environ.get("CONTENT", "")
    note = os.environ.get("NOTE", "")
    advice = os.environ.get("ADVICE", "")
    services = os.environ.get("MAIL_SERVICES", "")
    files_block = os.environ.get("MAIL_FILES", "")
    actions = os.environ.get("MAIL_ACTIONS", "")
    if os.environ.get("MAIL_REDACT", "0") == "1":
        content = redact(content)
        note = redact(note)
        advice = redact(advice)
        services = redact(services)
        files_block = redact(files_block)
        actions = redact(actions)
    os.environ["MAIL_SERVICES"] = services
    os.environ["MAIL_FILES"] = files_block
    os.environ["MAIL_ACTIONS"] = actions
    note_cmd = os.environ.get("NOTE_CMD", "").strip()
    return content, note.strip(), advice.strip(), note_cmd


def advice_parts(text):
    # A line that opens with @@H@@ is a heading. A line that is only @@BLOCK@@ closes the section.
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


def separate_heading(out):
    return bool(out) and out[-1] != ""


def advice_plain(text):
    # Two headings are separated by a blank line.
    marked, blocks = advice_parts(text)
    if not marked:
        return text
    out = []
    for title, body in blocks:
        if title:
            if separate_heading(out):
                out.append("")
            out.append(title)
        if body:
            out.append(body)
    return "\n".join(out).strip()


def mail_heading(text):
    return (
        '<div style="margin:0;padding:12px 16px 4px;font-size:16px;line-height:1.4;'
        'color:#e5b684;font-family:Arial,Helvetica,sans-serif;">' + html.escape(text, quote=False) + "</div>"
    )


def mail_pre(text, gap=False):
    margin = "0 0 16px" if gap else "0"
    return (
        '<pre style="margin:' + margin + ';width:100%;max-width:100%;box-sizing:border-box;'
        'display:block;background-color:#1e1e1e;padding:4px 16px 14px;color:#cccccc;'
        'font-family:Consolas,Courier New,monospace;font-size:13px;line-height:1.45;'
        'white-space:pre-wrap;word-wrap:break-word;word-break:break-word;'
        'overflow-wrap:break-word;overflow-x:auto;">' + html.escape(text, quote=False) + "</pre>"
    )


def advice_pieces(blocks):
    pieces = []
    for title, body in blocks:
        if title:
            pieces.append(("h", title))
        if body:
            pieces.append(("p", body))
    return pieces


def join_pieces(pieces):
    # The last text block has no bottom gap. Earlier text blocks do.
    chunks = []
    last = len(pieces) - 1
    for cursor, (kind, value) in enumerate(pieces):
        if kind == "h":
            chunks.append(mail_heading(value))
        else:
            chunks.append(mail_pre(value, gap=cursor != last))
    return "".join(chunks)


def advice_html(text):
    marked, blocks = advice_parts(text)
    if not marked:
        return mail_pre(text)
    return join_pieces(advice_pieces(blocks))


def read_template():
    path = Path(os.environ["MAIL_TEMPLATE_FILE"])
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        unread = os.environ.get("TEXT_TEMPLATE_UNREADABLE") or "unreadable template: {1}"
        print(unread.replace("{1}", str(exc)), file=sys.stderr)
        sys.exit(1)


def fill_subtitle():
    # A blank subtitle becomes the project, the host, and the date.
    if os.environ.get("MAIL_SUBTITLE", "").strip():
        return
    parts = (
        os.environ.get("PROJECT_NAME", ""),
        os.environ.get("HOSTNAME", ""),
        os.environ.get("DATE", ""),
    )
    os.environ["MAIL_SUBTITLE"] = " • ".join(part for part in parts if part)


def fill_footer():
    if os.environ.get("MAIL_FOOTER", "").strip():
        return
    os.environ["MAIL_FOOTER"] = os.environ.get("PROJECT_NAME", "")


def drop_named(tpl, name):
    return re.sub(
        r"<!--" + name + r"_START-->.*?<!--" + name + r"_END-->",
        "",
        tpl,
        count=1,
        flags=re.S,
    )


def drop_empty_blocks(tpl):
    # An empty section is cut out. A later copy of that section stays.
    for name, content_key in BLOCK_PAIRS:
        if not os.environ.get(content_key, "").strip():
            tpl = drop_named(tpl, name)
    return tpl


def fill_places(tpl):
    for key in PLACE_KEYS:
        value = html.escape(os.environ.get(key, ""), quote=False)
        tpl = tpl.replace("${" + key + "}", value)
    return tpl


def fill_advice(tpl, advice, plain_advice, html_advice):
    if advice:
        tpl = tpl.replace("${ADVICE}", html.escape(plain_advice, quote=False))
        return tpl.replace("${ADVICE_HTML}", html_advice)
    return drop_named(tpl, "ADVICE")


def fill_note(tpl, note, note_cmd):
    # The note is shown only together with its command.
    if note and note_cmd:
        tpl = tpl.replace("${NOTE}", html.escape(note, quote=False))
        return tpl.replace("${NOTE_CMD}", html.escape(note_cmd, quote=False))
    return drop_named(tpl, "NOTE")


def require_pre(tpl):
    # The finished page must contain a pre tag.
    if "<pre" in tpl:
        return
    missing = os.environ.get("TEXT_TEMPLATE_NO_PRE") or "template without a pre tag"
    print(missing, file=sys.stderr)
    sys.exit(1)


def render():
    content, note, advice, note_cmd = redacted_fields()
    plain_advice = advice_plain(advice)
    html_advice = advice_html(advice) if advice else ""
    tpl = read_template()
    fill_subtitle()
    fill_footer()
    tpl = drop_empty_blocks(tpl)
    tpl = fill_places(tpl)
    tpl = tpl.replace("${CONTENT}", html.escape(content, quote=False))
    tpl = fill_advice(tpl, advice, plain_advice, html_advice)
    tpl = fill_note(tpl, note, note_cmd)
    require_pre(tpl)
    sys.stdout.write(tpl)


if __name__ == "__main__":
    render()
