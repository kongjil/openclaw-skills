# Lingji1 gateway policy — systemd only

Date: 2026-03-12
Host: lingji1

## Final decision
Lingji1's OpenClaw gateway is **systemd-only**.

Allowed management scope:
- `systemctl start openclaw-gateway.service`
- `systemctl stop openclaw-gateway.service`
- `systemctl restart openclaw-gateway.service`
- `systemctl status openclaw-gateway.service`
- `journalctl -u openclaw-gateway.service ...`

## Forbidden paths
The following paths are no longer allowed for Lingji1 gateway management:
- `systemctl --user ... openclaw-gateway.service`
- manual foreground runs such as `openclaw gateway run`
- direct runs such as `node dist/index.js gateway ...`
- any user-scope, nohup, tmux, shell-background, or ad-hoc launch path for the gateway

## Required refusal behavior
If anyone attempts to operate Lingji1 gateway with non-systemd-level commands, the request must be refused and redirected.

Required wording (Chinese preferred):
- 「一号机 gateway 现在只允许 systemd 级别管理；其他级别启动/重启指令已禁用，请改用 systemctl 管理 system 级 openclaw-gateway.service。」

## Why
Reason: Lingji1 previously had both user-scope and system-scope gateway services, which caused:
- duplicate gateway processes
- port 18789 conflicts
- repeated restart loops
- repeated Telegram restart/self-check notifications

## Current enforcement
- user-scope gateway unit removed
- notify polling timer disabled
- unsupervised gateway starts are rejected
- rogue gateway processes are auto-cleaned after systemd start
