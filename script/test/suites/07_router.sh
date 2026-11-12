#!/usr/bin/env bash
# =============================================================================
# File       : script/test/suites/07_router.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================


locate_python_dir() {
    local dir hops=0 candidate
    for candidate in \
        "${CONFIG_BASE_DIRECTORY:-}/python" \
        "${BASE:-}/python" \
        "${INSTALL_DIRECTORY:-}/python" \
        "${INSTALL_DIRECTORY:-}/../share/python"
    do
        if [[ -n "${candidate}" && -d "${candidate}" ]]; then
            (cd -- "${candidate}" && pwd -P)
            return 0
        fi
    done
    dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "${hops}" -lt 8 && "${dir}" != "/" ]]; do
        if [[ -d "${dir}/share/python" ]]; then
            printf '%s\n' "${dir}/share/python"
            return 0
        fi
        if [[ -d "${dir}/python" ]]; then
            (cd -- "${dir}/python" && pwd -P)
            return 0
        fi
        dir="$(dirname -- "${dir}")"
        hops=$((hops + 1))
    done
    printf '%s\n' "dossier python introuvable" >&2
    return 1
}

t_section "routeur"
root=""
here="${T_ROOT}"
while [[ "${here}" != "/" ]]; do
    if [[ -f "${here}/agents/route.sh" ]]; then
        root="${here}"
        break
    fi
    here="$(dirname -- "${here}")"
done

if [[ -z "${root}" ]]; then
    t_fail "route.check" "agents/route.sh introuvable au-dessus de ${T_ROOT}"
elif bash "${root}/agents/route.sh" --check > "${ARTIFACTS}/route.txt"; then
    t_pass "route.check" "fichiers cités présents"
else
    t_fail "route.check" "$(tr '\n' ' ' < "${ARTIFACTS}/route.txt")"
fi

if [[ -n "${root}" ]] && python3 "$(locate_python_dir)/check-commands.py" csv "${root}/agents/maps/commands.csv" "${root}/share/core/run/launch.sh" > "${ARTIFACTS}/commands.txt" 2>&1
then
    t_pass "commands.csv" "liste alignée sur les commandes"
else
    t_fail "commands.csv" "$(tr '\n' ' ' < "${ARTIFACTS}/commands.txt" 2>/dev/null || true)"
fi

