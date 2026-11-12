#!/usr/bin/env bash
# =============================================================================
# File       : script/test/suites/06_sql_contract.sh
# Updated at : 2026-10-28
# Creator    : palarchsys
# =============================================================================

t_section "contrat SQL"
root=""
here="${T_ROOT}"
while [[ "${here}" != "/" ]]; do
    if [[ -f "${here}/agents/laws/server.md" ]]; then
        root="${here}"
        break
    fi
    here="$(dirname -- "${here}")"
done

sql_server=""
sql_web=""
law=""
if [[ -n "${root}" ]]; then
    sql_server="${root}/server/docker/web/sql/001_tables.sql"
    sql_web="${root}/web/backend/app/db/sql/001_tables.sql"
    law="${root}/agents/laws/server.md"
fi

if [[ -z "${root}" ]]; then
    t_fail "sql.contract" "agents/laws/server.md introuvable au-dessus du produit"
elif [[ -f "${sql_server}" || -f "${sql_web}" ]]; then
    t_fail "sql.contract" "001_tables.sql est revenu dans server ou web"
elif ! grep -qF 'liltress-web' "${law}" \
    || ! grep -qF 'ne crée pas les tables' "${law}"; then
    t_fail "sql.contract" "la loi serveur doit laisser les tables à liltress-web"
else
    t_pass "sql.contract" "tables générées par liltress-web, aucune copie dans server ni web"
fi
