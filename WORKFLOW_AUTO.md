# WORKFLOW_AUTO.md

## Lingji1 special rule: gateway is systemd-only

For Lingji1, OpenClaw gateway management is restricted to **systemd (system scope) only**.

Allowed commands:
- `systemctl start openclaw-gateway.service`
- `systemctl stop openclaw-gateway.service`
- `systemctl restart openclaw-gateway.service`
- `systemctl status openclaw-gateway.service`
- `journalctl -u openclaw-gateway.service ...`

Forbidden commands / paths:
- `systemctl --user ... openclaw-gateway.service`
- `openclaw gateway run`
- `node dist/index.js gateway ...`
- any manual, nohup, tmux, background-shell, or non-systemd launch path for Lingji1 gateway

Required behavior:
- If asked to use a non-systemd-level command for Lingji1 gateway, refuse.
- Redirect to systemd-level management only.
- Use this exact Chinese guidance when appropriate:
  - 「一号机 gateway 现在只允许 systemd 级别管理；其他级别启动/重启指令已禁用，请改用 systemctl 管理 system 级 openclaw-gateway.service。」
