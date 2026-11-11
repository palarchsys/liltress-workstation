#!/usr/bin/env bash
# =============================================================================
# File       : core/host/ssh.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================


read_sshd_value() {
    local keyword="${1,,}"
    awk -v key="${keyword}" 'tolower($1) == key { print tolower($2); exit }'
}

# Print one effective sshd setting. 10.2 uses lowercase, 10.5 uses canonical case.

get_sshd_value() {
    local keyword="${1,,}"
    sshd -T 2>/dev/null | read_sshd_value "${keyword}"
}

get_ssh_port() {
    local port="22"
    if command -v sshd >/dev/null 2>&1; then
        port="$(get_sshd_value port)"
        [[ -z "$port" ]] && port="22"
    fi
    SSH_PORT="$port"
    export SSH_PORT
}
