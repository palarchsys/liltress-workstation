#!/usr/bin/env bash
# =============================================================================
# File       : core/text/text.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================

# Placeholders are {1}, {2}, … The whole number is read, so {10} is not {1}.
# The argument is inserted as text. The catalog is not evaluated.

check_language() {
    case "${1:-}" in
        en|fr|de|es) return 0 ;;
        *) return 1 ;;
    esac
}

collect_text_dirs() {
    local -n dir_dest="$2"
    local lang="$1"
    local text_here="" text_product="" text_base="" candidate="" resolved="" seen="|"
    text_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    text_product="${PRODUCT_ROOT:-}"
    if [[ -z "${text_product}" ]]; then
        text_product="$(cd -- "${text_here}/../.." && pwd)"
    fi
    if declare -F get_product_base >/dev/null 2>&1; then
        text_base="$(get_product_base)"
    elif [[ -n "${BASE:-}" ]]; then
        text_base="${BASE}"
    elif [[ -n "${CONFIG_BASE_DIRECTORY:-}" ]]; then
        text_base="${CONFIG_BASE_DIRECTORY}"
    else
        text_base="/opt/liltress"
    fi
    dir_dest=()
    local -a text_candidates=(
        "$(cd -- "${text_here}/../.." && pwd)/locale/${lang}"
        "${text_product}/locale/${lang}"
        "${INSTALL_DIRECTORY:-}/locale/${lang}"
        "${text_base}/src/locale/${lang}"
        "${text_base}/locale/${lang}"
        "${INSTALL_DIRECTORY:-}/src/locale/${lang}"
    )
    if [[ -n "${TEXT_DIR:-}" ]]; then
        text_candidates+=("${TEXT_DIR}/${lang}")
    fi
    for candidate in "${text_candidates[@]}"; do
        [[ -n "${candidate}" && -d "${candidate}" ]] || continue
        resolved="$(cd -- "${candidate}" && pwd -P)" || continue
        [[ "${seen}" == *"|${resolved}|"* ]] && continue
        seen+="${resolved}|"
        dir_dest+=("${resolved}")
    done
}

read_text_file() {
    local file="$1"
    local -n text_dest="$2"
    local line="" key="" value="" open=0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^\[([a-z][a-z0-9-]*(\.[a-z0-9-]+)+|LABEL_[A-Z][A-Z0-9]*(_[A-Z0-9]+)*)\]$ ]]; then
            if [[ "${open}" -eq 1 ]]; then
                while [[ "${value}" == *$'\n' ]]; do
                    value="${value%$'\n'}"
                done
                text_dest["${key}"]="${value}"
            fi
            key="${BASH_REMATCH[1]}"
            value=""
            open=1
            continue
        fi
        if [[ "${open}" -eq 0 ]]; then
            continue
        fi
        value+="${line}"$'\n'
    done < "${file}"
    if [[ "${open}" -eq 1 ]]; then
        while [[ "${value}" == *$'\n' ]]; do
            value="${value%$'\n'}"
        done
        text_dest["${key}"]="${value}"
    fi
}

