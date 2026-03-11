#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 5 ]; then
  cat >&2 <<'EOF'
Usage:
  run-with-pending.sh <taskId> <summaryPath> <brief> [longrunName] -- <command...>
EOF
  exit 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
register_script="$script_dir/register-pending.sh"

task_id="$1"
summary_path="$2"
brief="$3"
longrun_name="$4"
shift 4

if [ "${1:-}" != "--" ]; then
  echo "error: missing -- before command" >&2
  exit 2
fi
shift
[ "$#" -gt 0 ] || { echo "error: missing command" >&2; exit 2; }

mkdir -p "$(dirname "$summary_path")"
OPENCLAW_WORKSPACE="${OPENCLAW_WORKSPACE:-}" bash "$register_script" "$task_id" "$summary_path" "$brief" "$longrun_name"

set +e
"$@"
rc=$?
set -e

if [ $rc -ne 0 ] && [ ! -s "$summary_path" ]; then
  {
    printf '重启后补汇报：任务 %s 执行失败。\n\n' "$task_id"
    printf -- '- brief: %s\n' "$brief"
    printf -- '- command: '
    printf '%q ' "$@"
    printf '\n- exitCode: %s\n' "$rc"
    printf -- '- time: %s\n' "$(date '+%F %T %Z')"
  } > "$summary_path"
fi

exit $rc
