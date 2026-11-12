#!/usr/bin/env bash
# =============================================================================
# File       : core/check/test-harness.sh
# Updated at : 2026-11-07
# Creator    : palarchsys
# =============================================================================


locate_python_dir() {
    local dir hops=0
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -d "${dir}/share/python" ]]; then
            printf '%s\n' "${dir}/share/python"
            return 0
        fi
        if [[ -d "${dir}/python" ]]; then
            printf '%s\n' "${dir}/python"
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

t_get_timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

t_log() {
    local line="[$(t_get_timestamp)] $*"
    printf '%s\n' "$line"
    if [[ -n "${RUN_LOG:-}" ]]; then
        printf '%s\n' "$line" >> "${RUN_LOG}"
    fi
    if [[ -n "${T_SUITE_LOG:-}" ]]; then
        printf '%s\n' "$line" >> "${T_SUITE_LOG}"
    fi
}

t_record() {
    local status="$1"
    local id="$2"
    local msg="$3"
    printf '%s\t%s\t%s\n' "$status" "$id" "$msg" >> "${T_RESULT_TSV}"
}

t_pass() {
    T_PASS=$((T_PASS + 1))
    t_log "PASS  $1 — $2"
    t_record PASS "$1" "$2"
}

t_fail() {
    T_FAIL=$((T_FAIL + 1))
    t_log "FAIL  $1 — $2"
    t_record FAIL "$1" "$2"
}

t_warn() {
    T_WARN=$((T_WARN + 1))
    t_log "WARN  $1 — $2"
    t_record WARN "$1" "$2"
}

t_skip() {
    T_SKIP=$((T_SKIP + 1))
    t_log "SKIP  $1 — $2"
    t_record SKIP "$1" "$2"
}

t_section() {
    t_log ""
    t_log "── $1 ──"
}

t_check_command() { command -v "$1" >/dev/null 2>&1; }

t_load_project_config() {
    # shellcheck disable=SC1091
    set +u
    if [[ -f "${T_ROOT}/config/user.conf" ]]; then
        source "${T_ROOT}/config/user.conf"
    fi
    source "${T_ROOT}/config/global.conf"
    set -u
}

t_check_envsubst_leftover() {
    local file="$1"
    grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' "$file" 2>/dev/null | sort -u || true
}

t_begin() {
    local stamp
    stamp="$(date '+%Y%m%d-%H%M%S')"
    T_OUTPUT="${T_ROOT}/log/test/${stamp}"
    ARTIFACTS="${T_OUTPUT}/artifacts"
    T_SUITE_DIRECTORY="${T_OUTPUT}/suites"
    RUN_LOG="${T_OUTPUT}/run.log"
    T_RESULT_TSV="${T_OUTPUT}/results.tsv"
    mkdir -p "${ARTIFACTS}" "${T_SUITE_DIRECTORY}"
    : > "${RUN_LOG}"
    : > "${T_RESULT_TSV}"
    local language_line="" language_value="" language_file=""
    LANGUAGE="en"
    language_file="${T_ROOT}/config/global.conf"
    if [[ -f "${T_ROOT}/config/user.conf" ]] && grep -qE '^LANGUAGE=' -- "${T_ROOT}/config/user.conf"; then
        language_file="${T_ROOT}/config/user.conf"
    fi
    if [[ -f "${language_file}" ]]; then
        language_line="$(grep -E '^LANGUAGE=' -- "${language_file}" | head -n 1 || true)"
        language_value="${language_line#LANGUAGE=}"
        language_value="${language_value%\"}"
        language_value="${language_value#\"}"
        case "${language_value}" in
            en|fr|de|es) LANGUAGE="${language_value}" ;;
        esac
    fi
    export T_TEST_DIRECTORY T_ROOT T_OUTPUT ARTIFACTS T_SUITE_DIRECTORY RUN_LOG T_RESULT_TSV PROFILE LANGUAGE
    TOTAL_PASS=0
    TOTAL_FAIL=0
    TOTAL_WARN=0
    TOTAL_SKIP=0
    t_log "Liltress test run"
    t_log "root     : ${T_ROOT}"
    t_log "output   : ${T_OUTPUT}"
    t_log "profile  : ${PROFILE}"
    t_log "host     : $(hostname -s 2>/dev/null || hostname)"
    t_log ""
}

