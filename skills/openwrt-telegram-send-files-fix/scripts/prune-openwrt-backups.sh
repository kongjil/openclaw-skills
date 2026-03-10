#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="${1:-/opt/backup/lingji1}"
NOW_EPOCH="$(date +%s)"
DAY_SEC=86400
MONTH_SEC=$((31 * DAY_SEC))
THREE_MONTH_SEC=$((92 * DAY_SEC))

[[ -d "$BASE_DIR" ]] || exit 0

parse_epoch() {
  local name="$1"
  date -d "${name:0:10} ${name:11:2}:${name:13:2}:${name:15:2}" +%s 2>/dev/null || return 1
}

mapfile -t dirs < <(
  find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r p; do
    basename "$p"
  done | sort -r
)
[[ ${#dirs[@]} -eq 0 ]] && exit 0

declare -A keep=()

# 1) keep latest 3 backups
for d in "${dirs[@]:0:3}"; do
  keep["$d"]=1
done

# 2) keep latest 4 Wednesday backups within last month, excluding latest 3
weekly_count=0
for d in "${dirs[@]}"; do
  [[ -n "${keep[$d]:-}" ]] && continue
  epoch="$(parse_epoch "$d" || true)"
  [[ -n "$epoch" ]] || continue
  age=$((NOW_EPOCH - epoch))
  (( age >= 0 && age <= MONTH_SEC )) || continue
  weekday="$(date -d "@$epoch" +%u)"
  if [[ "$weekday" == "3" ]]; then
    keep["$d"]=1
    weekly_count=$((weekly_count + 1))
    [[ $weekly_count -ge 4 ]] && break
  fi
done

# 3) keep latest 2 monthly checkpoints: day 15, from >1 month to <=3 months
monthly_count=0
for d in "${dirs[@]}"; do
  [[ -n "${keep[$d]:-}" ]] && continue
  epoch="$(parse_epoch "$d" || true)"
  [[ -n "$epoch" ]] || continue
  age=$((NOW_EPOCH - epoch))
  (( age > MONTH_SEC && age <= THREE_MONTH_SEC )) || continue
  dom="$(date -d "@$epoch" +%d)"
  if [[ "$dom" == "15" ]]; then
    keep["$d"]=1
    monthly_count=$((monthly_count + 1))
    [[ $monthly_count -ge 2 ]] && break
  fi
done

for d in "${dirs[@]}"; do
  if [[ -z "${keep[$d]:-}" ]]; then
    rm -rf -- "$BASE_DIR/$d"
  fi
done
