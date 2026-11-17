#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/watchdogs/send.sh
# Updated at : 2026-11-15
# Creator    : palarchsys
# =============================================================================


# -----------------------------------------------------------------------------
# Purpose    : Hand one alert message to the mail helper.
# -----------------------------------------------------------------------------


set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"
deliver_mail
