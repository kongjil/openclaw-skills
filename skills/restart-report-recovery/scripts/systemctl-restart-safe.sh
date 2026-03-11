#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  systemctl-restart-safe.sh <taskId> <summaryPath> <brief> <service> [service...] [--delay-sec N] [--dry-run]
EOF
}

if [ "$#" -lt 4 ]; then
  usage >&2
  exit 2
fi

task_id="$1"
summary_path="$2"
brief="$3"
shift 3

delay_sec=12
dry_run=0
services=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --delay-sec)
      delay_sec="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      services+=("$1")
      shift
      ;;
  esac
done

[ "${#services[@]}" -gt 0 ] || { echo "error: missing service name" >&2; exit 2; }

script_dir="$(cd "$(dirname "$0")" && pwd)"
register_script="$script_dir/register-pending.sh"
mkdir -p "$(dirname "$summary_path")"

bash "$register_script" "$task_id" "$summary_path" "$brief" ""

postcheck_script="$(mktemp /tmp/systemctl-restart-postcheck.${task_id}.XXXXXX.sh)"
cat > "$postcheck_script" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
TASK_ID="$1"
SUMMARY_PATH="$2"
BRIEF="$3"
DELAY_SEC="$4"
shift 4
services=("$@")

sleep "$DELAY_SEC"
TS="$(date '+%F %T %Z')"
{
  printf '重启后补汇报：任务 %s 已执行 systemctl restart 检查。\n\n' "$TASK_ID"
  printf -- '- brief: %s\n' "$BRIEF"
  printf -- '- time: %s\n\n' "$TS"
  for svc in "${services[@]}"; do
    active="$(systemctl is-active "$svc" 2>/dev/null || true)"
    printf '## %s\n' "$svc"
    printf -- '- is-active: %s\n' "${active:-unknown}"
    systemctl status "$svc" --no-pager -l 2>/dev/null | sed -n '1,20p'
    printf '\n'
  done
} > "$SUMMARY_PATH"
rm -f "$0"
SH
chmod 700 "$postcheck_script"

spawn_postcheck() {
  local script_path="$1"
  shift
  local unit="openclaw-postcheck-systemctl-${task_id//[^a-zA-Z0-9_.-]/-}"
  if command -v systemd-run >/dev/null 2>&1; then
    if systemd-run --unit "$unit" --collect --service-type=exec /bin/bash "$script_path" "$@" \
      >/tmp/systemctl-restart-postcheck.launch.log 2>&1; then
      echo "systemd-run:$unit"
      return 0
    fi
  fi
  nohup setsid /bin/bash "$script_path" "$@" </dev/null >/tmp/systemctl-restart-postcheck.log 2>&1 &
  local pid=$!
  echo "setsid:$pid"
  return 0
}

postcheck_handle="$(spawn_postcheck "$postcheck_script" "$task_id" "$summary_path" "$brief" "$delay_sec" "${services[@]}")"

if [ "$dry_run" = "1" ]; then
  echo "DRY_RUN registered=$task_id summary=$summary_path postcheck=$postcheck_handle services=${services[*]} delay=$delay_sec"
  exit 0
fi

systemctl restart "${services[@]}"
printf 'REGISTERED %s\n' "$task_id"
printf 'SUMMARY %s\n' "$summary_path"
printf 'POSTCHECK %s\n' "$postcheck_handle"
