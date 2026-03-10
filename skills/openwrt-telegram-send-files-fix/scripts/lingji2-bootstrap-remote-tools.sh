#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lingji2-common.sh
source "${SCRIPT_DIR}/lingji2-common.sh"

usage() {
  cat <<'EOF'
Usage:
  scripts/lingji2-bootstrap-remote-tools.sh [remote_workspace]

Purpose:
  首次把 lingji2 远端工具链脚本铺到 2 号机，并在远端做 chmod + bash -n 校验。

Example:
  scripts/lingji2-bootstrap-remote-tools.sh
  scripts/lingji2-bootstrap-remote-tools.sh /root/.openclaw/workspace
EOF
}

main() {
  lingji2_require_key_if_set

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  if [[ $# -gt 1 ]]; then
    usage >&2
    exit 2
  fi

  local remote_workspace remote_scripts_dir
  remote_workspace="${1:-/root/.openclaw/workspace}"
  remote_scripts_dir="${remote_workspace}/scripts"

  local -a files
  files=(
    "lingji2-common.sh"
    "lingji2-ssh.sh"
    "lingji2-copy.sh"
    "lingji2-run-script.sh"
    "lingji2-bootstrap-remote-tools.sh"
    "README-lingji2-remote.md"
  )

  local f
  for f in "${files[@]}"; do
    [[ -f "${SCRIPT_DIR}/${f}" ]] || lingji2_die "local file not found: ${SCRIPT_DIR}/${f}"
  done

  echo "[lingji2-bootstrap] ensure remote dir: ${remote_scripts_dir}"
  lingji2_ssh "mkdir -p '${remote_scripts_dir}'"

  echo "[lingji2-bootstrap] upload files"
  for f in "${files[@]}"; do
    lingji2_scp "${SCRIPT_DIR}/${f}" "$(lingji2_target):${remote_scripts_dir}/${f}"
  done

  echo "[lingji2-bootstrap] chmod +x scripts"
  lingji2_ssh "chmod +x \
'${remote_scripts_dir}/lingji2-common.sh' \
'${remote_scripts_dir}/lingji2-ssh.sh' \
'${remote_scripts_dir}/lingji2-copy.sh' \
'${remote_scripts_dir}/lingji2-run-script.sh' \
'${remote_scripts_dir}/lingji2-bootstrap-remote-tools.sh'"

  echo "[lingji2-bootstrap] bash -n verify"
  lingji2_ssh "bash -n '${remote_scripts_dir}/lingji2-common.sh'"
  lingji2_ssh "bash -n '${remote_scripts_dir}/lingji2-ssh.sh'"
  lingji2_ssh "bash -n '${remote_scripts_dir}/lingji2-copy.sh'"
  lingji2_ssh "bash -n '${remote_scripts_dir}/lingji2-run-script.sh'"
  lingji2_ssh "bash -n '${remote_scripts_dir}/lingji2-bootstrap-remote-tools.sh'"

  echo "[lingji2-bootstrap] done"
  echo "[lingji2-bootstrap] next: use scripts/lingji2-ssh.sh | scripts/lingji2-copy.sh | scripts/lingji2-run-script.sh"
}

main "$@"
