#!/usr/bin/env python3
# =============================================================================
# File       : python/text_redact.py
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Mask secrets in mail, excerpts, and packs.
# Note       : Each caller passes its own mask, except the pack which uses fixed words.
# -----------------------------------------------------------------------------


import re


def redact_mail(text, redacted, redacted_key):
    # A value that already starts with the mask stays as it is.
    token = re.escape(redacted)
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


def redact_excerpt(text, redacted, redacted_key):
    # The key banner matches any letter case. A bearer token under eight characters stays.
    text = re.sub(
        r"(?is)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----",
        lambda _match: redacted_key,
        text,
    )
    text = re.sub(
        r"(?i)\b(password|passwd|token|secret|api[_-]?key|authorization|bearer)\b(\s*[:=]\s*)\S+",
        lambda match: match.group(1) + match.group(2) + redacted,
        text,
    )
    text = re.sub(
        r"(?i)\bbearer\s+[A-Za-z0-9._~+/-]{8,}",
        lambda _match: "Bearer " + redacted,
        text,
    )
    return text


def redact_pack(text):
    # Fixed words replace a key block and an assignment. A bare bearer token stays.
    text = re.sub(
        r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----",
        "[private key redacted]",
        text,
        flags=re.S,
    )
    text = re.sub(
        r"(?i)\b(password|passwd|token|secret|api[_-]?key|authorization|bearer)\b(\s*[:=]\s*)\S+",
        lambda match: match.group(1) + match.group(2) + "[redacted]",
        text,
    )
    return text
