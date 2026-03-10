#!/usr/bin/env bash
set -euo pipefail
TARGET_ROOT="${1:-$HOME/.openclaw/workspace/skills}"
TARGET_DIR="$TARGET_ROOT/auto-work-task-reminder"
BASE="https://raw.githubusercontent.com/kongjil/openclaw-skills/main"
mkdir -p "$TARGET_DIR"
curl -fsSL "$BASE/skills/task-pulse-reminder/skill/task-pulse-reminder/SKILL.md" -o "$TARGET_DIR/SKILL.md"
curl -fsSL "$BASE/skills/task-pulse-reminder/README.md" -o "$TARGET_DIR/README.md" || true
echo "[ok] installed: $TARGET_DIR"
