#!/usr/bin/env bash
set -euo pipefail

WORKSPACE=/root/.openclaw/workspace
MEMORY_DIR="$WORKSPACE/memory"
ARCHIVE_ROOT="$MEMORY_DIR/logs"

shopt -s nullglob
for src in "$MEMORY_DIR"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md; do
  base=$(basename "$src")
  day=${base%.md}
  year=${day:0:4}
  month=${day:5:2}
  dest_dir="$ARCHIVE_ROOT/$year/$month"
  dest="$dest_dir/$base"
  mkdir -p "$dest_dir"

  if [ ! -f "$dest" ] || [ "$src" -nt "$dest" ]; then
    install -m 0644 "$src" "$dest"
    echo "archived: $src -> $dest"
  else
    echo "up-to-date: $dest"
  fi
done
