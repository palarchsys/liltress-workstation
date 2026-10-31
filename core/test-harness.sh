#!/usr/bin/env bash
# =============================================================================
# File       : core/test-harness.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

t_get_timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

t_log() {
    local line="[$(t_get_timestamp)] $*"
    printf '%s\n' "$line"
    if [[ -n "${G_RUN_LOG:-}" ]]; then
        printf '%s\n' "$line" >> "${G_RUN_LOG}"
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
    T_OUTPUT="${T_TEST_DIRECTORY}/output/${stamp}"
    G_ARTIFACTS="${T_OUTPUT}/artifacts"
    T_SUITE_DIRECTORY="${T_OUTPUT}/suites"
    G_RUN_LOG="${T_OUTPUT}/run.log"
    T_RESULT_TSV="${T_OUTPUT}/results.tsv"
    mkdir -p "${G_ARTIFACTS}" "${T_SUITE_DIRECTORY}"
    : > "${G_RUN_LOG}"
    : > "${T_RESULT_TSV}"
    local language_line="" language_value=""
    G_LANGUAGE="en"
    if [[ -f "${T_ROOT}/config/global.conf" ]]; then
        language_line="$(grep -E '^G_LANGUAGE=' -- "${T_ROOT}/config/global.conf" | head -n 1 || true)"
        language_value="${language_line#G_LANGUAGE=}"
        language_value="${language_value%\"}"
        language_value="${language_value#\"}"
        case "${language_value}" in
            en|fr|de|es) G_LANGUAGE="${language_value}" ;;
        esac
    fi
    export T_TEST_DIRECTORY T_ROOT T_OUTPUT G_ARTIFACTS T_SUITE_DIRECTORY G_RUN_LOG T_RESULT_TSV PROFILE G_LANGUAGE
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
    local suite g_suite_name
    for suite in "${T_TEST_DIRECTORY}/suites/"[0-9][0-9]_*.sh; do
        [[ -f "${suite}" ]] || continue
        g_suite_name="$(basename "${suite}" .sh)"
        export T_SUITE_LOG="${T_SUITE_DIRECTORY}/${g_suite_name}.log"
        : > "${T_SUITE_LOG}"
        T_PASS=0
        T_FAIL=0
        T_WARN=0
        T_SKIP=0
        t_log ""
        t_log "════════════════════════════════════════════════════════════════"
        t_log " SUITE ${g_suite_name}"
        t_log "════════════════════════════════════════════════════════════════"
        # shellcheck disable=SC1090
        source "${suite}"
        TOTAL_PASS=$((TOTAL_PASS + T_PASS))
        TOTAL_FAIL=$((TOTAL_FAIL + T_FAIL))
        TOTAL_WARN=$((TOTAL_WARN + T_WARN))
        TOTAL_SKIP=$((TOTAL_SKIP + T_SKIP))
        t_log "suite ${g_suite_name}: ${T_PASS} pass, ${T_FAIL} fail, ${T_WARN} warn, ${T_SKIP} skip"
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

    python3 - "${T_OUTPUT}/summary.json" "${TOTAL_PASS}" "${TOTAL_FAIL}" "${TOTAL_WARN}" "${TOTAL_SKIP}" "${PROFILE}" "${T_RESULT_TSV}" << 'PY'
import json, sys
out, p, f, w, s, profile, tsv = sys.argv[1:8]
items = []
with open(tsv, encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        status, ident, msg = line.split("\t", 2)
        items.append({"status": status, "id": ident, "message": msg})
payload = {
    "profile": profile,
    "pass": int(p),
    "fail": int(f),
    "warn": int(w),
    "skip": int(s),
    "ok": int(f) == 0,
    "results": items,
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY

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
