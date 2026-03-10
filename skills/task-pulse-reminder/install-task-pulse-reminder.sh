#!/usr/bin/env bash
set -euo pipefail

# Install Task Pulse Reminder skill pack
# 安装 Task Pulse Reminder 技能包
# Usage / 用法:
#   bash install-task-pulse-reminder.sh [SKILLS_ROOT]

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/skill/task-pulse-reminder"
TARGET_ROOT="${1:-$HOME/.openclaw/workspace/skills}"
TARGET_DIR="$TARGET_ROOT/task-pulse-reminder"

mkdir -p "$TARGET_ROOT"
rm -rf "$TARGET_DIR"
cp -a "$SRC_DIR" "$TARGET_DIR"

echo "[ok] installed: $TARGET_DIR"
echo "[next] 在 OpenClaw 中直接使用触发词：每5分钟提醒继续任务 / 常开唤起"
echo "[next] Trigger phrases: remind every 5 minutes / keep nudging until done"
