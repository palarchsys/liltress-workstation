#!/usr/bin/env bash
# =============================================================================
# File       : script/install.sh
# Updated at : 2026-11-12
# Creator    : palarchsys
# =============================================================================

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/palarchsys/liltress-workstation}"
BRANCH="${BRANCH:-main}"

if [[ "${EUID}" -ne 0 ]]; then
    echo "$(get_text install.this-script-must-be-executed-as-root-sudo)" >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl ca-certificates tar git >/dev/null

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "$(get_text install.download-branch "${REPO_URL}" "${BRANCH}")"
mkdir -p "${tmp}/extract"
extracted=""
if git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" "${tmp}/extract/src"; then
    extracted="${tmp}/extract/src"
fi
if [[ -z "${extracted}" || ! -f "${extracted}/config/global.conf" ]]; then
    curl -fsSL "${REPO_URL}/archive/refs/heads/${BRANCH}.tar.gz" -o "${tmp}/src.tar.gz"
    tar -xzf "${tmp}/src.tar.gz" -C "${tmp}/extract"
    extracted="$(find "${tmp}/extract" -mindepth 1 -maxdepth 1 -type d | head -1)"
fi
if [[ -z "${extracted}" || ! -f "${extracted}/config/global.conf" ]]; then
    echo "$(get_text install.archive-github-invalid-config-global-conf-absent)" >&2
    exit 1
fi

config_base="$(
    unset INSTALL_DIRECTORY
    set +u
    # shellcheck disable=SC1091
    source "${extracted}/config/global.conf"
    printf '%s\n' "${CONFIG_BASE_DIRECTORY}"
)"
if [[ -z "${config_base}" || "${config_base}" != /opt/* || "${config_base}" == *..* || "${config_base}" == *[[:space:]]* ]]; then
    echo "$(get_text install.g-config-base-directory-invalid-in-global-conf "${config_base:-vide}")" >&2
    exit 1
fi
INSTALL_ROOT="${INSTALL_ROOT:-${config_base}}"
if [[ "${INSTALL_ROOT}" != /* || "${INSTALL_ROOT}" == "/" || "${INSTALL_ROOT}" == *..* || "${INSTALL_ROOT}" == *[[:space:]]* ]]; then
    echo "$(get_text install.root-of-install-rejected "${INSTALL_ROOT}")" >&2
    exit 1
fi

mkdir -p "${INSTALL_ROOT}"
keep=""
mkdir -p "${tmp}/keep"
if [[ -f "${INSTALL_ROOT}/config/global.conf" ]] && grep -q '^CONFIG_PREPARED=1$' "${INSTALL_ROOT}/config/global.conf" && [[ -f "${INSTALL_ROOT}/config/secrets.conf" ]]; then
    cp -a "${INSTALL_ROOT}/config/global.conf" "${INSTALL_ROOT}/config/secrets.conf" "${tmp}/keep/"
    keep=1
fi
skip_keep=""
if [[ -f "${INSTALL_ROOT}/config/clamav/scan-skip.paths" ]] && ! grep -q '__HOME__' "${INSTALL_ROOT}/config/clamav/scan-skip.paths"; then
    cp -a "${INSTALL_ROOT}/config/clamav/scan-skip.paths" "${tmp}/keep/scan-skip.paths"
    skip_keep=1
fi
if [[ "${skip_keep}" != "1" && -f "${INSTALL_ROOT}/src/config/clamav/scan-skip.paths" ]] && ! grep -q '__HOME__' "${INSTALL_ROOT}/src/config/clamav/scan-skip.paths"; then
    cp -a "${INSTALL_ROOT}/src/config/clamav/scan-skip.paths" "${tmp}/keep/scan-skip.paths"
    skip_keep=1
fi
for kept_name in docker secrets cron; do
    if [[ -d "${INSTALL_ROOT}/${kept_name}" ]]; then
        mv "${INSTALL_ROOT}/${kept_name}" "${tmp}/keep/${kept_name}"
    fi
done
legacy="${INSTALL_ROOT}/src"
if [[ -f "${legacy}/liltress" ]]; then
    if [[ "${keep}" != "1" && -f "${legacy}/config/global.conf" ]] && grep -q '^CONFIG_PREPARED=1$' "${legacy}/config/global.conf" && [[ -f "${legacy}/config/secrets.conf" ]]; then
        cp -a "${legacy}/config/global.conf" "${legacy}/config/secrets.conf" "${tmp}/keep/"
        keep=1
    fi
    for kept_name in docker secrets cron; do
        if [[ ! -d "${tmp}/keep/${kept_name}" && -d "${legacy}/${kept_name}" ]]; then
            mv "${legacy}/${kept_name}" "${tmp}/keep/${kept_name}"
        fi
    done
fi
rm -rf "${INSTALL_ROOT:?}"/*
cp -a "${extracted}/." "${INSTALL_ROOT}/"
if [[ "${keep}" == "1" ]]; then
    mkdir -p "${INSTALL_ROOT}/config"
    cp -a "${tmp}/keep/global.conf" "${tmp}/keep/secrets.conf" "${INSTALL_ROOT}/config/"
    chmod 600 "${INSTALL_ROOT}/config/secrets.conf" || true
fi
for kept_name in docker secrets cron; do
    if [[ -d "${tmp}/keep/${kept_name}" ]]; then
        rm -rf "${INSTALL_ROOT:?}/${kept_name:?}"
        mv "${tmp}/keep/${kept_name}" "${INSTALL_ROOT}/${kept_name}"
    fi
done
if [[ "${skip_keep}" == "1" ]]; then
    mkdir -p "${INSTALL_ROOT}/config/clamav"
    cp -a "${tmp}/keep/scan-skip.paths" "${INSTALL_ROOT}/config/clamav/scan-skip.paths"
    chmod 644 "${INSTALL_ROOT}/config/clamav/scan-skip.paths" || true
elif [[ -f "${config_base}/cron/scan-skip.paths" ]]; then
    if [[ ! -f "${INSTALL_ROOT}/config/clamav/scan-skip.paths" ]] || grep -q '__HOME__' "${INSTALL_ROOT}/config/clamav/scan-skip.paths"; then
        mkdir -p "${INSTALL_ROOT}/config/clamav"
        cp -a "${config_base}/cron/scan-skip.paths" "${INSTALL_ROOT}/config/clamav/scan-skip.paths"
        chmod 644 "${INSTALL_ROOT}/config/clamav/scan-skip.paths" || true
    fi
fi
if [[ ! -f "${INSTALL_ROOT}/liltress" ]]; then
    printf "$(get_text install.liltress-absent-after-extraction-n)" >&2
    exit 1
fi
chmod 755 "${INSTALL_ROOT}/liltress"

if [[ "${keep}" != "1" ]]; then
    printf "$(get_text install.nt-l-chargement-finished-the-sources-are-in-s-n)" "${INSTALL_ROOT}"
    printf "$(get_text install.launch-of-the-configuration-n-n)"
    exec bash "${INSTALL_ROOT}/script/configure.sh"
fi

if ! bash "${INSTALL_ROOT}/script/configure.sh" --check; then
    printf "$(get_text install.nla-configuration-saved-password-more-the-check)" >&2
    printf "$(get_text install.launch-of-the-questions-n-n)" >&2
    exec bash "${INSTALL_ROOT}/script/configure.sh"
fi

cd "${INSTALL_ROOT}"
exec bash "${INSTALL_ROOT}/script/run.sh"
