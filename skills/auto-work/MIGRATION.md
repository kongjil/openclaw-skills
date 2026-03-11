# auto-work Migration Guide

`auto-work` is the new unified entrypoint for the old reminder-first and code-workbench-first workflows.

## Replaced skills

The following old skills are now considered replaced by `auto-work`:
- `code-moment-switch-model`
- `code-moment-codex-switch`
- `task-pulse-reminder`

## Mental model change

Old model:
- one skill for code execution
- one skill for reminder/watchdog
- user had to understand when to combine them

New model:
- user says `开启自动工作 / 持续做完 / 不要只监督`
- `auto-work` decides whether the task should stay in watch mode or upgrade to execute mode
- internal watchdog / execution / recovery logic stays inside one product surface

## Recommended migration

Use `auto-work` for all new long tasks, especially when the old workflow would have required:
- code-moment + task-pulse-reminder together
- repeated 5-minute nudges
- explicit “do not stop until finished” instructions

## Trigger migration examples

Old phrasing:
- `开代码时刻`
- `每5分钟提醒我继续`
- `开监工`

New phrasing:
- `开启自动工作`
- `这个任务持续做完`
- `不要只监督，直接做完`

## Compatibility note

The old skills are removed from this machine. Keep user-facing language centered on `auto-work` only.
