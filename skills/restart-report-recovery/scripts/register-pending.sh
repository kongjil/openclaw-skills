#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <taskId> <summaryPath> <brief> [longrunName] [targetSessionKey] [targetChannel] [targetTo]" >&2
  exit 2
fi

resolve_workspace() {
  if [ -n "${OPENCLAW_WORKSPACE:-}" ] && [ -d "$OPENCLAW_WORKSPACE" ]; then
    echo "$OPENCLAW_WORKSPACE"; return
  fi
  if [ -d "$HOME/.openclaw/workspace" ]; then
    echo "$HOME/.openclaw/workspace"; return
  fi
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  # scripts -> skill_dir -> skills -> workspace
  echo "$(cd "$script_dir/../.." && pwd)"
}

workspace="$(resolve_workspace)"
state_dir="$workspace/memory"
state_file="$state_dir/restart-report-pending.jsonl"
mkdir -p "$state_dir"

task_id="$1"
summary_path="$2"
brief="$3"
longrun_name="${4:-}"
target_session_key="${5:-}"
target_channel="${6:-}"
target_to="${7:-}"

python3 - "$state_file" "$task_id" "$summary_path" "$brief" "$longrun_name" "$target_session_key" "$target_channel" "$target_to" <<'PY'
import json,sys,time
state_file,task_id,summary_path,brief,longrun_name,target_session_key,target_channel,target_to = sys.argv[1:9]
obj = {
  "taskId": task_id,
  "summaryPath": summary_path,
  "brief": brief,
  "longrunName": longrun_name,
  "targetSessionKey": target_session_key,
  "targetChannel": target_channel,
  "targetTo": target_to,
  "status": "pending",
  "createdAt": int(time.time()),
  "closedAt": None,
}
with open(state_file, "a", encoding="utf-8") as f:
    f.write(json.dumps(obj, ensure_ascii=False) + "\n")
print(f"REGISTERED {task_id} -> {state_file}")
PY
