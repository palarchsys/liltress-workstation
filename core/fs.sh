#!/usr/bin/env bash
# =============================================================================
# File       : core/fs.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

locate_config_file() {
    local rel="$1"
    local root candidate shared_parent probe
    local seen="|"
    local roots=()

    if [[ -n "${G_INSTALL_DIRECTORY:-}" ]]; then
        roots+=("${G_INSTALL_DIRECTORY}")
    fi
    if [[ -n "${G_PRODUCT_ROOT:-}" ]]; then
        roots+=("${G_PRODUCT_ROOT}")
    fi
    if [[ -n "${G_CONFIG_BASE_DIRECTORY:-}" ]]; then
        roots+=("${G_CONFIG_BASE_DIRECTORY}/src" "${G_CONFIG_BASE_DIRECTORY}")
    fi
    if [[ -n "${W_BASE:-}" ]]; then
        roots+=("${W_BASE}/src" "${W_BASE}")
    fi
    if [[ -n "${G_BASE:-}" ]]; then
        roots+=("${G_BASE}/src" "${G_BASE}")
    fi
    for probe in "${G_INSTALL_DIRECTORY:-}" "${G_PRODUCT_ROOT:-}"; do
        [[ -n "${probe}" && -d "${probe}" ]] || continue
        if shared_parent="$(cd -- "${probe}/.." && pwd)"; then
            if [[ -d "${shared_parent}/core" && -d "${shared_parent}/config" ]]; then
                roots+=("${shared_parent}")
                break
            fi
        fi
    done

    for root in "${roots[@]}"; do
        [[ -n "${root}" ]] || continue
        [[ "${seen}" == *"|${root}|"* ]] && continue
        seen="${seen}${root}|"
        candidate="${root}/config/${rel}"
        if [[ -f "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

add_line() {
    local file="$1"
    local line="$2"
    local comment="${3:-}"
    if ! grep -qF "$line" "$file" 2>/dev/null; then
        [[ -n "$comment" ]] && echo "$comment" >> "$file"
        echo "$line" >> "$file"
    fi
}

copy_backup() {
    local file="$1"
    local backup="${file}.bak"
    [[ -f "$file" ]] || return 0
    [[ -f "$backup" ]] && return 0
    log_info "${INSTALL_WATCHER:-BASH}" "install.fs.info" "${file}"
    cp -a "$file" "$backup" && log_success "${INSTALL_WATCHER:-BASH}" "install.fs.success" "${backup}"
}

ensure_directory() {
    local mode="700"
    local user="root"
    local group="root"
    local dirs=()

    while [ $# -gt 0 ]; do
        case "$1" in
            [0-9]*)
                mode="$1"
                shift
                break
                ;;
            *)
                dirs+=("$1")
                shift
                ;;
        esac
    done

    if [ $# -ge 1 ]; then
        user="$1"
    fi
    if [ $# -ge 2 ]; then
        group="$2"
    fi

    local dir effective_user effective_group
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        chmod "$mode" "$dir"

        effective_user="$user"
        effective_group="$group"

        if ! id -u "$effective_user" >/dev/null 2>&1; then
            effective_user="root"
        fi
        if ! getent group "$effective_group" >/dev/null 2>&1; then
            effective_group="root"
        fi

        chown "${effective_user}:${effective_group}" "$dir" 2>/dev/null || true
    done
}

check_user() {
    local user="$1"
    id "$user" >/dev/null 2>&1
}
