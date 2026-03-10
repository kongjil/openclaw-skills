#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lingji2-common.sh
source "${SCRIPT_DIR}/lingji2-common.sh"

usage() {
  cat <<'EOF'
Usage:
  scripts/lingji2-run-script.sh <local_script> [args...]

Behavior:
  1) Upload local script to remote tmp dir via scp
  2) chmod +x
  3) Execute with provided args
  4) Auto-clean temporary script file
EOF
}

main() {
  lingji2_require_key_if_set

  [[ $# -ge 1 ]] || { usage >&2; exit 2; }

  local local_script="$1"
  shift

  [[ -f "${local_script}" ]] || lingji2_die "local script not found: ${local_script}"

  local remote_tmp_dir remote_script remote_cmd args_quoted
  remote_tmp_dir="/tmp/openclaw-lingji2-run"
  remote_script="${remote_tmp_dir}/$(basename "${local_script}").$$.$RANDOM.sh"

  lingji2_ssh "mkdir -p '${remote_tmp_dir}'"
  lingji2_scp "${local_script}" "$(lingji2_target):${remote_script}"

  args_quoted="$(lingji2_quote_args "$@")"

  if [[ -n "${args_quoted}" ]]; then
    remote_cmd="chmod +x '${remote_script}' && '${remote_script}' ${args_quoted}"
  else
    remote_cmd="chmod +x '${remote_script}' && '${remote_script}'"
  fi

  set +e
  lingji2_ssh "bash -lc $(printf '%q' "${remote_cmd}")"
  local rc=$?
  set -e

  lingji2_ssh "rm -f '${remote_script}'" || true
  exit "${rc}"
}

main "$@"
