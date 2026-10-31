#!/usr/bin/env bash
# =============================================================================
# File       : service/cron/scan-skip.sh
# Updated at : 2026-10-31
# Creator    : palarchsys
# =============================================================================

set -euo pipefail
W_BASE="${W_BASE:-/opt/liltress-workstation}"
# shellcheck disable=SC1091
source "${W_BASE}/cron/bin/scan-skip-lib.sh"

show_usage() {
    printf "$(get_text log.usage-sudo-bash-bin-scan-skip-sh-list "${W_BASE}")" >&2
    printf "$(get_text log.sudo-bash-bin-scan-skip-sh-add-chemin "${W_BASE}")" >&2
    printf "$(get_text log.sudo-bash-bin-scan-skip-sh-del-chemin "${W_BASE}")" >&2
}

if [[ "${EUID}" -ne 0 ]]; then
    printf "$(get_text log.run-this-command-with-sudo-n)" >&2
    exit 1
fi

action="${1:-}"
case "${action}" in
    list|add|del) ;;
    *)
        show_usage
        exit 1
        ;;
esac

if [[ ! -f "${W_SCAN_SKIP_FILE}" ]]; then
    printf "$(get_text log.file-absent "${W_SCAN_SKIP_FILE}")" >&2
    exit 1
fi

if [[ "${action}" == "list" ]]; then
    collect_scan_skip_path
    if [[ ${#W_SCAN_SKIP_VALID[@]} -gt 0 ]]; then
        printf '%s\n' "${W_SCAN_SKIP_VALID[@]}"
    fi
    if [[ ${#W_SCAN_SKIP_BAD[@]} -gt 0 ]]; then
        for line in "${W_SCAN_SKIP_BAD[@]}"; do
            printf "$(get_text log.path-denied "${line}")" >&2
        done
    fi
    exit 0
fi

if [[ $# -ne 2 ]]; then
    show_usage
    exit 1
fi

if ! norm="$(check_scan_skip_path "$2")"; then
    printf "$(get_text log.path-denied "$2")" >&2
    exit 1
fi

collect_scan_skip_path
found=0
if [[ ${#W_SCAN_SKIP_VALID[@]} -gt 0 ]]; then
    for path in "${W_SCAN_SKIP_VALID[@]}"; do
        [[ "${path}" == "${norm}" ]] && found=1
    done
fi

if [[ "${action}" == "add" ]]; then
    if [[ "${found}" -eq 1 ]]; then
        printf "$(get_text log.this-path-is-already-excluded-s-n)" "${norm}"
        exit 0
    fi
    if [[ -s "${W_SCAN_SKIP_FILE}" ]] && [[ "$(tail -c1 "${W_SCAN_SKIP_FILE}" | wc -l)" -eq 0 ]]; then
        printf "$(get_text log.n)" >> "${W_SCAN_SKIP_FILE}"
    fi
    printf '%s\n' "${norm}" >> "${W_SCAN_SKIP_FILE}"
    printf "$(get_text log.path-added "${norm}")"
else
    if [[ "${found}" -eq 0 ]]; then
        printf '%s\n' "$(get_text log.path-absent-of-the-list "${norm}")" >&2
        exit 1
    fi
    python3 - "${W_SCAN_SKIP_FILE}" "${norm}" << 'PY'
import sys
from pathlib import Path

dest = Path(sys.argv[1])
target = sys.argv[2]
kept = []
for raw in dest.read_text(errors="replace").splitlines():
    line = raw.strip()
    if line == target:
        continue
    kept.append(raw)
text = "\n".join(kept)
if text and not text.endswith("\n"):
    text += "\n"
if not text.endswith("\n"):
    text += "\n"
dest.write_text(text)
PY
    printf "$(get_text log.path-removed "${norm}")"
fi

bash "${W_BASE}/cron/bin/apply-scan-skip.sh"
exit 0
