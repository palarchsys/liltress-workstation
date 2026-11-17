#!/usr/bin/env bash
# =============================================================================
# File       : core/host/host.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Open the account, ssh, and release scripts.
# -----------------------------------------------------------------------------


host_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${host_dir}/account.sh"
# shellcheck disable=SC1091
source "${host_dir}/ssh.sh"
# shellcheck disable=SC1091
source "${host_dir}/ubuntu.sh"
unset host_dir