if [[ -n "${root}" ]]; then
    t_check_route() {
        local id="$1"
        local query="$2"
        local expect="$3"
        local got
        got="$(bash "${root}/agents/route.sh" "${query}")"
        if [[ "${got}" == "${expect}" ]]; then
            t_pass "route.${id}" "${query}"
        else
            t_fail "route.${id}" "${got}"
        fi
    }

    t_check_route history "historique version antérieure" $'agents/laws/history.md\nagents/laws/style.md'
    t_check_route tests "test" "agents/maps/tests.md"
    t_check_route probe "anomalie sonde" $'agents/laws/logs.md\nagents/maps/probe.md'
    t_check_route install "installeur" $'agents/laws/install.md\nagents/maps/core.md'
    t_check_route git.gitignore "gitignore" "agents/laws/git.md"
    t_check_route names.inventaire "inventaire des noms" $'agents/laws/names.md\nagents/maps/names.md'
    t_check_route names.keep-variable "variable" "agents/laws/naming.md"
    t_check_route compat.postfix "compatibilité postfix" $'agents/laws/compat.md\nagents/maps/versions.md'
    t_check_route compat.sasl "sasl 26.10" $'agents/laws/compat.md\nagents/maps/versions.md'
    t_check_route compat.esm "esm-infra" $'agents/laws/compat.md\nagents/maps/versions.md'
    t_check_route watchdog "watchdog" $'agents/laws/watchdog.md\nagents/maps/watchdog.md'
    t_check_route mail "mail" $'agents/laws/mail.md\nagents/maps/core.md'
    t_check_route parallel "parallèle" $'agents/laws/parallel.md\nagents/maps/owners.md'

    core_gap=""
    while IFS= read -r core_file; do
        core_name="$(basename -- "${core_file}")"
        if ! grep -q "/${core_name}" "${root}/agents/maps/core.md"; then
            core_gap="${core_gap} ${core_name}"
        fi
    done < <(find "${root}/share/core" -name '*.sh' -type f | sort)
    if [[ -z "${core_gap}" ]]; then
        t_pass "route.core.files" "chaque script de share/core est dans l'index"
    else
        t_fail "route.core.files" "absents de core.md :${core_gap}"
    fi

    suite_gap=""
    while IFS= read -r suite_file; do
        suite_rel="${suite_file#"${root}/"}"
        if ! grep -q "${suite_rel}" "${root}/agents/maps/tests.md"; then
            suite_gap="${suite_gap} ${suite_rel}"
        fi
    done < <(find "${root}/workstation/script/test/suites" "${root}/server/script/test/suites" -name '[0-9][0-9]_*.sh' -type f | sort)
    if [[ -z "${suite_gap}" ]]; then
        t_pass "route.tests.files" "chaque suite est dans l'index"
    else
        t_fail "route.tests.files" "absentes de tests.md :${suite_gap}"
    fi

    help_user="$(bash "${root}/workstation/liltress" help)"
    help_server="$(bash "${root}/server/liltress" help)"
    if [[ "${help_user}" == *"script/verify/workstation.sh"* && "${help_user}" == *"/opt/liltress-workstation/script/scan-skip.sh"* && "${help_user}" != *"--basic"* ]]; then
        t_pass "help.user" "commandes du poste"
    else
        t_fail "help.user" "écran poste incomplet"
    fi
    if [[ "${help_server}" == *"--basic"* && "${help_server}" == *"--avance"* && "${help_server}" == *"script/verify/matrix.sh"* && "${help_server}" != *"scan-skip"* ]]; then
        t_pass "help.server" "commandes du serveur"
    else
        t_fail "help.server" "écran serveur incomplet"
    fi

    if python3 "$(locate_python_dir)/check-commands.py" order "${root}" > "${ARTIFACTS}/order.txt" 2>&1
    then
        t_pass "order.maps" "tableaux alignés sur le plan d'installation"
    else
        t_fail "order.maps" "$(tr '\n' ' ' < "${ARTIFACTS}/order.txt" 2>/dev/null || true)"
    fi

    if bash "${root}/scripts/render-install.sh" --print workstation | cmp -s - "${root}/workstation/script/install.sh" \
        && bash "${root}/scripts/render-install.sh" --print server | cmp -s - "${root}/server/script/install.sh" \
        && bash "${root}/scripts/render-install.sh" --print workstation | grep -q 'liltress-workstation' \
        && bash "${root}/scripts/render-install.sh" --print workstation | grep -q 'scan-skip.paths' \
        && bash "${root}/scripts/render-install.sh" --print server | grep -q 'liltress-server' \
        && ! bash "${root}/scripts/render-install.sh" --print server | grep -q 'scan-skip.paths'
    then
        t_pass "install.template" "rendu égal aux deux install.sh"
    else
        t_fail "install.template" "le rendu diffère du fichier"
    fi

    if bash "${root}/agents/search.sh" render_install | grep -q 'scripts/render-install.sh'; then
        t_pass "search.hit" "motif trouvé"
    else
        t_fail "search.hit" "render-install.sh absent du résultat"
    fi
    status=0
    bash "${root}/agents/search.sh" >/dev/null 2>&1 || status=$?
    if [[ "${status}" -eq 2 ]]; then
        t_pass "search.usage" "sans motif, code 2"
    else
        t_fail "search.usage" "code ${status}"
    fi
    scope="$(bash "${root}/agents/search.sh" gold_gaming_trophy.png || true)"
    if [[ "${scope}" == *next_step* ]]; then
        t_fail "search.scope" "next_step est dans le résultat"
    else
        t_pass "search.scope" "next_step hors recherche"
    fi
fi
