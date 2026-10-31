#!/usr/bin/env bash
# =============================================================================
# File       : test/suites/03_functions.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

t_section "fonctions conservées"
MONO="$(cd -- "${T_ROOT}/.." && pwd)"

t_require_function() {
    local name="$1"
    local where="$2"
    if grep -RInE "^${name}[[:space:]]*\\(\\)" ${where} >/dev/null 2>&1; then
        t_pass "fn:${name}" "présente"
    else
        t_fail "fn:${name}" "absente de ${where}"
    fi
}

for name in set_color_blue require_root set_step_visible log_error run_silent run_optional run_silent_apt run_step \
    add_line copy_backup ensure_directory check_user init_install_log \
    collect_install_log publish_repo_logs check_debug_log install_exit \
    copy_installed_logs; do
    t_require_function "${name}" "${MONO}/core"
done
for name in get_current_user get_operating_system check_ubuntu_base check_desktop_account write_account_table \
    record_account_snapshot strip_virt_groups check_account_drift read_sshd_value get_sshd_value get_ssh_port \
    check_virtual_machine check_app check_password_unchanged check_ubuntu_pro \
    collect_workstation_logs; do
    t_require_function "${name}" "${T_ROOT}/core/lib.sh"
done
for name in check_email check_port check_smtp check_absolute_path check_drive_remote check_drive_path check_drive_probe check_app_password; do
    t_require_function "${name}" "${MONO}/core/config-validators.sh"
done
t_require_function check_pro_token "${T_ROOT}/script/config-check.sh"
t_require_function check_localhost_port "${MONO}/server/core/lib.sh"

t_section "base ubuntu"
if bash -s -- "${T_ROOT}" << 'OSBASE'
set -euo pipefail
root="$1"
G_INSTALL_DIRECTORY="${root}"
# shellcheck disable=SC1091
source "${G_INSTALL_DIRECTORY}/core/lib.sh"
grep -q 'source /etc/os-release' "${G_INSTALL_DIRECTORY}/core/lib.sh"
grep -q 'dpkg --compare-versions' "${G_INSTALL_DIRECTORY}/core/lib.sh"
grep -q 'ge "26.04"' "${G_INSTALL_DIRECTORY}/core/lib.sh"
grep -q 'check_ubuntu_lts' "${G_INSTALL_DIRECTORY}/core/lib.sh"
grep -qF '!= "ubuntu"' "${G_INSTALL_DIRECTORY}/core/lib.sh"
if grep -q 'anduinos' "${G_INSTALL_DIRECTORY}/core/lib.sh"; then
    exit 1
fi

pass_os() {
    local ID="$1"
    local ID_LIKE="$2"
    local UBUNTU_CODENAME="$3"
    local PRETTY_NAME="$4"
    local VERSION_ID="${5:-}"
    local expect_version="$6"
    local expect_code="$7"
    unset UBUNTU_BASE_VERSION UBUNTU_BASE_CODENAME
    check_ubuntu_base
    [[ "${UBUNTU_BASE_VERSION}" == "${expect_version}" ]]
    [[ "${UBUNTU_BASE_CODENAME}" == "${expect_code}" ]]
}

fail_os() {
    local needle="$1"
    local id="$2"
    local like="$3"
    local code="$4"
    local pretty="$5"
    local version="${6:-}"
    local out rc
    set +e
    out=$(
        ID="${id}" ID_LIKE="${like}" UBUNTU_CODENAME="${code}" \
            PRETTY_NAME="${pretty}" VERSION_ID="${version}" \
            check_ubuntu_base 2>&1
    )
    rc=$?
    set -e
    [[ "${rc}" -ne 0 ]]
    printf '%s\n' "${out}" | grep -q '26.04'
    printf '%s\n' "${out}" | grep -qF "${needle}"
}

pass_os ubuntu debian resolute "Ubuntu 26.04 LTS" "26.04" 26.04 resolute
pass_os ubuntu debian resolute "Ubuntu 26.04.1 LTS" "26.04.1" 26.04 resolute
pass_os ubuntu debian stonking "Ubuntu 26.10" "26.10" 26.10 stonking
pass_os ubuntu debian later "Ubuntu 28.04 LTS" "28.04" 28.04 later
pass_os ubuntu debian "" "Ubuntu 26.04" "26.04" 26.04 inconnu
fail_os AnduinOS anduinos "" resolute "AnduinOS" "1.4"
fail_os "Linux Mint" linuxmint "ubuntu debian" resolute "Linux Mint" "22"
fail_os "Custom derivative" custom "" resolute "Custom derivative" ""
fail_os 25.10 ubuntu debian questing "Ubuntu 25.10" "25.10"
fail_os 24.04 ubuntu debian noble "Ubuntu 24.04 LTS" "24.04"
fail_os 22.04 ubuntu debian jammy "Ubuntu 22.04 LTS" "22.04"
fail_os aucune ubuntu debian "" "Ubuntu" ""
fail_os Fedora fedora fedora "" "Fedora" "42"
OSBASE
then
    t_pass "fn.os.base" "Ubuntu seul, 26.04 ou plus récent"
