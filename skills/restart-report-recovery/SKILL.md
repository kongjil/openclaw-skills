---
name: restart-report-recovery
description: OpenClaw 通用“重启后补汇报”技能：在重启前登记任务，重启后自动恢复并补发结果，避免会话断链导致任务无汇报。适用于 gateway/systemd/docker restart、可能被 SIGTERM 掐断的运维脚本，以及任何需要“结果落地后再补回聊天”的流程。
---

# Restart Report Recovery（OpenClaw 通用版）

## 触发场景
- 用户反馈：重启后任务不自动汇报。
- 你将执行可能断链的动作：gateway/systemd/docker 重启、长任务切后台等。
- 你要跑一个可能在当前会话断掉后才出结果的脚本。

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

## 默认入口（优先级从高到低）

### A. 只重启 OpenClaw Gateway：优先用专用入口
```bash
oc-gateway restart-safe <taskId> <summaryPath> "<brief>" [--delay-sec N]
```

等价脚本：
```bash
bash skills/restart-report-recovery/scripts/gateway-restart-safe.sh <taskId> <summaryPath> "<brief>" [--delay-sec N]
```

用途：
- 自动 `register-pending`
- 脱离当前会话起 postcheck
- 执行 `systemctl restart openclaw-gateway.service`
- 重启后自动把 `is-active` / HTTP probe / status 摘要写入 summary

### B. 任意可能断链的命令/脚本：用通用 wrapper
```bash
bash skills/restart-report-recovery/scripts/run-with-pending.sh <taskId> <summaryPath> "<brief>" "<longrunName-or-empty>" -- <command...>
```

用途：
- 先登记 pending
- 再执行任意命令
- 若命令失败且 summary 还没写，会自动补一份失败摘要

### C. 最低层原语：手工三段式
#### 1) 重启前登记
```bash
bash skills/restart-report-recovery/scripts/register-pending.sh <taskId> <summaryPath> "<brief>" [longrunName]
```

#### 2) 执行命令/重启
按你的实际动作执行（gateway/systemd/docker）。

#### 3) 重启后恢复扫描
```bash
bash skills/restart-report-recovery/scripts/recover-pending.sh
```

输出语义：
- `READY <taskId> <summaryPath>`：已有结果，立即向用户补汇报
- `WAIT <taskId> ...`：任务仍运行/暂无结果，告知“继续跟进”

### 4) 自动分发补汇报
```bash
bash skills/restart-report-recovery/scripts/recover-dispatch.sh
```

行为：
- 只处理 `READY` 项
- 读取 summary 文件并输出用户可读补汇报文本
- 成功输出后自动 `close-pending`
- 无可汇报结果时静默退出

### 5) 完成后关闭
```bash
bash skills/restart-report-recovery/scripts/close-pending.sh <taskId>
```

## 推荐流程
- **gateway 单独重启**：直接 `oc-gateway restart-safe ...`
- **脚本里包含 restart**：整条命令包进 `run-with-pending.sh`
- **复杂多阶段流程**：结果先写 `summaryPath`，分发交给恢复链路

## Detached 触发规则（新增硬规则）
- **不要默认在前台 exec 里直接跑 `gateway-restart-safe.sh` / `oc-gateway restart-safe`**；因为 gateway 重启时，承载当前 exec 的链路可能被 SIGTERM 掐断，导致 postcheck 虽已起过，但 summary 没来得及落地。
- 对 gateway safe restart，默认优先：
  1. 使用更稳定的 detached 触发方式（如 `oc-longrun`、systemd-run、nohup 包裹的独立 shell）；
  2. 或确保 postcheck 脱离当前会话/控制组后再执行重启；
  3. 重启后第一时间检查：`summaryPath` 是否已生成、`recover-pending.sh` 是否返回 READY，而不是只看 service active。
- 若前台 exec 因 SIGTERM 中断，但服务已成功重启：
  - 不要立刻判失败；
  - 先检查 summary 是否存在；
  - 若不存在，立即手工补写 summary 并 `close-pending`，把补汇报补齐。

## 建议文案
- READY：`重启后补汇报：任务 <taskId> 已完成，结论如下……`
- WAIT：`重启后补汇报：任务 <taskId> 仍在执行，我会在产出后第一时间补汇报。`

## 规则
- 结果优先落地文件，再发消息。
- 重启类任务默认要登记 pending。
- **不要再裸跑 `systemctl restart openclaw-gateway.service` 作为默认习惯**；默认改用 `oc-gateway restart-safe ...`。
- 同一 taskId 汇报后务必 close，避免重复提醒。
- 不要只把 `recover-pending.sh` 结果打到日志里；要配合 `recover-dispatch.sh` 或等价分发器，真正把 READY 结果送出去。
