# auto-work (task-reminder) / 自动工作

- **auto-work (task-reminder)**
- 中文名：**自动工作督办**

A bilingual OpenClaw skill pack for **command-style work supervision**, not soft nudging.  
It detects idle work, fake progress, rhetoric-only replies, and long stalled execution chains. When needed, it escalates from evidence checks to **recover-execution judgment**.

一个双语 OpenClaw 技能包，用于**命令式工作督办**，不是温和催促。  
它会识别挂机、假推进、纯话术回复，以及长时间断链空转；必要时会从证据检测升级到**恢复执行判定**。

## Install / 安装
```bash
curl -fsSL https://raw.githubusercontent.com/kongjil/openclaw-skills/main/install-auto-work-task-reminder.sh | bash
```

(仓库内脚本方式)
```bash
bash install-task-pulse-reminder.sh
```

Custom skills directory / 自定义安装目录：
```bash
bash install-task-pulse-reminder.sh /path/to/.openclaw/workspace/skills
```

## What this skill does / 技能能力
- Create a recurring 5-minute watchdog cron job
- Treat **no evidence = no progress**
- Detect fake progress, rhetoric loops, apology/promise-only replies
- Stay silent when real work evidence exists
- **When cross-agent history is available, check related subagent/codex session evidence before declaring “no progress”**
- Escalate long stalled tasks into **recover-execution judgment**
- Distinguish between:
  - recoverable stalled tasks
  - input-missing / context-polluted tasks that should not auto-recover
- Avoid duplicate jobs
- Stop when user says done

- 使用 cron 创建每 5 分钟督办任务
- 执行 **无证据 = 无推进** 规则
- 识别假推进、检讨书循环、只有认错/承诺的空转回复
- 有真实推进证据时保持静默
- **若已具备跨 agent 历史读取能力，督办前必须先检查相关 subagent/codex 子会话证据，再决定是否判定未推进**
- 对长时间卡住的任务升级为**恢复执行判定**
- 区分：
  - 可以恢复执行的断链任务
  - 不应自动恢复、应补输入或重开上下文的任务
- 自动防重
- 用户说完成后关闭

## Default schedule / 默认频率
- Every 5 minutes (`*/5 * * * *`)

## Repository structure / 仓库结构
- `skill/task-pulse-reminder/SKILL.md`
- `install-task-pulse-reminder.sh`
- `README.md`
