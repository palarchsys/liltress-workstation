#!/usr/bin/env bash
# =============================================================================
# File       : core/host.sh
# Updated at : 2026-11-07
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
check_ubuntu_base() {
    local os_id="${ID:-}"
    local os_codename="${UBUNTU_CODENAME:-}"
    local version_id="${VERSION_ID:-}"
    local pretty="${PRETTY_NAME:-${OS_PRETTY:-inconnu}}"
    local base_version=""

    if [[ "${os_id}" != "ubuntu" ]]; then
        log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.17" "${pretty}"
    fi

    if [[ "${version_id}" =~ ^([0-9]+)\.([0-9]+) ]]; then
        base_version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
    fi
    if [[ -z "${base_version}" ]]; then
        log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.18" "${version_id:-aucune}"
    fi

    UBUNTU_BASE_VERSION="${base_version}"
    UBUNTU_BASE_CODENAME="${os_codename:-inconnu}"
    if ! dpkg --compare-versions "${UBUNTU_BASE_VERSION}" ge "26.04"; then
        log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.19" "${UBUNTU_BASE_VERSION}" "${UBUNTU_BASE_CODENAME}"
    fi
    export UBUNTU_BASE_VERSION UBUNTU_BASE_CODENAME
}

# Return 0 when the resolved base is an LTS: even year, minor 4.
check_ubuntu_lts() {
    local version="${UBUNTU_BASE_VERSION:-}"
    local major=0
    local minor=0

    if [[ ! "${version}" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
        return 1
    fi
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    if [[ "${minor}" -eq 4 && $((major % 2)) -eq 0 ]]; then
        return 0
    fi
    return 1
}

# Print the Postfix map type in use: hash on 26.04, cdb on 26.10.
get_sasl_map_type() {
    local map_type=""
    map_type="$(postconf -h default_database_type 2>/dev/null || true)"
    case "${map_type}" in
        hash|cdb|lmdb)
            printf '%s\n' "${map_type}"
            ;;
        *)
            log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.20" "${map_type:-aucun}"
            ;;
    esac
}

get_operating_system() {
    # shellcheck disable=SC1091
    source /etc/os-release
    OS_ID="${ID:-}"
    OS_VERSION_ID="${VERSION_ID:-}"
    OS_PRETTY="${PRETTY_NAME:-}"
    export OS_ID OS_VERSION_ID OS_PRETTY
    check_ubuntu_base
}

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

check_virtual_machine() {
    if command -v virsh >/dev/null 2>&1; then
        return 0
    fi
    if dpkg-query -W -f '${Status}\n' qemu-kvm qemu-system-x86 libvirt-daemon 2>/dev/null | grep -q 'install ok'; then
        return 0
    fi
    if [[ -e /dev/kvm ]]; then
        return 0
    fi
    return 1
}

check_app() {
    local name="$1"
    command -v "$name" >/dev/null 2>&1 && return 0
    dpkg-query -W -f '${Status}\n' "$name" 2>/dev/null | grep -q 'install ok' && return 0
    flatpak info "$name" >/dev/null 2>&1 && return 0
    return 1
}

check_password_unchanged() {
    case "$*" in
        *chpasswd*|*passwd\ *|*" usermod -p "*|*chage*)
            log_error "${INSTALL_WATCHER:-BASH}" "install.lib.error.22" "$*"
            ;;
    esac
}

check_ubuntu_pro() {
    command -v pro >/dev/null 2>&1 || return 1
    local st
    st="$(pro status --format json 2>/dev/null || true)"
    if [[ -n "$st" ]] && command -v jq >/dev/null 2>&1; then
        echo "$st" | jq -e '.attached == true' >/dev/null 2>&1 && return 0
    fi
    pro status 2>/dev/null | grep -qiE 'This machine is attached|machine is attached to an Ubuntu Pro|est attachée|Attached:[[:space:]]*(yes|true)' && return 0
    return 1
}
