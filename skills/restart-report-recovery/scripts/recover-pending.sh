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
state_file="$workspace/memory/restart-report-pending.jsonl"
[ -f "$state_file" ] || { echo "NO_PENDING_FILE $state_file"; exit 0; }

oc_longrun_bin="${OPENCLAW_LONGRUN_BIN:-$(command -v oc-longrun || true)}"

python3 - "$state_file" "$oc_longrun_bin" <<'PY'
import json,sys,os,subprocess
state_file, longrun_bin = sys.argv[1:3]

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

for r in rows:
    if r.get('status') != 'pending':
        continue

    task = r.get('taskId','unknown')
    summary = r.get('summaryPath','')
    longrun = r.get('longrunName','')

    if summary and os.path.exists(summary) and os.path.getsize(summary) > 0:
        print(f"READY {task} {summary}")
        continue

    running = False
    if longrun and longrun_bin:
        try:
            out = subprocess.run([longrun_bin,'status',longrun],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=6)
            txt = (out.stdout or '').lower()
            if ('running' in txt) or ('active' in txt):
                running = True
        except Exception:
            running = False

    if running:
        print(f"WAIT {task} longrun:{longrun}")
    else:
        print(f"WAIT {task} no-result")
PY
