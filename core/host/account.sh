#!/usr/bin/env bash
# =============================================================================
# File       : core/host/account.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================


get_current_user() {
    local u="${SUDO_USER:-${USER:-}}"
    if [[ -z "$u" || "$u" == "root" ]]; then
        u="$(awk -F: '$3 >= 1000 && $3 < 65534 && $1 != "nobody" { print $1; exit }' /etc/passwd)"
    fi
    if [[ -z "$u" ]]; then
        log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.16"
    fi
    CURRENT_USER="$u"
    CURRENT_GROUP="$(id -gn "$CURRENT_USER")"
    CURRENT_HOME="$(getent passwd "$CURRENT_USER" | awk -F: '{print $6}')"
    export CURRENT_USER CURRENT_GROUP CURRENT_HOME
}

# Ubuntu itself, release 26.04 or newer. A derivative is refused.

check_desktop_account() {
    local uid="$1" home="$2" shell="$3"
    [[ "${uid}" -ge 1000 && "${uid}" -lt 60000 ]] || return 1
    [[ "${home}" == /home/* ]] || return 1
    case "${shell}" in
        */nologin|*/false) return 1 ;;
    esac
    return 0
}

write_account_table() {
    local dest="$1"
    local name uid gid gecos home shell groups shadow_fp maxdays
    : > "${dest}.tmp"
    while IFS=: read -r name _ uid gid gecos home shell; do
        if ! check_desktop_account "${uid}" "${home}" "${shell}"; then
            continue
        fi
        groups="$(id -nG "${name}" | tr ' ' '\n' | LC_ALL=C sort | paste -sd, -)"
        shadow_fp="$(awk -F: -v u="${name}" '$1==u { print $2 }' /etc/shadow | sha256sum | awk '{ print $1 }')"
        maxdays="$(LANG=C LC_ALL=C chage -l "${name}" 2>/dev/null | awk -F: '/Maximum/ { gsub(/ /, "", $2); print $2 }')"
        printf "$(get_text log.t-t-t-t-t-t-t-t "${name}" "${uid}" "${gid}" "${gecos}" "${home}" "${shell}" "${groups}" "${shadow_fp}" "${maxdays}")" >> "${dest}.tmp"
    done < /etc/passwd
    LC_ALL=C sort -o "${dest}" "${dest}.tmp"
    rm -f "${dest}.tmp"
    chmod 600 "${dest}"
}

ACCOUNT_SNAPSHOT="/var/lib/liltress-workstation/accounts/human.tsv"

record_account_snapshot() {
    mkdir -p /var/lib/liltress-workstation/accounts
    chmod 700 /var/lib/liltress-workstation/accounts
    write_account_table "${ACCOUNT_SNAPSHOT}"

    local n
    n="$(wc -l < "${ACCOUNT_SNAPSHOT}" | tr -d ' ')"
    if [[ "${n}" -lt 1 ]]; then
        log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.21"
    fi
}

strip_virt_groups() {
    awk -F '\t' 'BEGIN { OFS = "\t" } {
        n = split($7, g, ",")
        out = ""
        for (i = 1; i <= n; i++) {
            if (g[i] != "libvirt" && g[i] != "kvm") {
                out = out (out ? "," : "") g[i]
            }
        }
        $7 = out
        print
    }'
}

check_account_drift() {
    local current baseline="${ACCOUNT_SNAPSHOT}" norm_base norm_now
    [[ -f "${baseline}" ]] || {
        echo "$(get_text log.snapshot-of-the-accounts-absent "${baseline}")"
        return 1
    }
    current="$(mktemp)"
    norm_base="$(mktemp)"
    norm_now="$(mktemp)"
    write_account_table "${current}"
    strip_virt_groups < "${baseline}" > "${norm_base}"
    strip_virt_groups < "${current}" > "${norm_now}"
    if cmp -s "${norm_base}" "${norm_now}"; then
        rm -f "${current}" "${norm_base}" "${norm_now}"
        return 0
    fi
    diff -u "${baseline}" "${current}" || true
    rm -f "${current}" "${norm_base}" "${norm_now}"
    return 1
}

# Read one keyword from an sshd -T dump on stdin. Match ignores keyword case.