t_run_suite() {
    local suite suite_name
    for suite in "${T_TEST_DIRECTORY}/suites/"[0-9][0-9]_*.sh; do
        [[ -f "${suite}" ]] || continue
        suite_name="$(basename "${suite}" .sh)"
        export T_SUITE_LOG="${T_SUITE_DIRECTORY}/${suite_name}.log"
        : > "${T_SUITE_LOG}"
        T_PASS=0
        T_FAIL=0
        T_WARN=0
        T_SKIP=0
        t_log ""
        t_log "════════════════════════════════════════════════════════════════"
        t_log " SUITE ${suite_name}"
        t_log "════════════════════════════════════════════════════════════════"
        # shellcheck disable=SC1090
        source "${suite}"
        TOTAL_PASS=$((TOTAL_PASS + T_PASS))
        TOTAL_FAIL=$((TOTAL_FAIL + T_FAIL))
        TOTAL_WARN=$((TOTAL_WARN + T_WARN))
        TOTAL_SKIP=$((TOTAL_SKIP + T_SKIP))
        t_log "suite ${suite_name}: ${T_PASS} pass, ${T_FAIL} fail, ${T_WARN} warn, ${T_SKIP} skip"
    done
}

t_finish() {
    {
        echo "# Rapport de test"
        echo ""
        echo "$(get_text log.date "$(date -Iseconds)")"
        echo "$(get_text log.profile "${PROFILE}")"
        echo "$(get_text log.directory "${T_OUTPUT}")"
        echo "$(get_text log.repository "${T_ROOT}")"
        echo ""
        echo "$(get_text log.total)"
        echo ""
        echo "$(get_text log.pass-fail-warn-skip)"
        echo "|------|------|------|------|"
        echo "| ${TOTAL_PASS} | ${TOTAL_FAIL} | ${TOTAL_WARN} | ${TOTAL_SKIP} |"
        echo ""
        if [[ "${TOTAL_FAIL}" -eq 0 ]]; then
            echo "$(get_text log.result-ok-no-fail)"
        else
            echo "$(get_text log.result-ko-fail-to-fix-before-a-deployment "${TOTAL_FAIL}")"
        fi
        echo ""
        echo "$(get_text log.fail)"
        echo ""
        if grep -q '^FAIL' "${T_RESULT_TSV}"; then
            echo "$(get_text log.id-detail)"
            echo "|----|--------|"
            awk -F'\t' '$1=="FAIL"{printf "| `%s` | %s |\n", $2, $3}' "${T_RESULT_TSV}"
        else
            echo "$(get_text log.aucun)"
        fi
        echo ""
        echo "$(get_text log.warn)"
        echo ""
        if grep -q '^WARN' "${T_RESULT_TSV}"; then
            echo "$(get_text log.id-detail)"
            echo "|----|--------|"
            awk -F'\t' '$1=="WARN"{printf "| `%s` | %s |\n", $2, $3}' "${T_RESULT_TSV}"
        else
            echo "$(get_text log.aucun)"
        fi
        echo ""
        echo "$(get_text log.pass-preview)"
        echo ""
        echo "$(get_text log.see-results-tsv-and-suites-log-for-the-complete "${TOTAL_PASS}")"
        echo ""
        echo "$(get_text log.files)"
        echo ""
        echo "$(get_text log.combined-journal-run-log)"
        echo "$(get_text log.raw-results-results-tsv)"
        echo "$(get_text log.configs-sandbox-artifacts)"
    } > "${T_OUTPUT}/summary.md"

    python3 "$(locate_python_dir)/test-summary.py" "${T_OUTPUT}/summary.json" "${TOTAL_PASS}" "${TOTAL_FAIL}" "${TOTAL_WARN}" "${TOTAL_SKIP}" "${PROFILE}" "${T_RESULT_TSV}"

    t_log ""
    t_log "════════════════════════════════════════════════════════════════"
    t_log " TOTAL  pass=${TOTAL_PASS} fail=${TOTAL_FAIL} warn=${TOTAL_WARN} skip=${TOTAL_SKIP}"
    t_log " Rapport : ${T_OUTPUT}/summary.md"
    t_log "════════════════════════════════════════════════════════════════"
    if [[ "${TOTAL_FAIL}" -eq 0 ]]; then
        exit 0
    fi
    exit 1
}
