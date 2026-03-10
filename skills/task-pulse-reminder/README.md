# auto-work (task-reminder) / 自动工作

- **auto-work (task-reminder)**
- 中文名：**自动工作**

A bilingual OpenClaw skill pack with **5-minute status checks** (not blind nudging).  
It reminds only when the agent is in non-working states (idle / blind-restart / low-information loop).

一个双语 OpenClaw 技能包：采用 **5 分钟状态检测**（不是盲目催促）。  
仅在“非工作态”（挂机 / 盲重启 / 低信息复读）时提醒；正在推进任务时保持静默。

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
- Check task progress first, then decide whether to remind
- Stay silent when real work is progressing
- Keep silent during long-running validation/read steps (default 20-min window)
- Alert only on non-working states
- Avoid duplicate jobs
- Stop when user says done

- 使用 cron 创建每 5 分钟看门狗
- 先检测任务状态，再决定是否提醒
- 有实质进展时静默
- 长验证/长读取进行中（默认 20 分钟窗口）也静默
- 仅在非工作态提醒
- 自动防重
- 用户说完成后关闭

## Default schedule / 默认频率
- Every 5 minutes (`*/5 * * * *`)

## Repository structure / 仓库结构
- `skill/task-pulse-reminder/SKILL.md`
- `install-task-pulse-reminder.sh`
- `README.md`
