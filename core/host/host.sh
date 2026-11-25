#!/usr/bin/env bash
# =============================================================================
# File       : core/host/host.sh
# Updated at : 2026-11-25
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Open the account, ssh, and release scripts.
# -----------------------------------------------------------------------------


host_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${host_directory}/account.sh"
# shellcheck disable=SC1091
source "${host_directory}/ssh.sh"
# shellcheck disable=SC1091
source "${host_directory}/ubuntu.sh"
unset host_directory
