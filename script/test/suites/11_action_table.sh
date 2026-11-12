#!/usr/bin/env bash
# =============================================================================
# File       : script/test/suites/11_action_table.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

t_section "table d'actions"

MONO="$(cd -- "${T_ROOT}/.." && pwd)"
work="$(mktemp -d)"
# shellcheck disable=SC1091
source "${MONO}/share/core/watchdog/decide.sh"
printf '%s\n' 'added: /etc/ld.so.preload' > "${work}/aide-hold.log"
printf '%s\n' 'Unpacking libc6' > "${work}/apt.log"
: > "${work}/dpkg.log"
: > "${work}/repair"
mkdir -p "${work}/state"
status="$(check_watchdog_phase integrity "${work}/aide-hold.log" 0 "${work}/repair" "${work}/state" "${work}/apt.log" "${work}/dpkg.log")"
if [[ "${status}" == "real" && -f "${work}/state/actions.tsv" ]]; then
    t_pass "action.hold" "un cas hold=1 n'est pas un faux positif apt"
else
    t_fail "action.hold" "statut ${status}"
fi

# shellcheck disable=SC1091
source "${MONO}/share/core/watchdog/remedy.sh"
printf '0\t0\tfile\taide\t-\t/etc/foo\taide\taide.systemd\n' > "${work}/rows.tsv"
# The stub stays in this subshell. t_finish still calls the catalog get_text.
(
    get_text() { printf 'Repair failed: %s' "${2:-}"; }
    reinstall_watchdog_package() { return 1; }
    apply_watchdog_remedy integrity "${work}"
)
if grep -q 'Repair failed: aide' "${work}/actions.txt"; then
    t_fail "action.repair" "Repair failed: aide est encore écrit"
else
    t_pass "action.repair" "aucun Repair failed sans paquet"
fi
rm -rf "${work}"
