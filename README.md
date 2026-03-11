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
| `restart-report-recovery` | 重启后补汇报：为 gateway/systemd/docker/断链脚本登记 pending、落地 summary，并在重启后补发结果。 | [README](skills/restart-report-recovery/README.md) · [SKILL](skills/restart-report-recovery/SKILL.md) |

## Recent hard-won lesson / 最近新增经验

- `code-moment-codex-switch` 现在补充了一条很值钱的 OpenClaw 排障经验：
  如果 `edit` / `read` 对一个**明明存在的仓库文件**报 `File not found`，先查 **resolved agent workspace root**，不要先怀疑文件丢了。
- 这类问题的典型根因是：`agents.defaults.workspace` 比真实 repo 根更窄，导致 host edit/read 把目标文件挡在 workspace 边界外。
- 技能里现在明确要求先检查：
  - 在线进程 `MainPID`
  - `ExecStart`
  - `/proc/$pid/cwd`
  - 以及 `src / dist / node_modules` 三层的真实执行链
- 英文版简述：when a repo file exists on disk but OpenClaw says `File not found`, check the **workspace root boundary** before patching the wrong layer.

## Directory Layout

```text
skills/
  task-pulse-reminder/
  qqbot/
  openwrt-telegram-send-files-fix/
  code-moment-codex-switch/
  restart-report-recovery/
```

## Install Pattern

Clone repo, then copy needed skill folder into your OpenClaw skills directory.

```bash
# example
cp -a skills/task-pulse-reminder ~/.openclaw/workspace/skills/
```
