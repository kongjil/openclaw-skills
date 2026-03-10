---
name: restart-report-recovery
description: OpenClaw 通用“重启后补汇报”技能：在重启前登记任务，重启后自动恢复并补发结果，避免会话断链导致任务无汇报。
---

# Restart Report Recovery（OpenClaw 通用版）

## 触发场景
- 用户反馈：重启后任务不自动汇报。
- 你将执行可能断链的动作：gateway/systemd/docker 重启、长任务切后台等。

## 目标
把“执行链路”和“汇报链路”解耦：
1) 重启前登记 pending；
2) 重启后扫描并补汇报；
3) 汇报后关闭 pending，避免重复播报。

## 目录与状态文件（自动探测）
脚本按以下顺序探测 workspace：
1. `$OPENCLAW_WORKSPACE`
2. `$HOME/.openclaw/workspace`
3. 基于脚本位置推断（`skills/<skill>/scripts` 向上两级）

pending 存储：
- `<workspace>/memory/restart-report-pending.jsonl`

## 标准流程

### 1) 重启前登记
```bash
bash scripts/register-pending.sh <taskId> <summaryPath> "<brief>" [longrunName]
```

参数说明：
- `taskId`：唯一任务 id（如 `20260311-frontend-refresh-fix`）
- `summaryPath`：结果文件路径（建议绝对路径）
- `brief`：任务简介
- `longrunName`：可选，若任务使用 oc-longrun 则填其任务名

### 2) 执行重启
按你的实际动作执行（gateway/systemd/docker）。

### 3) 重启后恢复扫描
```bash
bash scripts/recover-pending.sh
```

输出语义：
- `READY <taskId> <summaryPath>`：已有结果，立即向用户补汇报
- `WAIT <taskId> ...`：任务仍运行/暂无结果，告知“继续跟进”

### 4) 完成后关闭
```bash
bash scripts/close-pending.sh <taskId>
```

## 建议文案
- READY：`重启后补汇报：任务 <taskId> 已完成，结论如下……`
- WAIT：`重启后补汇报：任务 <taskId> 仍在执行，我会在产出后第一时间补汇报。`

## 规则
- 结果优先落地文件，再发消息。
- 重启类任务默认要登记 pending。
- 同一 taskId 汇报后务必 close，避免重复提醒。
