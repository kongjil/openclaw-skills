#!/usr/bin/env bash
set -euo pipefail
TARGET_ROOT="${1:-$HOME/.openclaw/workspace/skills}"
TARGET_DIR="$TARGET_ROOT/code-moment-codex-switch"
BASE="https://raw.githubusercontent.com/kongjil/openclaw-skills/main"
mkdir -p "$TARGET_DIR"
curl -fsSL "$BASE/skills/code-moment-codex-switch/SKILL.md" -o "$TARGET_DIR/SKILL.md"
curl -fsSL "$BASE/skills/code-moment-codex-switch/README.md" -o "$TARGET_DIR/README.md" || true
echo "[ok] installed: $TARGET_DIR"