else
    t_fail "fn.os.base" "la base Ubuntu n'accepte pas 26.04 ou plus récent"
fi
if grep -q '!= "26.04"' "${T_ROOT}/core/lib.sh"; then
    t_fail "fn.os.strict" "la version est comparée par égalité stricte sur VERSION_ID"
else
    t_pass "fn.os.strict" "la version est comparée au plancher 26.04"
fi

t_section "sshd -T casse"
if bash -s -- "${T_ROOT}" << 'SSHCASE'
set -euo pipefail
root="$1"
G_INSTALL_DIRECTORY="${root}"
# shellcheck disable=SC1091
source "${G_INSTALL_DIRECTORY}/core/lib.sh"
canon=$'Port 22\nPermitRootLogin no\nPasswordAuthentication yes\nAllowTcpForwarding no\n'
lower=$'port 2222\npermitrootlogin no\npasswordauthentication yes\n'
[[ "$(printf '%s\n' "${canon}" | read_sshd_value permitrootlogin)" == "no" ]]
[[ "$(printf '%s\n' "${canon}" | read_sshd_value PermitRootLogin)" == "no" ]]
[[ "$(printf '%s\n' "${canon}" | read_sshd_value port)" == "22" ]]
[[ "$(printf '%s\n' "${lower}" | read_sshd_value port)" == "2222" ]]
[[ "$(printf '%s\n' "${lower}" | read_sshd_value permitrootlogin)" == "no" ]]
grep -q 'get_sshd_value permitrootlogin' "${root}/service/ssh/configure.sh"
grep -q 'get_sshd_value permitrootlogin' "${root}/../server/service/ssh/configure.sh"
grep -q 'get_sshd_value allowtcpforwarding' "${root}/verify/workstation.sh"
grep -q 'tolower($1)=="permitrootlogin"' "${root}/service/cron/boot-check.sh"
if grep -RInE "awk '/\\^permitrootlogin " "${root}/service" "${root}/verify" "${root}/../server/service" >/dev/null 2>&1; then
    exit 1
fi
SSHCASE
then
    t_pass "fn.sshd.case" "sshd -T lu en minuscules et en casse canonique"
else
    t_fail "fn.sshd.case" "la lecture de sshd -T reste figée en minuscules"
fi

t_section "journaux dans logs/"
if grep -q 'trap install_exit EXIT' "${T_ROOT}/script/run.sh" \
   && grep -q 'G_LOG_DIR="${root}/log/${name}"' "${MONO}/core/log.sh" \
   && grep -F -q '[[ "${code}" -ne 0 ]]' "${MONO}/core/log.sh"; then
    t_pass "logs.wire" "le poste écrit dans logs/ et copie les logiciels seulement en échec"
else
    t_fail "logs.wire" "journaux du poste encore hors de logs/, ou copie même en succès"
fi
t_require_function render_mail "${MONO}/core/mail.sh"
t_require_function install_mail_templates "${MONO}/core/mail.sh"

t_section "mode test du poste"
if grep -q '^G_MODE_TEST=1$' "${T_ROOT}/config/global.conf" \
   && ! grep -q '^S_SERVER_TYPE=' "${T_ROOT}/config/global.conf" \
   && grep -q '^G_MODE_TEST=${G_MODE_TEST}$' "${T_ROOT}/script/config-check.sh" \
   && ! grep -q 'S_SERVER_TYPE' "${T_ROOT}/script/config-check.sh" \
   && grep -q 'prompt G_MODE_TEST' "${T_ROOT}/script/configure.sh" \
   && grep -q 'bool01' "${T_ROOT}/script/configure.sh" \
   && ! grep -q 'S_SERVER_TYPE' "${T_ROOT}/script/run.sh" \
   && ! grep -RIn --include='*.sh' 'S_SERVER_TYPE' \
        "${T_ROOT}/system" "${T_ROOT}/service" "${T_ROOT}/verify" | grep -q . \
   && grep -q 'G_MODE_TEST:-0' "${MONO}/core/log.sh"; then
    t_pass "user.mode-test" "G_MODE_TEST=1, S_SERVER_TYPE absent du poste"
else
    t_fail "user.mode-test" "G_MODE_TEST ou S_SERVER_TYPE mal placé"
fi

