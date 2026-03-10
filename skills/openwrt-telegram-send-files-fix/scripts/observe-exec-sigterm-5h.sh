#!/usr/bin/env bash
set -u
LOG="/root/.openclaw/workspace/temp/observe-exec-sigterm-5h-$(date +%F_%H%M%S).log"
END=$(( $(date +%s) + 5*3600 ))
echo "[start] $(date '+%F %T %z') log=$LOG" | tee -a "$LOG"
run_check(){
  local name="$1"; shift
  local t0=$(date +%s)
  echo "=== [$name] start $(date '+%F %T %z') ===" | tee -a "$LOG"
  if timeout 40s "$@" >>"$LOG" 2>&1; then rc=0; else rc=$?; fi
  local t1=$(date +%s)
  echo "=== [$name] end rc=$rc dur=$((t1-t0))s $(date '+%F %T %z') ===" | tee -a "$LOG"
}
while [ $(date +%s) -lt "$END" ]; do
  echo "--- tick $(date '+%F %T %z') ---" | tee -a "$LOG"
  run_check openclaw-status openclaw status
  run_check openclaw-gateway-status openclaw gateway status
  run_check git-ls-remote git ls-remote --heads https://github.com/kongjil/new-api.git kong
  run_check sleep-20 bash -lc 'sleep 20; echo sleep-ok'
  run_check systemd-state systemctl is-active openclaw-gateway.service
  run_check gateway-mainpid systemctl show -p MainPID -p ExecMainStartTimestamp -p ActiveEnterTimestamp -p NRestarts openclaw-gateway.service
  sleep 600
done
echo "[done] $(date '+%F %T %z')" | tee -a "$LOG"
