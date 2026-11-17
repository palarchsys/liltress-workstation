#!/usr/bin/env bash
# =============================================================================
# File       : system/sudoers/apply.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Build the sudoers file from the command catalog.
# Note       : An explicit output path skips the root demand.
# -----------------------------------------------------------------------------


set -euo pipefail

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY

if [[ -z "${INSTALL_DIRECTORY}" || ! -d "${INSTALL_DIRECTORY}" ]]; then
    printf '%s\n' "répertoire d'installation absent" >&2
    exit 1
fi

# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/core/boot/lib.sh"
# shellcheck disable=SC1091
source "${INSTALL_DIRECTORY}/config/global.conf"

if [[ -z "${SUDOERS_OUT:-}" ]]; then
    require_root
fi

log_info "${INSTALL_WATCHER}" "install.sudoers.start"

target_user=""
if [[ -f "${INSTALL_DIRECTORY}/script/verify/matrix.sh" ]]; then
    target_user="${MAIN_USER:-}"
else
    target_user="${SUDO_USER:-}"
fi
if [[ -z "${target_user}" || "${target_user}" == "root" ]] \
    || [[ ! "${target_user}" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]; then
    log_error "${INSTALL_WATCHER}" "install.sudoers.user"
fi

catalog="${INSTALL_DIRECTORY}/system/sudoers/commands.csv"
if [[ ! -f "${catalog}" ]]; then
    log_error "${INSTALL_WATCHER}" "log.file-not-found" "${catalog}"
fi

bin="${INSTALL_DIRECTORY}/liltress"
specs=()
while IFS= read -r command || [[ -n "${command}" ]]; do
    [[ -n "${command}" ]] || continue
    rest="${command}"
    rest="${rest#sudo }"
    rest="${rest#\"./liltress\" }"
    rest="${rest#./liltress }"
    spec="${bin}"
    wild=0
    set -f
    for part in ${rest}; do
        if [[ "${part}" == \<* || "${part}" == *"|"* || "${part}" == \[* ]]; then
            wild=1
            break
        fi
        spec="${spec} ${part}"
    done
    if [[ "${wild}" -eq 1 ]]; then
        spec="${spec} *"
    fi
    set +f
    specs+=("${spec}")
done < <(
    python3 - "${catalog}" <<'PY'
import csv
import sys
path = sys.argv[1]
allowed = {"liltress", "vpn", "verify", "maintain"}
with open(path, newline="", encoding="utf-8") as handle:
    for row in csv.DictReader(handle):
        group = (row.get("group") or "").strip()
        command = (row.get("command") or "").strip()
        if group not in allowed or not command:
            continue
        print(command)
PY
)

if [[ "${#specs[@]}" -eq 0 ]]; then
    log_error "${INSTALL_WATCHER}" "install.sudoers.invalid"
fi

out="${SUDOERS_OUT:-/etc/sudoers.d/liltress-commands}"
{
    printf '%s\n' "# Liltress"
    printf '%s ALL=(root) NOPASSWD: ' "${target_user}"
    last=$((${#specs[@]} - 1))
    index=0
    while [[ "${index}" -le "${last}" ]]; do
        if [[ "${index}" -eq 0 ]]; then
            printf '%s' "${specs[${index}]}"
        else
            printf ', \\\n    %s' "${specs[${index}]}"
        fi
        index=$((index + 1))
    done
    printf '\n'
} >"${out}"

chmod 440 "${out}"
if [[ -z "${SUDOERS_OUT:-}" ]]; then
    chown root:root "${out}"
fi
if command -v visudo >/dev/null 2>&1; then
    if ! visudo -cf "${out}" >/dev/null; then
        rm -f "${out}"
        log_error "${INSTALL_WATCHER}" "install.sudoers.invalid"
    fi
fi
log_success "${INSTALL_WATCHER}" "install.sudoers.ok" "${target_user}"
