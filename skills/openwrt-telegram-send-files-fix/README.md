# OpenClaw Skill: Telegram 文件发送修复 / Telegram File-Send Fix

## 中文

这个仓库只保留 **Telegram attachment / file 发送修复** 相关 skill。

### 包含内容
- `skills/telegram-file-send-fix/SKILL.md`

### 适用问题
- Telegram 文本发送正常，但 attachment/file 失败
- legacy target 空字段导致附件路由异常
- 需要快速确认、修复并回归验证 Telegram 文件发送链路

### 对应修复线索
- `6e5c3ff67b fix(message): tolerate empty legacy target fields for attachment sends`

### 使用方式
如果你在排查或修复 OpenClaw 的 Telegram 文件发送问题，直接阅读：
- `skills/telegram-file-send-fix/SKILL.md`


---

## English

This repository contains only the **Telegram attachment / file send fix** skill for OpenClaw.

### Included
- `skills/telegram-file-send-fix/SKILL.md`

### When to use
- Telegram text messages work, but attachment/file sends fail
- Empty legacy target fields break attachment routing
- You need a short, practical runbook for confirming, fixing, and verifying Telegram file-send behavior

### Reference fix
- `6e5c3ff67b fix(message): tolerate empty legacy target fields for attachment sends`

### Usage
If you are troubleshooting or fixing Telegram file sends in OpenClaw, read:
- `skills/telegram-file-send-fix/SKILL.md`

