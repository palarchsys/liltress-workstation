#!/usr/bin/env bash
# =============================================================================
# File       : core/log/step.sh
# Updated at : 2026-11-11
# Creator    : palarchsys
# =============================================================================


cut_text() {
    local text="$1"
    local max="${2:-74}"
    local n="${#text}"
    if (( max < 2 || n <= max )); then
        printf '%s' "${text}"
        return 0
    fi
    printf '%s…' "${text:0:$((max - 1))}"
}

repeat_char() {
    local char="$1"
    local count="$2"
    local out="" i=0
    while (( i < count )); do
        out+="${char}"
        i=$((i + 1))
    done
    printf '%s' "${out}"
}

show_title_box() {
    local title
    title="$(cut_text "$1" 74)"
    local top mid bot pad
    top="╭$(repeat_char "─" 92)╮"
    pad=$((90 - ${#title}))
    (( pad < 0 )) && pad=0
    mid="│  ${title}$(repeat_char " " "${pad}")│"
    bot="╰$(repeat_char "─" 92)╯"
    set_color_yellow "${top}"
    set_color_yellow "${mid}"
    set_color_yellow "${bot}"
}

show_section_open() {
    local title dashes line
    title="$(cut_text "$1" 70)"
    dashes=$((89 - ${#title}))
    (( dashes < 1 )) && dashes=1
    line="╭─ ${title} $(repeat_char "─" "${dashes}")╮"
    set_color_yellow "${line}"
    set_color_yellow "│"
    SECTION_OPEN=1
    SECTION_HAD_STEP=0
    export SECTION_OPEN SECTION_HAD_STEP
}

show_section_close() {
    [[ "${SECTION_OPEN:-0}" == "1" ]] || return 0
    set_color_yellow "│"
    set_color_yellow "╰$(repeat_char "─" 92)╯"
    printf '\n' >&2
    SECTION_OPEN=0
    SECTION_HAD_STEP=0
    export SECTION_OPEN SECTION_HAD_STEP
}

paint_note() {
    local kind="$1"
    local text="$2"
    text="$(shorten_logs_paths "${text}")"
    local max=74
    if [[ "${kind}" == "error" || "${kind}" == "fault" ]]; then
        max=160
    fi
    text="$(cut_text "${text}" "${max}")"
    case "${kind}" in
        info|debug) printf '\e[34m•\e[0m %s' "${text}" ;;
        success)    printf '\e[32m✓\e[0m %s' "${text}" ;;
        warn)       printf '\e[38;5;208m⚠\e[0m %s' "${text}" ;;
        *)          printf '\e[31m✗\e[0m %s' "${text}" ;;
    esac
}

step_bar() {
    if [[ "${SECTION_OPEN:-0}" == "1" ]]; then
        printf '\e[33m│\e[0m  '
    else
        printf '   '
    fi
}

section_gap() {
    if [[ "${SECTION_OPEN:-0}" == "1" ]]; then
        printf '\e[33m│\e[0m\n' >&2
    else
        printf '\n' >&2
    fi
}

step_flush_branch() {
    [[ -n "${STEP_PENDING:-}" ]] || return 0
    printf '%s├── %s\n' "$(step_bar)" "${STEP_PENDING}" >&2
    STEP_PENDING=""
}

open_step_tree() {
    local label
    close_step_tree
    if [[ "${SECTION_OPEN:-0}" == "1" && "${SECTION_HAD_STEP:-0}" == "1" ]]; then
        section_gap
    fi
    label="$(cut_text "$1" 74)"
    STEP_TREE=1
    STEP_PENDING=""
    printf '%s┌ \e[33m%s\e[0m\n' "$(step_bar)" "${label}" >&2
}

mark_section_step() {
    [[ "${SECTION_OPEN:-0}" == "1" ]] || return 0
    SECTION_HAD_STEP=1
    export SECTION_HAD_STEP
}

close_step_tree() {
    [[ "${STEP_TREE:-0}" == "1" ]] || return 0
    if [[ -n "${STEP_PENDING:-}" ]]; then
        printf '%s└── %s\n' "$(step_bar)" "${STEP_PENDING}" >&2
    fi
    STEP_TREE=0
    STEP_PENDING=""
}

show_closing_note() {
    local title="$1"
    local text="$2"
    text="$(shorten_logs_paths "${text}")"
    printf '  ┌ \e[33m%s\e[0m\n' "$(cut_text "${title}" 74)" >&2
    printf '  └── \e[34m•\e[0m %s\n' "$(cut_text "${text}" 74)" >&2
    printf '\n' >&2
}

show_closing_command() {
    local title="$1"
    local command="$2"
    printf '  ┌ \e[33m%s\e[0m\n' "$(cut_text "${title}" 74)" >&2
    printf '  └── \e[34m•\e[0m %s\n' "${command}" >&2
    printf '\n' >&2
}

note_bash() {
    local kind="$1"
    local text="$2"
    local rendered
    rendered="$(paint_note "${kind}" "${text}")"
    if [[ "${STEP_TREE:-0}" == "1" ]]; then
        if [[ "${kind}" == "error" ]]; then
            step_flush_branch
            printf '%s└── %s\n' "$(step_bar)" "${rendered}" >&2
            STEP_TREE=0
            STEP_PENDING=""
            return 0
        fi
        step_flush_branch
        STEP_PENDING="${rendered}"
        return 0
    fi
    printf '  %s\n' "${rendered}" >&2
}

get_fit_width() {
    local text="$1"
    local max="${2:-62}"
    local n="${#text}"
    if (( max < 4 || n <= max )); then
        if (( n > max && max > 0 )); then
            printf '%s' "${text:0:max}"
            return 0
        fi
        printf '%s' "$text"
        return 0
    fi
    printf '%s...' "${text:0:$((max - 3))}"
}

show_path() {
    local p="$1"
    case "$p" in
        /var/log|/var/log/*)
            printf '%s' "$p"
            ;;
        */log|*/log/*)
            printf '%s' "log${p#*/log}"
            ;;
        *)
            printf '%s' "$p"
            ;;
    esac
}

shorten_logs_paths() {
    local rest="$1"
    local out="" pre path
    while [[ "$rest" == *"/log"* ]]; do
        pre="${rest%%/log*}"
        rest="${rest#*/log}"
        if [[ "$pre" == "/var" || "$pre" == */var ]]; then
            out+="${pre}/log"
            continue
        fi
        if [[ "$pre" =~ ^(.*[^/[:alnum:]._+~-])(/[[:alnum:]._+~/-]*)$ ]]; then
            out+="${BASH_REMATCH[1]}"
        elif [[ "$pre" == /* ]]; then
            :
        else
            out+="$pre"
        fi
        path="log"
        if [[ "$rest" =~ ^(/[[:alnum:]._+~/-]*) ]]; then
            path+="${BASH_REMATCH[1]}"
            rest="${rest:${#BASH_REMATCH[1]}}"
        fi
        out+="$path"
    done
    printf '%s%s' "$out" "$rest"
}
