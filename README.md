# OpenClaw Skills Monorepo

赛博仙人写的/修复的OpenClaw 相关技能与工具。
Unified monorepo for OpenClaw skills and related tooling.

## Skills Index

| Skill | 简介 | Docs |
|---|---|---|
| `auto-work (task-reminder)` | 自动工作：每 5 分钟状态检测，工作中静默，仅在非工作态提醒。 | [README](skills/task-pulse-reminder/README.md) |
| `qqbot` | qqbot日志等位置隐私加强+修复文件发送问题。 | [README (EN)](skills/qqbot/README.md) · [README (ZH)](skills/qqbot/README.zh.md) |
| `openwrt-telegram-send-files-fix` | Telegram 文件发送修复方案与技能集合 | [README](skills/openwrt-telegram-send-files-fix/README.md) |
| `code-moment-codex-switch` | 代码时刻：检测编码/部署任务后切入 Codex 工作流。 | [README](skills/code-moment-codex-switch/README.md) · [SKILL](skills/code-moment-codex-switch/SKILL.md) |

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

## Quick Install (One-Click)

### auto-work (task-reminder) / 自动工作
```bash
curl -fsSL https://raw.githubusercontent.com/kongjil/openclaw-skills/main/install-auto-work-task-reminder.sh | bash
```

### code-moment-codex-switch / 代码时刻
```bash
curl -fsSL https://raw.githubusercontent.com/kongjil/openclaw-skills/main/install-code-moment-codex-switch.sh | bash
```
