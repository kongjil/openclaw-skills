#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  gateway-restart-safe.sh <taskId> <summaryPath> <brief> [--delay-sec N] [--dry-run]

Behavior:
  1) register pending
  2) spawn detached post-restart verifier that writes summaryPath
  3) restart openclaw-gateway.service
EOF
}

if [ "$#" -lt 3 ]; then
  usage >&2
  exit 2
fi

task_id="$1"
summary_path="$2"
brief="$3"
shift 3

delay_sec=12
dry_run=0
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
      echo "error: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

script_dir="$(cd "$(dirname "$0")" && pwd)"
register_script="$script_dir/register-pending.sh"
mkdir -p "$(dirname "$summary_path")"

bash "$register_script" "$task_id" "$summary_path" "$brief" ""

postcheck_script="$(mktemp /tmp/openclaw-gateway-restart-postcheck.${task_id}.XXXXXX.sh)"
cat > "$postcheck_script" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
TASK_ID="$1"
SUMMARY_PATH="$2"
BRIEF="$3"
DELAY_SEC="$4"
SERVICE="openclaw-gateway.service"

sleep "$DELAY_SEC"

EXECSTART="$(systemctl show "$SERVICE" -p ExecStart --value 2>/dev/null || true)"
PORT="$(printf '%s' "$EXECSTART" | grep -Eo -- '--port[ =][0-9]+' | head -n1 | grep -Eo '[0-9]+' || true)"
[ -n "$PORT" ] || PORT=28789
URL="http://127.0.0.1:${PORT}/"
ACTIVE="$(systemctl is-active "$SERVICE" 2>/dev/null || true)"
STATUS_SNIP="$(systemctl status "$SERVICE" --no-pager -l 2>/dev/null | sed -n '1,25p' || true)"
PROBE="$(curl -Is --max-time 5 "$URL" 2>/dev/null | sed -n '1,8p' || true)"
TS="$(date '+%F %T %Z')"

{
  printf '重启后补汇报：任务 %s 已执行 gateway 重启检查。\n\n' "$TASK_ID"
  printf -- '- brief: %s\n' "$BRIEF"
  printf -- '- time: %s\n' "$TS"
  printf -- '- service: %s\n' "$SERVICE"
  printf -- '- is-active: %s\n' "${ACTIVE:-unknown}"
  printf -- '- probe: %s\n\n' "${URL}"
  if [ -n "$PROBE" ]; then
    printf '## HTTP probe\n%s\n\n' "$PROBE"
  else
    printf '## HTTP probe\n(no response within timeout)\n\n'
  fi
  if [ -n "$STATUS_SNIP" ]; then
    printf '## systemctl status\n%s\n' "$STATUS_SNIP"
  fi
} > "$SUMMARY_PATH"
rm -f "$0"
SH
chmod 700 "$postcheck_script"

spawn_postcheck() {
  local script_path="$1"
  shift
  local unit="openclaw-postcheck-gateway-${task_id//[^a-zA-Z0-9_.-]/-}"
  if command -v systemd-run >/dev/null 2>&1; then
    if systemd-run --unit "$unit" --collect --service-type=exec /bin/bash "$script_path" "$@" \
      >/tmp/openclaw-gateway-restart-postcheck.launch.log 2>&1; then
      echo "systemd-run:$unit"
      return 0
    fi
  fi
  nohup setsid /bin/bash "$script_path" "$@" </dev/null >/tmp/openclaw-gateway-restart-postcheck.log 2>&1 &
  local pid=$!
  echo "setsid:$pid"
  return 0
}

postcheck_handle="$(spawn_postcheck "$postcheck_script" "$task_id" "$summary_path" "$brief" "$delay_sec")"

if [ "$dry_run" = "1" ]; then
  echo "DRY_RUN registered=$task_id summary=$summary_path postcheck=$postcheck_handle delay=$delay_sec"
  exit 0
fi

systemctl restart openclaw-gateway.service
printf 'REGISTERED %s\n' "$task_id"
printf 'SUMMARY %s\n' "$summary_path"
printf 'POSTCHECK %s\n' "$postcheck_handle"
