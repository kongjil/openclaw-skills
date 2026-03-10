#!/usr/bin/env bash
set -euo pipefail

LOG_FILE_DEFAULT="/tmp/openclaw/openclaw-$(date +%F).log"
TEST_FILE_DEFAULT="/root/.openclaw/workspace/scripts/lingji2-bootstrap-remote-tools.sh"
TARGET_DEFAULT="2D9E4482013547CC3C6F34976CD9BB21"
MESSAGE_DEFAULT="[qqbot-selfcheck] file send probe $(date '+%F %T %z')"

LOG_FILE="$LOG_FILE_DEFAULT"
TEST_FILE="$TEST_FILE_DEFAULT"
TARGET="$TARGET_DEFAULT"
MESSAGE="$MESSAGE_DEFAULT"
TIMEOUT_SEC="60"

usage() {
  cat <<USAGE
用法: $(basename "$0") [选项]

选项:
  --log-file <path>     日志文件路径（默认: $LOG_FILE_DEFAULT）
  --file <path>         待发送文件（默认: $TEST_FILE_DEFAULT）
  --target <id>         QQ 目标 openid/groupid（默认: $TARGET_DEFAULT）
  --message <text>      发送说明文本
  --timeout <sec>       发送命令超时秒数（默认: 60）
  -h, --help            显示帮助
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log-file) LOG_FILE="${2:?}"; shift 2 ;;
    --file) TEST_FILE="${2:?}"; shift 2 ;;
    --target) TARGET="${2:?}"; shift 2 ;;
    --message) MESSAGE="${2:?}"; shift 2 ;;
    --timeout) TIMEOUT_SEC="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage; exit 2 ;;
  esac
done

echo "[INFO] LOG_FILE=$LOG_FILE"
echo "[INFO] TEST_FILE=$TEST_FILE"
echo "[INFO] TARGET=$TARGET"

if ! command -v openclaw >/dev/null 2>&1; then
  echo "[UNKNOWN] openclaw CLI 不存在，无法从 shell 触发 message tool 闭环。"
  echo "RESULT=UNKNOWN"
  exit 3
fi

if [[ ! -f "$TEST_FILE" ]]; then
  echo "[UNKNOWN] 测试文件不存在: $TEST_FILE"
  echo "RESULT=UNKNOWN"
  exit 3
fi

PLUGIN_INFO_JSON=""
if ! PLUGIN_INFO_JSON=$(openclaw plugins info qqbot --json 2>/dev/null); then
  echo "[UNKNOWN] 无法读取 qqbot 插件信息（可能 gateway 不可达或插件未注册）。"
  echo "RESULT=UNKNOWN"
  exit 3
fi

SOURCE_PATH=$(printf '%s' "$PLUGIN_INFO_JSON" | node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); process.stdout.write(x.source||"");' 2>/dev/null || true)
STATUS=$(printf '%s' "$PLUGIN_INFO_JSON" | node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); process.stdout.write(x.status||"");' 2>/dev/null || true)
ENABLED=$(printf '%s' "$PLUGIN_INFO_JSON" | node -e 'const fs=require("fs"); const x=JSON.parse(fs.readFileSync(0,"utf8")); process.stdout.write(String(x.enabled));' 2>/dev/null || true)

echo "[INFO] qqbot plugin source=${SOURCE_PATH:-N/A} status=${STATUS:-N/A} enabled=${ENABLED:-N/A}"

if [[ "$STATUS" != "loaded" || "$ENABLED" != "true" ]]; then
  echo "[UNKNOWN] qqbot 插件未处于 loaded 状态，无法执行有效发送验证。"
  echo "RESULT=UNKNOWN"
  exit 3
fi

START_TS=$(date +%s)
SEND_OUTPUT=""
SEND_RC=0

set +e
SEND_OUTPUT=$(timeout "${TIMEOUT_SEC}s" openclaw message send \
  --channel qqbot \
  --target "$TARGET" \
  --media "$TEST_FILE" \
  --message "$MESSAGE" \
  --json 2>&1)
SEND_RC=$?
set -e

END_TS=$(date +%s)

echo "[INFO] send rc=$SEND_RC elapsed=$((END_TS-START_TS))s"
echo "[INFO] raw send output:"
printf '%s\n' "$SEND_OUTPUT"

LOG_TAIL=""
if [[ -f "$LOG_FILE" ]]; then
  LOG_TAIL=$(tail -n 240 "$LOG_FILE" 2>/dev/null || true)
else
  echo "[WARN] 日志文件不存在: $LOG_FILE"
fi

if [[ -n "$LOG_TAIL" ]]; then
  echo "[INFO] log tail keywords:"
  printf '%s\n' "$LOG_TAIL" | grep -E 'qqbot|sendMedia|API|retcode|拦截|forbidden|failed|error|file' | tail -n 80 || true
fi

is_success=0
if printf '%s' "$SEND_OUTPUT" | grep -Eq '"messageId"\s*:\s*"?[^"]+'; then
  is_success=1
fi
if [[ $SEND_RC -eq 0 ]] && printf '%s' "$SEND_OUTPUT" | grep -Eq '"error"\s*:\s*null'; then
  is_success=1
fi

if [[ $is_success -eq 1 ]]; then
  echo "[SUCCESS] 文件发送链路看起来成功。"
  echo "RESULT=SUCCESS"
  exit 0
fi

BLOCK_PAT='真实拦截|API Error|retcode|forbidden|permission denied|insufficient|审核|拦截|blocked|sendMedia.*error|/files'
if printf '%s\n%s' "$SEND_OUTPUT" "$LOG_TAIL" | grep -Eiq "$BLOCK_PAT"; then
  echo "[API_BLOCKED] 命中 API 拦截/权限失败特征。"
  echo "RESULT=API_BLOCKED"
  exit 2
fi

echo "[UNKNOWN] 未匹配成功或明确 API 拦截特征。"
echo "RESULT=UNKNOWN"
exit 3
