#!/usr/bin/env bash
# =============================================================================
# File       : script/config/common.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================
# -----------------------------------------------------------------------------
# Purpose    : Shared refusals and mail-field reset for both products.
# Note       : The server questionnaire clears MAIL_ALERTS itself.
# -----------------------------------------------------------------------------

fail_apply() {
    printf '%s\n' "$1"
    printf 'error\n'
    exit 1
}

show_refusals() {
    local line=""
    if [[ ${#CONFIG_ERRORS[@]} -eq 0 ]]; then
        return 0
    fi
    for line in "${CONFIG_ERRORS[@]}"; do
        printf 'refus: %s\n' "${line}"
    done
}

clear_mail() {
    POSTFIX_SMTP_LOGIN=""
    POSTFIX_MAIL_ADDRESS=""
    POSTFIX_MAIL_PASSWORD=""
    POSTFIX_MAIL_SMTP=""
    WATCHDOG_MAIL=""
}
