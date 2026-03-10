#!/usr/bin/env bash
set -euo pipefail
TARGET_ROOT="${1:-$HOME/.openclaw/workspace/skills}"
TARGET_DIR="$TARGET_ROOT/restart-report-recovery"
BASE="https://raw.githubusercontent.com/kongjil/openclaw-skills/main"
mkdir -p "$TARGET_DIR/scripts"
curl -fsSL "$BASE/skills/restart-report-recovery/SKILL.md" -o "$TARGET_DIR/SKILL.md"
curl -fsSL "$BASE/skills/restart-report-recovery/scripts/register-pending.sh" -o "$TARGET_DIR/scripts/register-pending.sh"
curl -fsSL "$BASE/skills/restart-report-recovery/scripts/recover-pending.sh" -o "$TARGET_DIR/scripts/recover-pending.sh"
curl -fsSL "$BASE/skills/restart-report-recovery/scripts/close-pending.sh" -o "$TARGET_DIR/scripts/close-pending.sh"
chmod +x "$TARGET_DIR/scripts/"*.sh
echo "[ok] installed: $TARGET_DIR"