load_text() {
    local lang="${1:-${LANGUAGE:-en}}"
    local dir="" file="" joined="" key=""
    if ! check_language "${lang}"; then
        lang="en"
    fi
    if [[ -z "${LANGUAGE:-}" ]]; then
        LANGUAGE="en"
    fi
    if [[ "${TEXT_LANGUAGE:-}" == "${lang}" && "${TEXT_READY:-0}" == "1" && "${TEXT_DIR_LOADED:-}" == "${TEXT_DIR:-}" ]]; then
        export LANGUAGE
        return 0
    fi
    declare -gA TEXT_ENGLISH=()
    declare -gA TEXT_SELECTED=()
    local -a english_dirs=() selected_dirs=()
    collect_text_dirs en english_dirs
    if [[ "${lang}" == "en" ]]; then
        selected_dirs=("${english_dirs[@]}")
    else
        collect_text_dirs "${lang}" selected_dirs
    fi
    for dir in "${english_dirs[@]}"; do
        for file in "${dir}"/*.txt; do
            [[ -f "${file}" ]] || continue
            read_text_file "${file}" TEXT_ENGLISH
        done
    done
    if [[ "${lang}" == "en" ]]; then
        for key in "${!TEXT_ENGLISH[@]}"; do
            TEXT_SELECTED["${key}"]="${TEXT_ENGLISH[${key}]}"
        done
    else
        for dir in "${selected_dirs[@]}"; do
            for file in "${dir}"/*.txt; do
                [[ -f "${file}" ]] || continue
                read_text_file "${file}" TEXT_SELECTED
            done
        done
    fi
    joined="$(IFS=:; printf '%s' "${english_dirs[*]}")"
    TEXT_EN_DIRS="${joined}"
    joined="$(IFS=:; printf '%s' "${selected_dirs[*]}")"
    TEXT_LANG_DIRS="${joined}"
    TEXT_LANGUAGE="${lang}"
    TEXT_DIR_LOADED="${TEXT_DIR:-}"
    TEXT_READY=1
    export LANGUAGE TEXT_EN_DIRS TEXT_LANG_DIRS
}

apply_text() {
    local text="$1"
    shift
    local -a text_args=("$@")
    local text_out="" text_rest="${text}" text_head="" text_num="" text_mark=""
    while [[ "${text_rest}" == *'{'* ]]; do
        text_head="${text_rest%%\{*}"
        text_rest="${text_rest#*\{}"
        text_out+="${text_head}"
        if [[ "${text_rest}" =~ ^([0-9]+)\} ]]; then
            text_num="${BASH_REMATCH[1]}"
            text_mark="${BASH_REMATCH[0]}"
            text_rest="${text_rest#"${text_mark}"}"
            if (( text_num >= 1 && text_num <= ${#text_args[@]} )); then
                text_out+="${text_args[$((text_num - 1))]}"
            else
                text_out+="{${text_num}}"
            fi
        else
            text_out+="{"
        fi
    done
    printf '%s' "${text_out}${text_rest}"
}

get_text() {
    local key="$1"
    shift
    local lang="${LANGUAGE:-en}" text=""
    if ! check_language "${lang}"; then
        lang="en"
    fi
    if [[ "${TEXT_LANGUAGE:-}" != "${lang}" || "${TEXT_READY:-0}" != "1" || "${TEXT_DIR_LOADED:-}" != "${TEXT_DIR:-}" ]]; then
        load_text "${lang}"
    fi
    if [[ -n "${TEXT_SELECTED[${key}]+x}" ]]; then
        text="${TEXT_SELECTED[${key}]}"
    elif [[ -n "${TEXT_ENGLISH[${key}]+x}" ]]; then
        text="${TEXT_ENGLISH[${key}]}"
    else
        printf '%s' "${key}"
        return 0
    fi
    if [[ "$#" -eq 0 ]]; then
        printf '%s' "${text}"
        return 0
    fi
    apply_text "${text}" "$@"
}

read_text_record() {
    local lang="$1" key="$2"
    local -a dirs=()
    local dir="" file="" line="" current="" value="" found=""
    collect_text_dirs "${lang}" dirs
    for dir in "${dirs[@]}"; do
        for file in "${dir}"/*.txt; do
            [[ -f "${file}" ]] || continue
            current=""
            value=""
            while IFS= read -r line || [[ -n "${line}" ]]; do
                if [[ "${line}" =~ ^\[([a-z][a-z0-9-]*(\.[a-z0-9-]+)+|LABEL_[A-Z][A-Z0-9]*(_[A-Z0-9]+)*)\]$ ]]; then
                    if [[ "${current}" == "${key}" ]]; then
                        found="${value}"
                        while [[ "${found}" == *$'\n' ]]; do
                            found="${found%$'\n'}"
                        done
                    fi
                    current="${BASH_REMATCH[1]}"
                    value=""
                    continue
                fi
                if [[ -n "${current}" ]]; then
                    value+="${line}"$'\n'
                fi
            done < "${file}"
            if [[ "${current}" == "${key}" ]]; then
                found="${value}"
                while [[ "${found}" == *$'\n' ]]; do
                    found="${found%$'\n'}"
                done
            fi
        done
    done
    printf '%s' "${found}"
}

read_language_file() {
    local file="$1" line="" value="" sibling=""
    if [[ -z "${LANGUAGE:-}" ]]; then
        LANGUAGE="en"
    fi
    if [[ -f "${file}" ]] && ! grep -qE '^LANGUAGE=' -- "${file}"; then
        sibling="$(dirname -- "${file}")/user.conf"
        if [[ -f "${sibling}" ]] && grep -qE '^LANGUAGE=' -- "${sibling}"; then
            file="${sibling}"
        fi
    fi
    if [[ -f "${file}" ]]; then
        line="$(grep -E '^LANGUAGE=' -- "${file}" | head -n 1 || true)"
        if [[ -n "${line}" ]]; then
            value="${line#LANGUAGE=}"
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"
            if check_language "${value}"; then
                LANGUAGE="${value}"
            elif [[ -z "${value}" ]]; then
                LANGUAGE="en"
            fi
        fi
    fi
    if ! check_language "${LANGUAGE}"; then
        LANGUAGE="en"
    fi
    export LANGUAGE
    load_text "${LANGUAGE}"
}

# Command substitution starts a subshell. A catalog loaded there is discarded.
# Load once in this shell so later lookups reuse the arrays.

load_product_text() {
    local lang_file=""
    if [[ -n "${PRODUCT_ROOT:-}" && -f "${PRODUCT_ROOT}/config/global.conf" ]]; then
        lang_file="${PRODUCT_ROOT}/config/global.conf"
    elif [[ -n "${INSTALL_DIRECTORY:-}" && -f "${INSTALL_DIRECTORY}/config/global.conf" ]]; then
        lang_file="${INSTALL_DIRECTORY}/config/global.conf"
    fi
    if [[ -n "${lang_file}" ]]; then
        read_language_file "${lang_file}"
        return 0
    fi
    if [[ -n "${LANGUAGE:-}" ]]; then
        load_text "${LANGUAGE}"
    fi
}

ask_language() {
    local current="${LANGUAGE:-en}" hint="" choice="" lang=""
    check_language "${current}" || current="en"
    for lang in en fr de es; do
        hint="$(read_text_record "${lang}" "configure.language.hint")"
        if [[ -z "${hint}" ]]; then
            hint="${lang}"
        fi
        printf '%s\n' "${hint}" >&2
    done
    printf '%s\n' "1 en" >&2
    printf '%s\n' "2 fr" >&2
    printf '%s\n' "3 de" >&2
    printf '%s\n' "4 es" >&2
    IFS= read -r choice || choice=""
    choice="${choice#"${choice%%[![:space:]]*}"}"
    choice="${choice%"${choice##*[![:space:]]}"}"
    case "${choice}" in
        "") LANGUAGE="${current}" ;;
        1|en|EN) LANGUAGE="en" ;;
        2|fr|FR) LANGUAGE="fr" ;;
        3|de|DE) LANGUAGE="de" ;;
        4|es|ES) LANGUAGE="es" ;;
        *) LANGUAGE="en" ;;
    esac
    export LANGUAGE
    TEXT_READY=0
    load_text "${LANGUAGE}"
}
