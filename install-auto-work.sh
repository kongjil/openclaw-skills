#!/usr/bin/env bash
set -euo pipefail

SRC_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/auto-work.skill"
SRC="${1:-$SRC_DEFAULT}"
TARGET_ROOT="${2:-$HOME/.openclaw/workspace/skills}"
TARGET_DIR="$TARGET_ROOT/auto-work"

[ -f "$SRC" ] || { echo "skill archive not found: $SRC"; exit 2; }
mkdir -p "$TARGET_ROOT"
rm -rf "$TARGET_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
unzip -q "$SRC" -d "$TMP_DIR"
[ -d "$TMP_DIR/auto-work" ] || { echo "invalid skill archive: missing auto-work/"; exit 3; }
cp -a "$TMP_DIR/auto-work" "$TARGET_DIR"

echo "[ok] installed: $TARGET_DIR"
echo "[next] trigger with: 开启自动工作 / 这个任务持续做完 / 不要只监督，直接做完"
