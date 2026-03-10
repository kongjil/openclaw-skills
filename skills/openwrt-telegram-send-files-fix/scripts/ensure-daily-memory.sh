#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
WORKSPACE=$(cd -- "$SCRIPT_DIR/.." && pwd)
MEMORY_DIR="$WORKSPACE/memory"
mkdir -p "$MEMORY_DIR"

DAY=${1:-$(date +%F)}
TARGET="$MEMORY_DIR/$DAY.md"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

NOW=$(date '+%F %T %Z')
YEAR=${DAY:0:4}
MONTH=${DAY:5:2}
ARCHIVE_TARGET="$MEMORY_DIR/logs/$YEAR/$MONTH/$DAY.md"

ALERT_COUNT=$(grep -RoiE "告警|ALERT|运维告警|余额低于|异常" "$MEMORY_DIR" 2>/dev/null | wc -l | tr -d ' ')
GIT_SUMMARY=$(git -C "$WORKSPACE" log --since="$DAY 00:00:00" --until="$DAY 23:59:59" --pretty=format:'- %h %s' -n 5 2>/dev/null || true)
GIT_COUNT=$(git -C "$WORKSPACE" log --since="$DAY 00:00:00" --until="$DAY 23:59:59" --oneline 2>/dev/null | wc -l | tr -d ' ')
GATEWAY_STATUS=$(systemctl is-active openclaw-gateway.service 2>/dev/null || echo unknown)
GATEWAY_RESTARTS=$(journalctl -u openclaw-gateway.service --since "$DAY 00:00:00" --until "$DAY 23:59:59" --no-pager 2>/dev/null | grep -cE "Starting OpenClaw Gateway|Started OpenClaw Gateway" || true)

if [ -z "$GIT_SUMMARY" ]; then
  GIT_SUMMARY='- 无 git 提交记录'
fi

if [ -f "$ARCHIVE_TARGET" ]; then
  ARCHIVE_STATUS="已存在历史归档（通常仅在补跑/重建时出现）"
else
  ARCHIVE_STATUS="当日归档尚未发生（正常，次日 00:10 归档）"
fi

cat >"$TMP" <<EOF
# $DAY 运维日报

- 创建时间：$NOW
- 类型：daily memory（统一文件 / 运维日报头）
- 当日概况：今日暂无显式对话或可自动提取的重要事件。

## 运维摘要
- OpenClaw Gateway 状态：$GATEWAY_STATUS
- OpenClaw Gateway 当日重启相关日志命中：$GATEWAY_RESTARTS
- Git 提交数：$GIT_COUNT
- memory 目录告警关键词粗检命中：$ALERT_COUNT
- 日志归档状态：$ARCHIVE_STATUS
- 运行说明：已启用 memoryFlush；如当天无对话，也由每日兜底任务保底生成日志。

## Git 摘要
$GIT_SUMMARY

## 今日建议补记
- 今天做了什么
- 是否有重要排障 / 变更 / 决策
- 是否有需要写入 MEMORY.md 的长期信息
- 是否有需要明日跟进的事项
- 是否有异常但尚未彻底根修的问题
EOF

if [ ! -f "$TARGET" ]; then
  mv "$TMP" "$TARGET"
  echo "created: $TARGET"
  exit 0
fi

if grep -q "^# $DAY 运维日报$" "$TARGET"; then
  echo "header-exists: $TARGET"
  exit 0
fi

{
  cat "$TMP"
  printf '\n---\n\n'
  cat "$TARGET"
} > "$TARGET.tmp"
mv "$TARGET.tmp" "$TARGET"
echo "prepended-header: $TARGET"
