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
state_file="$workspace/memory/restart-report-pending.jsonl"

[ -x "$recover_script" ] || { echo "MISSING_RECOVER_SCRIPT $recover_script"; exit 1; }
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
      rest="${rest#* }"
      summary_path="${rest%%$'\t'*}"
      meta=""
      if [[ "$rest" == *$'\t'* ]]; then
        meta="${rest#*$'\t'}"
      fi
      [ -f "$summary_path" ] || continue
      [ -s "$summary_path" ] || continue

      target_session_key=""
      target_channel=""
      target_to=""
      if [ -n "$meta" ]; then
        while IFS= read -r field; do
          case "$field" in
            targetSessionKey=*) target_session_key="${field#targetSessionKey=}" ;;
            targetChannel=*) target_channel="${field#targetChannel=}" ;;
            targetTo=*) target_to="${field#targetTo=}" ;;
          esac
        done < <(printf '%s\n' "$meta" | tr '\t' '\n')
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
      [ -n "$summary_content" ] || continue

      [ "$printed" -eq 0 ] || printf '\n\n'
      printf 'READY_RESULT\n'
      printf 'taskId=%s\n' "$task_id"
      printf 'summaryPath=%s\n' "$summary_path"
      printf 'targetSessionKey=%s\n' "$target_session_key"
      printf 'targetChannel=%s\n' "$target_channel"
      printf 'targetTo=%s\n' "$target_to"
      printf -- '---SUMMARY-BEGIN---\n%s\n---SUMMARY-END---\n' "$summary_content"
      printed=1
      ;;
    *)
      ;;
  esac
done

exit 0
