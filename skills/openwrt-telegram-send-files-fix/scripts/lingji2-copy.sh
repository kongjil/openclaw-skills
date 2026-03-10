#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lingji2-common.sh
source "${SCRIPT_DIR}/lingji2-common.sh"

usage() {
  cat <<'EOF'
Usage:
  scripts/lingji2-copy.sh upload <local_src> <remote_dest>
  scripts/lingji2-copy.sh download <remote_src> <local_dest>
  scripts/lingji2-copy.sh sync-up <local_src> <remote_dest>
  scripts/lingji2-copy.sh sync-down <remote_src> <local_dest>

Notes:
  - upload/download use scp (file or dir, with -r for dirs)
  - sync-up/sync-down use rsync (incremental)
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || lingji2_die "missing command: $1"
}

main() {
  lingji2_require_key_if_set

  [[ $# -eq 3 ]] || { usage >&2; exit 2; }

  local mode="$1"
  local src="$2"
  local dest="$3"

  case "${mode}" in
    upload)
      if [[ ! -e "${src}" ]]; then
        lingji2_die "local source not found: ${src}"
      fi
      if [[ -d "${src}" ]]; then
        lingji2_scp -r "${src}" "$(lingji2_target):${dest}"
      else
        lingji2_scp "${src}" "$(lingji2_target):${dest}"
      fi
      ;;
    download)
      if [[ -d "${dest}" ]]; then
        :
      else
        mkdir -p "$(dirname "${dest}")"
      fi
      lingji2_scp "$(lingji2_target):${src}" "${dest}"
      ;;
    sync-up)
      need_cmd rsync
      if [[ ! -e "${src}" ]]; then
        lingji2_die "local source not found: ${src}"
      fi
      rsync -av --partial --append-verify -e "$(lingji2_rsync_ssh_cmd)" "${src}" "$(lingji2_target):${dest}"
      ;;
    sync-down)
      need_cmd rsync
      mkdir -p "$(dirname "${dest}")"
      rsync -av --partial --append-verify -e "$(lingji2_rsync_ssh_cmd)" "$(lingji2_target):${src}" "${dest}"
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
