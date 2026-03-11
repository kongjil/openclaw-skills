# OpenClaw Skills Monorepo

赛博仙人写的/修复的 OpenClaw 相关技能与工具。
Unified monorepo for OpenClaw skills and related tooling.

## Skills Index

| Skill | 简介 | Docs |
|---|---|---|
| `auto-work (task-reminder)` | 命令式自动工作督办：识别挂机、假推进、检讨书循环；长时间空转时升级为恢复执行判定。 | [README](skills/task-pulse-reminder/README.md) |
| `qqbot` | qqbot日志等位置隐私加强+修复文件发送问题。 | [README (EN)](skills/qqbot/README.md) · [README (ZH)](skills/qqbot/README.zh.md) |
| `openwrt-telegram-send-files-fix` | Telegram 文件发送修复方案与技能集合 | [README](skills/openwrt-telegram-send-files-fix/README.md) |
| `code-moment-codex-switch` | 代码时刻：检测编码/部署任务后切入 Codex 工作流，并可联动长任务督办与一次受控恢复。 | [README](skills/code-moment-codex-switch/README.md) · [SKILL](skills/code-moment-codex-switch/SKILL.md) |

## Directory Layout

```text
skills/
  task-pulse-reminder/
  qqbot/
  openwrt-telegram-send-files-fix/
  code-moment-codex-switch/
```

## Install Pattern

Clone repo, then copy needed skill folder into your OpenClaw skills directory.

```bash
# example
cp -a skills/task-pulse-reminder ~/.openclaw/workspace/skills/
```