stage="$(mktemp -d)"
if bash -c '
    set -euo pipefail
    # shellcheck disable=SC1090
    source "$1"
    set_config_default
    write_global_config "$2/global.conf"
    grep -q "^G_MODE_TEST=1$" "$2/global.conf"
    ! grep -q "^S_SERVER_TYPE=" "$2/global.conf"
' bash "${T_ROOT}/script/config-check.sh" "${stage}"; then
    t_pass "user.mode-test.write" "le fichier réécrit porte G_MODE_TEST=1, sans S_SERVER_TYPE"
else
    t_fail "user.mode-test.write" "la réécriture omet G_MODE_TEST ou garde S_SERVER_TYPE"
fi
rm -rf "${stage}"

tree="$(mktemp -d)"
cat > "${tree}/one.sh" << 'EOF'
#!/usr/bin/env bash
printf 'A:%s:%s:%s\n' "$1" "$2" "${3-}"
EOF
cat > "${tree}/two.sh" << 'EOF'
#!/usr/bin/env bash
printf 'B:%s:%s:%s\n' "$1" "$2" "${3-}"
EOF
out="$(G_PRODUCT_ROOT="${T_ROOT}" bash -c '
    set -euo pipefail
    unset S_SERVER_TYPE || true
    # shellcheck disable=SC1090
    source "$1"
    run_step "$2" "one.sh"
    run_step "$2" MATRIX "two.sh"
' bash "${T_ROOT}/core/lib.sh" "${tree}" 2>/dev/null)" || out=""
if [[ "${out}" == "A:BASH:${tree}:"$'\n'"B:BASH:${tree}:MATRIX" ]]; then
    t_pass "user.mode-test.steps" "le poste lance l'étape sans profil, le serveur garde le sien"
else
    t_fail "user.mode-test.steps" "arguments reçus : ${out}"
fi
rm -rf "${tree}"

log_work="$(mktemp -d)"
if G_PRODUCT_ROOT="${T_ROOT}" bash -c '
    set -euo pipefail
    unset S_SERVER_TYPE || true
    # shellcheck disable=SC1090
    source "$1"
    G_INSTALL_DIRECTORY="$2"
    export G_INSTALL_DIRECTORY
    W_PROJECT_SLUG=liltress-workstation
    G_PROJECT_NAME=HF
    unset UBUNTU_BASE_VERSION || true
    OS_PRETTY="Ubuntu"
    OS_VERSION_ID="26.10"
    export OS_PRETTY OS_VERSION_ID
    init_install_log
    [[ "${G_LOG_DIR}" == "${G_INSTALL_DIRECTORY}/log/install-"*"-workstation" ]]
    grep -Fqx "os          : Ubuntu 26.10" "${G_LOG_DIR}/meta.txt"
    grep -Fqx "os          : Ubuntu 26.10" "${G_LOG_DIR}/install.log"
    OS_PRETTY="Ubuntu 26.10"
    export OS_PRETTY
    init_install_log
    grep -Fqx "os          : Ubuntu 26.10" "${G_LOG_DIR}/meta.txt"
    ! grep -Fqx "os          : Ubuntu 26.10 26.10" "${G_LOG_DIR}/meta.txt"
' bash "${T_ROOT}/core/lib.sh" "${log_work}"; then
    t_pass "user.mode-test.logname" "journal nommé install-*-workstation, version de distribution écrite une fois"
else
    t_fail "user.mode-test.logname" "le journal du poste omet -user ou la version de distribution"
fi
rm -rf "${log_work}"

if timeout 3 bash -c '
    set -euo pipefail
    # shellcheck disable=SC1090
    source "$1"
    unset G_INSTALL_DIRECTORY || true
    # shellcheck disable=SC1090
    source "$2"
    [[ "${G_MODE_TEST}" == "1" ]]
    [[ -z "${S_SERVER_TYPE:-}" ]]
    work="$(mktemp -d)"
    trap "rm -rf -- \"${work}\"" EXIT
    mkdir -p "${work}/inst/script" "${work}/inst/config" "${work}/base"
    printf x > "${work}/inst/liltress"
    printf x > "${work}/inst/script/run.sh"
    printf C > "${work}/inst/config/global.conf"
    inst="$(cd -- "${work}/inst" && pwd -P)"
    base="$(cd -- "${work}/base" && pwd -P)"
    out="$(G_INSTALL_DIRECTORY="${inst}" G_CONFIG_BASE_DIRECTORY="${base}" offer_remove_installer 2>&1)"
    [[ "${out}" != *[Ss]upprimer* ]]
    [[ -f "${inst}/liltress" && -f "${inst}/config/global.conf" ]]
' bash "${MONO}/core/log.sh" "${T_ROOT}/config/global.conf"; then
    t_pass "user.mode-test.skip" "G_MODE_TEST=1 termine sans question"
else
    t_fail "user.mode-test.skip" "la question de suppression part encore"
fi
