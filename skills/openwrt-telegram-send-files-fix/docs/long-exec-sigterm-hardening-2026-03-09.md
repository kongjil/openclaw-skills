# 长执行/长扫描 SIGTERM 打断：最小止血与稳妥路径（2026-03-09）

## 因果链

- **根因（Root Cause）**：OpenClaw exec 链路会在父进程收到信号时向子进程转发（见 `src/process/child-process-bridge.ts`）。
- **放大器（Amplifier）**：长任务挂在前台 exec，且同机自修时常伴随 gateway/systemd 重启。
- **最终现象（Error Surface）**：`Exec failed ... signal SIGTERM` 或 `Command aborted by signal SIGTERM`。

## 本次最小落地修复

- 代码位于：`src/agents/bash-tools.exec-runtime.ts`
- 当 exec 因 `SIGTERM` 失败时，错误信息内追加恢复提示：
  - 解释这通常与 gateway/session 重启/断连有关
  - 给出 `oc-longrun v2` 的标准替代命令

## 最小验证

1. 单测：`src/agents/bash-tools.exec-runtime.sigterm-guidance.test.ts`  
   - 验证 SIGTERM 失败时包含 `oc-longrun start <name> <command...>` 提示。
2. 实跑：
   - `oc-longrun start sigterm-proof-20260309 bash -lc 'echo begin; sleep 2; echo done'`
   - `oc-longrun inspect sigterm-proof-20260309`
   - `oc-longrun logs sigterm-proof-20260309 -n 80`
   - 结果：任务成功、日志完整，流程可作为长任务默认通路。

## 执行建议（SOP）

- 出现 `SIGTERM` 先判“承载链路被掐断”而非任务逻辑失败。
- 先补查：
  - `systemctl is-active openclaw-gateway.service`
  - `journalctl -u openclaw-gateway.service -n 200 --no-pager`
- 长任务改走：
  - `/root/.openclaw/bin/oc-longrun start <name> <cmd...>`
  - `/root/.openclaw/bin/oc-longrun status <name>`
  - `/root/.openclaw/bin/oc-longrun logs <name> -n 200`
