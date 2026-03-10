#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
WORKSPACE=$(cd -- "$SCRIPT_DIR/.." && pwd)
ROOT="$WORKSPACE/memory/logs"
DAY=${1:-$(date -d 'yesterday' +%F)}
YEAR=${DAY:0:4}
MONTH=${DAY:5:2}
TARGET="$ROOT/$YEAR/$MONTH/$DAY.md"
SOURCE="$WORKSPACE/memory/$DAY.md"
FALLBACK_SCRIPT="$WORKSPACE/scripts/ensure-daily-memory.sh"
ROOT_CRONTAB="/var/spool/cron/crontabs/root"

if [ -f "$TARGET" ]; then
  echo "OK: $TARGET"
  exit 0
fi

if [ ! -f "$SOURCE" ]; then
  DAY_END_TS=$(date -d "$DAY 23:59:59" +%s)

  fallback_script_ts=0
  fallback_cron_ts=0

  if [ -f "$FALLBACK_SCRIPT" ]; then
    fallback_script_ts=$(stat -c %Y "$FALLBACK_SCRIPT" 2>/dev/null || echo 0)
  fi

  if [ -f "$ROOT_CRONTAB" ] && grep -Fq "$FALLBACK_SCRIPT" "$ROOT_CRONTAB"; then
    fallback_cron_ts=$(stat -c %Y "$ROOT_CRONTAB" 2>/dev/null || echo 0)
  fi

  if [ "$fallback_script_ts" -eq 0 ] || [ "$fallback_cron_ts" -eq 0 ] || [ "$fallback_script_ts" -gt "$DAY_END_TS" ] || [ "$fallback_cron_ts" -gt "$DAY_END_TS" ]; then
    echo "INFO: 昨天（$DAY）不存在可归档源文件（$SOURCE），且当时 daily fallback 尚未生效，属于历史空窗，不判定为归档异常。"
    exit 0
  fi

  echo "查到：昨天（$DAY）不存在可归档源文件（$SOURCE），但 daily fallback 理应已覆盖。请检查 ensure-daily-memory cron/日志是否异常。"
  exit 1
fi

echo "查到：$ROOT/ 下未发现昨天（$DAY）的归档记录，且源文件存在（$SOURCE）。请检查 archive-memory-logs 归档/轮转是否正常。"
exit 1
