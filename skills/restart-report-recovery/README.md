# restart-report-recovery

OpenClaw 通用“重启后补汇报”技能。

## 解决什么问题
当 gateway / systemd / docker / 脚本重启导致当前会话断链时，避免“任务做完了但聊天里没有补汇报”。

核心能力：
- 重启前登记 pending
- 重启后生成 summary
- 通过 recover + dispatch 补发结果
- 汇报后自动 close pending

## 重点规则
- 不要默认裸跑 `systemctl restart ...`
- Gateway 重启优先：
  - `oc-gateway restart-safe <taskId> <summaryPath> "<brief>"`
- 通用断链命令优先：
  - `bash skills/restart-report-recovery/scripts/run-with-pending.sh <taskId> <summaryPath> "<brief>" "<longrunName-or-empty>" -- <command...>`

## 新增稳定性规则（2026-03-11）
- **不要默认在前台 exec 里直接跑 safe restart**，否则 gateway 重启时当前 exec 可能被 SIGTERM 掐断，导致：
  - pending 已登记
  - 服务已成功重启
  - 但 postcheck / summary 没落地
- 现在脚本默认优先用更稳定的 detached 方式起 postcheck：
  - `systemd-run`
  - 回退：`setsid + nohup`
- 验收时不能只看 service active，还要看：
  - `summaryPath` 是否生成
  - `recover-pending.sh` 是否返回 READY

## 文件
- `SKILL.md`
- `scripts/gateway-restart-safe.sh`
- `scripts/systemctl-restart-safe.sh`
- `scripts/run-with-pending.sh`
- `scripts/recover-pending.sh`
- `scripts/recover-dispatch.sh`
- `scripts/register-pending.sh`
- `scripts/close-pending.sh`
