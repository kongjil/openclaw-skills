#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lingji2-common.sh
source "${SCRIPT_DIR}/lingji2-common.sh"

usage() {
  cat <<'EOF'
Usage:
  scripts/lingji2-ssh.sh <cmd...>
  scripts/lingji2-ssh.sh --raw '<remote command string>'
EOF
}

main() {
  lingji2_require_key_if_set

  if [[ $# -lt 1 ]]; then
    usage >&2
    exit 2
  fi

  if [[ "$1" == "--raw" ]]; then
    shift
    [[ $# -eq 1 ]] || lingji2_die "--raw requires exactly one command string"
    lingji2_ssh "bash -lc $1"
    return
  fi

  local cmd_quoted
  cmd_quoted="$(lingji2_quote_args "$@")"
  lingji2_ssh "bash -lc ${cmd_quoted}"
}

main "$@"
