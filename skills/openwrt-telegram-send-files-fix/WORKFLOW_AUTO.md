# WORKFLOW_AUTO.md

本文件用于在「上下文压缩/重置」后恢复工作流程。

## 默认排障工作流（Gateway 不回消息）
1. 先抓最近 2-10 分钟 journalctl 关键字（discord/telegram/qqbot + timed out/slow listener/lane wait/token_mismatch）。
2. 优先处理：
   - DiscordMessageListener timed out / Slow listener
   - embedded run timeout / lane wait exceeded
   - gateway token mismatch / unauthorized token_mismatch
   - Telegram 409 Conflict / webhook 异常
3. 恢复动作：只用 systemd 重启：`systemctl restart openclaw-gateway.service`。
4. 配置/日志对外展示必须打码 token/secret。
