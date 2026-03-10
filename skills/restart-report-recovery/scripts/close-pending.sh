#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <taskId>" >&2
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
  echo "$(cd "$script_dir/../.." && pwd)"
}

workspace="$(resolve_workspace)"
state_file="$workspace/memory/restart-report-pending.jsonl"
[ -f "$state_file" ] || { echo "NO_PENDING_FILE $state_file"; exit 0; }

task_id="$1"

python3 - "$state_file" "$task_id" <<'PY'
import json,sys,time
state_file, task_id = sys.argv[1:3]
rows=[]
with open(state_file,'r',encoding='utf-8') as f:
    for ln in f:
        ln=ln.strip()
        if not ln:
            continue
        try:
            rows.append(json.loads(ln))
        except Exception:
            pass

changed=False
for r in rows:
    if r.get('taskId') == task_id and r.get('status') == 'pending':
        r['status'] = 'closed'
        r['closedAt'] = int(time.time())
        changed=True

if changed:
    with open(state_file,'w',encoding='utf-8') as f:
        for r in rows:
            f.write(json.dumps(r,ensure_ascii=False)+'\n')
    print(f"CLOSED {task_id}")
else:
    print(f"NOT_FOUND_OR_ALREADY_CLOSED {task_id}")
PY
