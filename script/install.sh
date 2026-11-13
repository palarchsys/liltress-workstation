#!/usr/bin/env bash
# =============================================================================
# File       : script/install.sh
# Updated at : 2026-11-13
# Creator    : palarchsys
# =============================================================================

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/palarchsys/liltress-workstation}"
BRANCH="${BRANCH:-main}"
INSTALL_ROOT="${INSTALL_ROOT:-/opt/liltress-workstation}"

if [[ "${EUID}" -ne 0 ]]; then
    if declare -F get_text >/dev/null 2>&1; then
        printf '%s\n' "$(get_text install.this-script-must-be-executed-as-root-sudo)" >&2
    else
        printf '%s\n' "This script must be run as root (sudo)." >&2
    fi
    exit 1
fi

if [[ -z "${INSTALL_ROOT}" || "${INSTALL_ROOT}" != /opt/* || "${INSTALL_ROOT}" == "/opt" || "${INSTALL_ROOT}" == "/" || "${INSTALL_ROOT}" == *..* || "${INSTALL_ROOT}" == *[[:space:]]* ]]; then
    if declare -F get_text >/dev/null 2>&1; then
        printf '%s\n' "$(get_text install.root-of-install-rejected "${INSTALL_ROOT}")" >&2
    else
        printf '%s\n' "Install root rejected: ${INSTALL_ROOT}" >&2
    fi
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
NEEDRESTART_MODE=a apt-get upgrade -y -qq
apt-get install -y -qq ca-certificates git >/dev/null

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "${tmp}/keep"

save_prepared() {
    local root="$1"
    if [[ -f "${root}/config/global.conf" ]] && grep -q '^CONFIG_PREPARED=1$' "${root}/config/global.conf"; then
        cp -a "${root}/config/global.conf" "${tmp}/keep/global.conf"
        if [[ -f "${root}/config/user.conf" ]]; then
            cp -a "${root}/config/user.conf" "${tmp}/keep/user.conf"
        fi
    fi
    if [[ ! -f "${tmp}/keep/secrets.conf" && -f "${root}/config/secrets.conf" ]]; then
        cp -a "${root}/config/secrets.conf" "${tmp}/keep/secrets.conf"
    fi
}

save_scan_skip() {
    local root="$1"
    if [[ -f "${tmp}/keep/scan-skip.paths" ]]; then
        return 0
    fi
    if [[ -f "${root}/config/clamav/scan-skip.paths" ]] && ! grep -q '__HOME__' "${root}/config/clamav/scan-skip.paths"; then
        cp -a "${root}/config/clamav/scan-skip.paths" "${tmp}/keep/scan-skip.paths"
    fi
}

save_runtime() {
    local root="$1"
    local name
    for name in docker secrets; do
        if [[ ! -e "${tmp}/keep/${name}" && -d "${root}/${name}" ]]; then
            mv "${root}/${name}" "${tmp}/keep/${name}"
        fi
    done
    if [[ -d "${root}/cron" ]]; then
        mkdir -p "${tmp}/keep/cron"
        for name in cron_logs security_logs alerts archives quarantine; do
            if [[ -d "${root}/cron/${name}" && ! -e "${tmp}/keep/cron/${name}" ]]; then
                mv "${root}/cron/${name}" "${tmp}/keep/cron/${name}"
            fi
        done
    fi
}

restore_kept() {
    if [[ -f "${tmp}/keep/global.conf" ]]; then
        cp -a "${tmp}/keep/global.conf" "${INSTALL_ROOT}/config/global.conf"
    fi
    if [[ -f "${tmp}/keep/user.conf" ]]; then
        cp -a "${tmp}/keep/user.conf" "${INSTALL_ROOT}/config/user.conf"
    fi
    if [[ -f "${tmp}/keep/secrets.conf" ]]; then
        cp -a "${tmp}/keep/secrets.conf" "${INSTALL_ROOT}/config/secrets.conf"
        chmod 600 "${INSTALL_ROOT}/config/secrets.conf"
    fi
    if [[ -f "${tmp}/keep/scan-skip.paths" ]]; then
        mkdir -p "${INSTALL_ROOT}/config/clamav"
        cp -a "${tmp}/keep/scan-skip.paths" "${INSTALL_ROOT}/config/clamav/scan-skip.paths"
        chmod 644 "${INSTALL_ROOT}/config/clamav/scan-skip.paths"
    fi
    local name
    for name in docker secrets; do
        if [[ -d "${tmp}/keep/${name}" ]]; then
            rm -rf "${INSTALL_ROOT:?}/${name:?}"
            mv "${tmp}/keep/${name}" "${INSTALL_ROOT}/${name}"
        fi
    done
    if [[ -d "${tmp}/keep/cron" ]]; then
        mkdir -p "${INSTALL_ROOT}/cron"
        for name in cron_logs security_logs alerts archives quarantine; do
            if [[ -d "${tmp}/keep/cron/${name}" ]]; then
                rm -rf "${INSTALL_ROOT:?}/cron/${name:?}"
                mv "${tmp}/keep/cron/${name}" "${INSTALL_ROOT}/cron/${name}"
            fi
        done
    fi
}

mkdir -p "${INSTALL_ROOT}"
save_prepared "${INSTALL_ROOT}"
save_scan_skip "${INSTALL_ROOT}"
if [[ -f "${INSTALL_ROOT}/src/liltress" ]]; then
    save_prepared "${INSTALL_ROOT}/src"
    save_scan_skip "${INSTALL_ROOT}/src"
    save_runtime "${INSTALL_ROOT}/src"
fi

accepted=0
if [[ -n "$(find "${INSTALL_ROOT}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    if [[ -f "${INSTALL_ROOT}/core/boot/lib.sh" && -f "${INSTALL_ROOT}/core/boot/bootstrap.sh" && -f "${INSTALL_ROOT}/config/global.conf" ]]; then
        INSTALL_DIRECTORY="${INSTALL_ROOT}"
        # shellcheck disable=SC1091
        source "${INSTALL_DIRECTORY}/core/boot/lib.sh" || true
        # shellcheck disable=SC1091
        source "${INSTALL_DIRECTORY}/config/global.conf" || true
        if declare -F read_language_file >/dev/null 2>&1; then
            read_language_file "${INSTALL_DIRECTORY}/config/global.conf" || true
        fi
    fi
    answer=""
    if [[ -r /dev/tty ]] && { exec 3<>/dev/tty; } 2>/dev/null; then
        if declare -F get_text >/dev/null 2>&1; then
            printf '%s' "$(get_text install.continue-o-n)" >&3
        else
            printf '%s' "Continue the installation? [O/N] " >&3
        fi
        IFS= read -r answer <&3 || answer=""
        exec 3<&-
    else
        if declare -F get_text >/dev/null 2>&1; then
            printf '%s\n' "$(get_text install.no-terminal)" >&2
        else
            printf '%s\n' "No terminal for the question. Stopped." >&2
        fi
        exit 0
    fi
    case "${answer}" in
        O|o) accepted=1 ;;
        *)
            if declare -F get_text >/dev/null 2>&1; then
                printf '%s\n' "$(get_text install.stopped)"
            else
                printf '%s\n' "Stopped."
            fi
            exit 0
            ;;
    esac
fi

if [[ -d "${INSTALL_ROOT}/.git" ]]; then
    git -C "${INSTALL_ROOT}" fetch --depth 1 origin "${BRANCH}"
    trap - EXIT
    save_runtime "${INSTALL_ROOT}"
    git -C "${INSTALL_ROOT}" clean -fdx
    git -C "${INSTALL_ROOT}" checkout -f -B "${BRANCH}" FETCH_HEAD
else
    trap - EXIT
    save_runtime "${INSTALL_ROOT}"
    find "${INSTALL_ROOT}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" "${INSTALL_ROOT}"
fi

if [[ ! -f "${INSTALL_ROOT}/config/global.conf" || ! -f "${INSTALL_ROOT}/liltress" ]]; then
    if declare -F get_text >/dev/null 2>&1; then
        printf '%s\n' "$(get_text install.archive-github-invalid-config-global-conf-absent)" >&2
    else
        printf '%s\n' "Invalid GitHub archive (config/global.conf absent)." >&2
    fi
    exit 1
fi

restore_kept
trap 'rm -rf "$tmp"' EXIT
rm -rf "${INSTALL_ROOT:?}/src"
chmod 755 "${INSTALL_ROOT}/liltress"
INSTALL_DIRECTORY="${INSTALL_ROOT}" bash -c '
    set -euo pipefail
    # shellcheck disable=SC1091
    source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
    # shellcheck disable=SC1091
    source "${INSTALL_DIRECTORY}/config/global.conf"
    set_tree_modes
'

INSTALL_DIRECTORY="${INSTALL_ROOT}"
# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/config/global.conf"
read_language_file "${INSTALL_DIRECTORY}/config/global.conf"

if [[ "${accepted}" -eq 0 ]]; then
    answer=""
    if [[ -r /dev/tty ]] && { exec 3<>/dev/tty; } 2>/dev/null; then
        printf '%s' "$(get_text install.continue-o-n)" >&3
        IFS= read -r answer <&3 || answer=""
        exec 3<&-
    else
        printf '%s\n' "$(get_text install.no-terminal)" >&2
        exit 0
    fi
    case "${answer}" in
        O|o) ;;
        *)
            printf '%s\n' "$(get_text install.stopped)"
            exit 0
            ;;
    esac
fi

if bash "${INSTALL_ROOT}/script/configure.sh" --check; then
    printf '%s\n' "$(get_text install.launch-of-the-installation)"
    cd "${INSTALL_ROOT}"
    exec bash "${INSTALL_ROOT}/script/run.sh"
fi

printf '%b' "$(get_text install.launch-of-the-configuration-n-n)"
exec bash "${INSTALL_ROOT}/script/configure.sh"
