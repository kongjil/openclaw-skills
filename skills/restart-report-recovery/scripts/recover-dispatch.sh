#!/usr/bin/env bash
set -euo pipefail

resolve_workspace() {
  if [ -n "${OPENCLAW_WORKSPACE:-}" ] && [ -d "$OPENCLAW_WORKSPACE" ]; then
    echo "$OPENCLAW_WORKSPACE"; return
  fi
  if [ -d "$HOME/.openclaw/workspace" ]; then
    echo "$HOME/.openclaw/workspace"; return
  fi
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  echo "$(cd "$script_dir/../.." && pwd)"
}

workspace="$(resolve_workspace)"
recover_script="$workspace/skills/restart-report-recovery/scripts/recover-pending.sh"
close_script="$workspace/skills/restart-report-recovery/scripts/close-pending.sh"
state_file="$workspace/memory/restart-report-pending.jsonl"

[ -x "$recover_script" ] || { echo "MISSING_RECOVER_SCRIPT $recover_script"; exit 1; }
[ -x "$close_script" ] || { echo "MISSING_CLOSE_SCRIPT $close_script"; exit 1; }
[ -f "$state_file" ] || exit 0

mapfile -t lines < <(bash "$recover_script")
[ "${#lines[@]}" -gt 0 ] || exit 0

printed=0
for line in "${lines[@]}"; do
  [ -n "$line" ] || continue
  case "$line" in
    READY\ *)
      rest="${line#READY }"
      task_id="${rest%% *}"
      summary_path="${rest#* }"
      [ -f "$summary_path" ] || continue
      if [ ! -s "$summary_path" ]; then
        continue
      fi

      summary_content="$(python3 - "$summary_path" <<'PY'
import sys
p=sys.argv[1]
with open(p,'r',encoding='utf-8',errors='replace') as f:
    txt=f.read()
limit=12000
if len(txt) > limit:
    txt = txt[:limit] + "\n\n[摘要已截断，完整结果见落地文件]"
print(txt, end='')
PY
)"

      if [ -n "$summary_content" ]; then
        if [ $printed -eq 1 ]; then
          printf '\n\n'
        fi
        printf '重启后补汇报：任务 %s 已完成。\n\n%s\n' "$task_id" "$summary_content"
        printed=1
        bash "$close_script" "$task_id" >/dev/null 2>&1 || true
      fi
      ;;
    *)
      ;;
  esac
done

exit 0
