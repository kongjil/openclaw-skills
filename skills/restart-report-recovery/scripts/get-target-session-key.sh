#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <taskId>" >&2
  exit 2
fi

task_id="$1"

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
state_file="$workspace/memory/restart-report-pending.jsonl"
[ -f "$state_file" ] || exit 0

python3 - "$state_file" "$task_id" <<'PY'
import json,sys
state_file, task_id = sys.argv[1:3]
found = None
with open(state_file,'r',encoding='utf-8') as f:
    for ln in f:
        ln = ln.strip()
        if not ln:
            continue
        try:
            row = json.loads(ln)
        except Exception:
            continue
        if row.get('taskId') == task_id:
            found = row
if found and found.get('targetSessionKey'):
    print(found['targetSessionKey'])
PY
