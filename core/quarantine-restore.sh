#!/usr/bin/env bash
# =============================================================================
# File       : core/quarantine-restore.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================
# -----------------------------------------------------------------------------
# Purpose    : Put one recorded file back at its original path.
# Note       : The registry line is the only accepted origin.
# -----------------------------------------------------------------------------

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
for candidate in \
    "${script_dir}/log.sh" \
    "${script_dir}/../core/log.sh" \
    "${script_dir}/../src/core/log.sh" \
    "${G_CONFIG_BASE_DIRECTORY:-}/src/core/log.sh" \
    "${G_INSTALL_DIRECTORY:-}/core/log.sh" \
    "${G_INSTALL_DIRECTORY:-}/src/core/log.sh"
do
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
        # shellcheck disable=SC1090
        source "${candidate}"
        break
    fi
done

if [[ "$(basename -- "${script_dir}")" == "bin" ]]; then
    base="$(dirname -- "${script_dir}")"
else
    base="${G_CONFIG_BASE_DIRECTORY:-${W_BASE:-${G_BASE:-/opt/liltress}}}"
fi
if [[ -f "${base}/config/global.conf" ]] && declare -F read_language_file >/dev/null 2>&1; then
    read_language_file "${base}/config/global.conf"
fi

if [[ "${EUID}" -ne 0 ]]; then
    if declare -F get_text >/dev/null 2>&1; then
        printf '%s\n' "$(get_text log.root-required)" >&2
    else
        printf '%s\n' "root required" >&2
    fi
    exit 1
fi

if [[ "$#" -ne 1 || -z "${1:-}" ]]; then
    printf '%s\n' "$(get_text quarantine.identifier-required)" >&2
    exit 1
fi

id="$1"
if [[ ! "${id}" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+- ]]; then
    printf '%s\n' "$(get_text quarantine.identifier-rejected)" >&2
    exit 1
fi
case "${id}" in
    */*|*\\*)
        printf '%s\n' "$(get_text quarantine.identifier-rejected)" >&2
        exit 1
        ;;
esac

registry="${base}/cron/quarantine.registry"
if [[ ! -f "${registry}" ]]; then
    printf '%s\n' "$(get_text quarantine.identifier-absent-of-the-registre)" >&2
    exit 1
fi

line="$(awk -F '\t' -v want="${id}" '$1 == want { print; exit }' "${registry}")"
if [[ -z "${line}" ]]; then
    printf '%s\n' "$(get_text quarantine.identifier-absent-of-the-registre)" >&2
    exit 1
fi

IFS=$'\t' read -r found_id _moment _source origin stored _signature <<< "${line}"
if [[ "${found_id}" != "${id}" || -z "${origin}" || -z "${stored}" ]]; then
    printf '%s\n' "$(get_text quarantine.identifier-absent-of-the-registre)" >&2
    exit 1
fi
case "${origin}" in
    /*) ;;
    *)
        printf '%s\n' "$(get_text quarantine.location-original-rejected)" >&2
        exit 1
        ;;
esac

if [[ ! -e "${stored}" ]]; then
    printf '%s\n' "$(get_text quarantine.file-of-quarantine-absent)" >&2
    exit 1
fi

parent="$(dirname -- "${origin}")"
if [[ ! -d "${parent}" ]]; then
    printf '%s\n' "$(get_text quarantine.directory-original-absent)" >&2
    exit 1
fi

if [[ -e "${origin}" ]]; then
    printf '%s\n' "$(get_text quarantine.location-original-busy)" >&2
    exit 1
fi

mv -- "${stored}" "${origin}"
printf '%s\n' "$(get_text quarantine.file-reset-in-place)"
exit 0
