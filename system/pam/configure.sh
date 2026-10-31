#!/usr/bin/env bash
# =============================================================================
# File       : system/pam/configure.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

INSTALL_WATCHER="${1:-BASH}"
INSTALL_DIRECTORY="${2:-}"
export INSTALL_WATCHER INSTALL_DIRECTORY
G_INSTALL_DIRECTORY="${INSTALL_DIRECTORY}"
export G_INSTALL_DIRECTORY

source "${G_INSTALL_DIRECTORY}/core/lib.sh"
source "${G_INSTALL_DIRECTORY}/config/global.conf"
require_root

get_current_user
log_subtitle     "${INSTALL_WATCHER}" "configure.algorithm-of-the-passwords-lynis-auth-9229"
log_info         "${INSTALL_WATCHER}" "configure.configuration-of-encrypt-method-yescrypt-no-chpa"
if grep -q "^ENCRYPT_METHOD" /etc/login.defs; then
    sed -i 's/^ENCRYPT_METHOD.*/ENCRYPT_METHOD YESCRYPT/' /etc/login.defs
else
    echo "$(get_text configure.encrypt-method-yescrypt)" >> /etc/login.defs
fi
log_success      "${INSTALL_WATCHER}" "configure.yescrypt-for-the-new-hash-old-intact"
log_subtitle     "${INSTALL_WATCHER}" "configure.required-quality-lors-of-a-change-of-password"
log_info         "${INSTALL_WATCHER}" "configure.configuration-of-pwquality"
tee /etc/security/pwquality.conf > /dev/null << EOF
minlen = ${W_PAM_PASSWORD_MIN_LENGTH}
minclass = 3
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
retry = 3
EOF
log_success      "${INSTALL_WATCHER}" "configure.pwquality-configured-minlen-not-32-desktop-usabl" "${W_PAM_PASSWORD_MIN_LENGTH}"

if [[ -f /etc/pam.d/common-password ]] && ! grep -q "rounds=65536" /etc/pam.d/common-password; then
    sed -i 's/\(pam_unix\.so.*\)/\1 rounds=65536/' /etc/pam.d/common-password 2>/dev/null || true
fi

log_info         "${INSTALL_WATCHER}" "configure.configuration-of-pam-faillock-pam-auth-update-wi"
tee /etc/security/faillock.conf > /dev/null << EOF
deny = ${W_FAILLOCK_DENY}
unlock_time = ${W_FAILLOCK_UNLOCK}
fail_interval = ${W_FAILLOCK_FAIL_INTERVAL}
even_deny_root
root_unlock_time = ${W_FAILLOCK_UNLOCK}
EOF
sed -i '/pam_faillock\.so/d' /etc/pam.d/common-auth /etc/pam.d/common-account 2>/dev/null || true
install -m 644 "$(locate_config_file system/pam-configs/faillock)" /usr/share/pam-configs/faillock
install -m 644 "$(locate_config_file system/pam-configs/faillock-preauth)" /usr/share/pam-configs/faillock-preauth
export DEBIAN_FRONTEND=noninteractive
pam-auth-update --force

pam-auth-update --enable faillock faillock-preauth --force
log_success      "${INSTALL_WATCHER}" "configure.pam-faillock-configured"

log_info         "${INSTALL_WATCHER}" "configure.hardening-of-login-defs-umask-and-faillog-existi"
if ! grep -q "^UMASK" /etc/login.defs; then
    echo "$(get_text configure.umask-027)" >> /etc/login.defs
else
    sed -i 's/^#*UMASK.*/UMASK 027/' /etc/login.defs
fi
grep -q "^SHA_CRYPT_MIN_ROUNDS" /etc/login.defs || echo "$(get_text configure.sha-crypt-min-rounds-65536)" >> /etc/login.defs
grep -q "^SHA_CRYPT_MAX_ROUNDS" /etc/login.defs || echo "$(get_text configure.sha-crypt-max-rounds-65536)" >> /etc/login.defs
sed -i 's/^#*FAILLOG_ENAB.*/FAILLOG_ENAB yes/' /etc/login.defs
grep -q "^FAILLOG_ENAB" /etc/login.defs || echo "$(get_text configure.faillog-enab-yes)" >> /etc/login.defs

log_success      "${INSTALL_WATCHER}" "configure.login-hardened-defs-no-chage-on-root" "${CURRENT_USER}"

log_info         "${INSTALL_WATCHER}" "configure.configuration-of-the-umask-027-no-tmout-on-the-t"
if ! grep -q "^umask" /etc/profile; then
    echo "$(get_text configure.umask-027-2)" >> /etc/profile
else
    sed -i 's/^#*umask.*/umask 027/' /etc/profile
fi
if ! grep -q "^umask" /etc/bash.bashrc; then
    echo "$(get_text configure.umask-027-2)" >> /etc/bash.bashrc
else
    sed -i 's/^#*umask.*/umask 027/' /etc/bash.bashrc
fi
tee /etc/profile.d/hardening.sh > /dev/null << EOF
umask 027
EOF
chmod 644 /etc/profile.d/hardening.sh
log_success      "${INSTALL_WATCHER}" "configure.umask-027-applied"

log_info         "${INSTALL_WATCHER}" "configure.configuration-of-the-sudoers-umask-0022-apt-not"

install -d -m 755 /etc/sudoers.d
cat > /etc/sudoers.d/liltress-workstation-umask << 'EOF'
Defaults umask=0022
Defaults umask_override
EOF
chmod 440 /etc/sudoers.d/liltress-workstation-umask
if ! visudo -cf /etc/sudoers.d/liltress-workstation-umask >/dev/null; then
    rm -f /etc/sudoers.d/liltress-workstation-umask
    log_error        "${INSTALL_WATCHER}" "configure.sudoers-umask-invalid-file-removed"
fi
log_success      "${INSTALL_WATCHER}" "configure.sudoers-installed-umask-0022-for-apt-and-the-too"

log_info         "${INSTALL_WATCHER}" "configure.memory-sudo-of-5-minutes"
cat > /etc/sudoers.d/liltress-workstation-timeout << 'EOF'
Defaults timestamp_timeout=5
EOF
chmod 440 /etc/sudoers.d/liltress-workstation-timeout
if ! visudo -cf /etc/sudoers.d/liltress-workstation-timeout >/dev/null; then
    rm -f /etc/sudoers.d/liltress-workstation-timeout
    log_error        "${INSTALL_WATCHER}" "configure.sudoers-timeout-invalid-file-removed"
fi
log_success      "${INSTALL_WATCHER}" "configure.sudo-asks-again-the-password-after-5-minutes"
