#!/usr/bin/env bash
# =============================================================================
# File       : test/suites/08_mail.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

t_section "modèle éditable"
MONO="$(cd -- "${T_ROOT}/.." && pwd)"
mail_sh="${MONO}/core/mail.sh"
tpl="${T_ROOT}/template/mail.html"

if grep -q '^G_MAIL_TEMPLATE="mail.html"$' "${T_ROOT}/config/global.conf" \
   && grep -q 'install_mail_templates' "${T_ROOT}/service/cron/configure.sh" \
   && grep -q 'deliver_mail' "${T_ROOT}/service/cron/watchdogs/send.sh" \
   && grep -q 'render_mail' "${MONO}/core/watchdog.sh" \
   && grep -q 'core/watchdog.sh' "${T_ROOT}/service/cron/configure.sh" \
   && ! grep -q 'G_MAIL_REDACT=1' "${T_ROOT}/service/cron/watchdogs/send.sh" \
   && grep -q 'NOTE_CMD' "${tpl}" \
   && grep -q '<!--NOTE_START-->' "${tpl}" \
   && grep -q '<!--NOTE_END-->' "${tpl}" \
   && grep -q '<!--ADVICE_START-->' "${tpl}" \
   && grep -q 'alert-advice.txt' "${T_ROOT}/service/cron/configure.sh"; then
    t_pass "mail.wired" "template/mail.html, copie à l'install, rendu sans masquage des identifiants"
else
    t_fail "mail.wired" "le poste doit rendre template/mail.html via core/mail.sh"
fi

# shellcheck disable=SC1090
source "${mail_sh}"
stage="$(mktemp -d)"
mkdir -p "${stage}/template" "${stage}/dest"
printf '<pre>${CONTENT}</pre>\n' > "${stage}/template/mail.html"
printf '<pre>autre</pre>\n' > "${stage}/template/autre.html"
if G_INSTALL_DIRECTORY="${stage}" G_MAIL_TEMPLATE="autre.html" install_mail_templates "${stage}/dest" \
   && [[ -f "${stage}/dest/mail.html" && -f "${stage}/dest/autre.html" ]] \
   && grep -q 'autre' "${stage}/dest/autre.html"; then
    t_pass "mail.install-many" "tous les .html de template/ sont copiés"
else
    t_fail "mail.install-many" "la copie des modèles a échoué"
fi
mkdir -p "${stage}/dest-e"

if G_INSTALL_DIRECTORY="${stage}" G_MAIL_TEMPLATE="mail.html" bash -c '
    set -euo pipefail
    # shellcheck disable=SC1090
    source "$1"
    install_mail_templates "$2"
' bash "${mail_sh}" "${stage}/dest-e" \
   && [[ -f "${stage}/dest-e/mail.html" ]]; then
    t_pass "mail.install-set-e" "la copie survit à set -e quand nullglob est inactif"
else
    t_fail "mail.install-set-e" "la copie quitte sous set -e sans écrire le modèle"
fi
rm -rf "${stage}"

export TITLE="Essai" G_PROJECT_NAME="Liltress Workstation" HOSTNAME="poste" DATE="2026-01-01" MODULE_NAME="Test"
export CONTENT='<script>$HOME'
export NOTE="" NOTE_CMD=""
unset ADVICE || true
unset G_MAIL_REDACT || true
if rendered="$(render_mail "${tpl}")" \
   && printf '%s' "${rendered}" | grep -q '<pre' \
   && printf '%s' "${rendered}" | grep -q '&lt;script&gt;\$HOME' \
   && ! printf '%s' "${rendered}" | grep -q '<!--NOTE_START-->' \
   && ! printf '%s' "${rendered}" | grep -q '<!--ADVICE_START-->' \
   && ! printf '%s' "${rendered}" | grep -Fq '${ADVICE}'; then
    t_pass "mail.render" "échappement HTML et bloc note retiré"
else
    t_fail "mail.render" "le rendu du modèle poste est invalide"
fi

export NOTE="voir le journal" NOTE_CMD="sudo true"
if rendered="$(render_mail "${tpl}")" \
   && printf '%s' "${rendered}" | grep -q 'voir le journal' \
   && printf '%s' "${rendered}" | grep -q 'sudo true' \
   && ! printf '%s' "${rendered}" | grep -q '<!--ADVICE_START-->'; then
    t_pass "mail.note" "NOTE et NOTE_CMD sont insérés"
else
    t_fail "mail.note" "le second bloc du modèle n'est pas rendu"
fi

export ADVICE="commande snap info"
if rendered="$(render_mail "${tpl}")" \
   && advice_at="$(printf '%s\n' "${rendered}" | grep -n 'commande snap info' | head -n 1 | cut -d: -f1)" \
   && cmd_at="$(printf '%s\n' "${rendered}" | grep -n 'sudo true' | head -n 1 | cut -d: -f1)" \
   && [[ -n "${advice_at}" && -n "${cmd_at}" && "${advice_at}" -lt "${cmd_at}" ]] \
   && ! printf '%s' "${rendered}" | grep -Fq '${ADVICE}'; then
    t_pass "mail.advice" "le bloc de vérification précède la commande finale"
else
    t_fail "mail.advice" "le conseil n'est pas avant la commande finale"
fi
unset ADVICE || true
