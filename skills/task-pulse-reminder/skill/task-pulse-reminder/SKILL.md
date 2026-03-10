---
name: auto-work-task-reminder
description: Intelligent 5-minute task watchdog for OpenClaw. Checks whether work is actively progressing before reminding; reminds only on idle/blind-restart/non-working states. / 智能 5 分钟任务看门狗：先检测是否在推进任务，只有在挂机/盲重启/非工作态时才提醒。
---

# Auto-Work (Task-Reminder) / 自动工作

## When to use / 何时使用
- 用户希望“定时盯任务”，但不希望高频打断。
- 用户反馈“提醒太密导致低信息量回执”。
- 目标是：**提醒只在非工作态触发**，工作中静默。

## Goal / 目标
创建一个每 5 分钟触发的 **状态检测型** 提醒，而不是固定催促：
- 每 5 分钟先检测当前会话状态
- 若正在推进任务（有实质产出或处于有效长验证）→ 不提醒
- 若挂机/盲目重启/空转/低信息复读 → 发送提醒

## Create watchdog / 创建看门狗
使用 `cron.add`：
- `sessionTarget: "main"`
- `payload.kind: "systemEvent"`
- `schedule.kind: "cron"`
- `schedule.expr: "*/5 * * * *"`
- `schedule.tz: "Asia/Shanghai"`
- name: `自动工作-5分钟状态检测`

建议 event 文本（直接可用）：

`【5分钟自动工作检测】先做状态检测再决定是否提醒：1) 检查最近执行是否有实质进展（代码改动/命令结果/验证结论/可交付结果）；2) 若正在推进，保持静默并继续执行；3) 若处于挂机、盲目重启、重复“继续中”无新结果、或明显偏离任务目标，立刻发送一次“请回到任务并给出新产出”的提醒；4) 有新产出后恢复静默；5) 用户明确说“完成/停止提醒”即关闭本任务。`

## Detection policy / 检测策略
每次触发按以下顺序判断：

1. **完成态**（立即关闭）
   - 用户明确说：完成 / 结束 / 停止提醒 / 不用继续

2. **工作态（静默）**
   满足任一即可视为工作中：
   - 最近有文件改动、commit、补丁
   - 最近有有效命令输出并带新结论
   - 最近有构建/测试/验证结果（成功或失败都算有效进展）
   - 最近回复包含“改了什么 + 结果是什么 + 下一步”
   - **处于长验证/长读取进行中（重点）**：
     - 已明确启动耗时步骤（build/test/deploy前检查/日志追踪/大文件读取）
     - 且当前无失败结论、无卡死证据
     - 且仍在合理窗口内（默认 20 分钟）
     - 该情形即使 5 分钟内无新输出，也按“工作态”静默，不触发催促

3. **非工作态（提醒）**
   满足任一则提醒一次：
   - 连续多次仅“我还在继续/处理中”等低信息回复
   - 重复重启/重复同命令但无新结论（盲重启）
   - 超过长验证窗口且无结果、无推进证据（空转）
   - 行为偏离当前任务目标

## Avoid duplicates / 防重复
创建前先 `cron.list`：
- 已有同类启用任务则复用，不重复创建。

## Stop watchdog / 关闭看门狗
用户说“任务完成/结束/不用继续/停止提醒”：
- `cron.list` 找到 job
- `cron.update(enabled=false)` 或 `cron.remove`
- 回执关闭结果

## Reply templates / 回执模板
- Created:
  - `已开启“自动工作(task-reminder)5分钟状态检测”（jobId: ...）：仅在非工作态提醒，工作中静默。`
- Reused:
  - `已存在自动工作提醒（jobId: ...），继续复用。`
- Alert fired:
  - `【自动工作提醒】你当前处于非工作态（低信息回执/空转/盲重启），请立即给出新的实质产出（改动/结果/验证）。`
- Closed:
  - `已关闭自动工作提醒。`
