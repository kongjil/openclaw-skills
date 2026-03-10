# OpenClaw 排障结论（message target 校验 + 长任务 SIGTERM）

日期：2026-03-09

## 1) message 工具报错 `Use `target` instead of `to`/`channelId`.` 的根因

### 现象
- 在调用 `message` 工具发送（尤其含文件/附件）时，即使已经传了 `target`，仍报：
  - `Use `target` instead of `to`/`channelId`.`

### 真正校验位置
- `src/infra/outbound/channel-target.ts` -> `applyTargetToParams()`
- 原逻辑把 `to`/`channelId` 只要是 **string 类型**就视为 legacy 参数存在：
  - `typeof params.args.channelId === "string"`
- 而 message 工具调用中，模型常把可选字段也填成空串（`""`），导致被误判 legacy 参数冲突。

### 参数期望形态
- 新口径：
  - 目标一律用 `target`（如 `user:xxx` / `1824254227` / `@username` 等）
  - 不应同时携带有效 `to`/`channelId`
- 兼容上，空串 `""` 不应算“有效 legacy 参数”。

### 已落地修复
- 修改：`/root/openclaw/src/infra/outbound/channel-target.ts`
- 变更点：legacy 参数存在判定从“是否 string”改为“trim 后是否非空”。
  - `hasLegacyTo = legacyTo.length > 0`
  - `hasLegacyChannelId = legacyChannelId.length > 0`

### 最小验证
- 新增测试：`/root/openclaw/src/infra/outbound/message-action-runner.test.ts`
  - `ignores empty legacy channelId when target is provided`
- 运行：
  - `npx vitest run src/infra/outbound/message-action-runner.test.ts -t "empty legacy channelId"`
  - `npx vitest run src/infra/outbound/message-action-runner.test.ts -t "legacy to parameter|empty legacy channelId"`
- 结果：通过。

---

## 2) 长执行/源码扫描常被 SIGTERM 打断：根因与放大器

### 根因（Root Cause）
- OpenClaw 的 `exec` 运行链路会把父进程信号桥接到子进程：
  - `src/process/child-process-bridge.ts`
  - 收到 `SIGTERM/SIGINT/...` 时会 `child.kill(signal)`。
- 因此，**当承载会话的 gateway/agent 进程被重启或停止**（包括运维动作触发），前台 exec 的子任务会被同步终止。

### 放大器（Amplifiers）
1. 在“同机自修”时执行 `openclaw gateway restart` / systemd restart，最容易把当前对话执行链路一并掐断。
2. 长任务直接挂在前台 exec（build、长 grep、长日志、rsync、长 SSH）暴露窗口更长。
3. `exec` 虽支持 background/process，但本质仍依赖当前 gateway 会话存活；遇到 gateway 重启仍会中断。

### 最终表现（Error Code / Surface）
- 常见外显：`Exec failed (..., signal SIGTERM)`
- 需要区分：
  - A. 发起动作的 exec 会话被掐断（常见）
  - B. systemd 单元真正启动失败（需用 `systemctl is-active` + `journalctl` 复核）

### 修复/规避方案（已固化）
- 长任务默认改走 `oc-longrun v2`（`systemd-run` transient unit 脱离前台会话）：
  - `oc-longrun start <name> <command...>`
  - `oc-longrun status <name>`
  - `oc-longrun logs <name> -n 200`
- 该规则已在工作区 `AGENTS.md / TOOLS.md / MEMORY.md` 系列中固化。

### 快速 SOP
1. 一旦看到 `Exec failed ... SIGTERM`，先别判失败。
2. 立刻查：
   - `systemctl is-active openclaw-gateway.service`
   - `journalctl -u openclaw-gateway.service -n 200 --no-pager`
3. 长任务改为：
   - `/root/.openclaw/bin/oc-longrun start <name> <cmd...>`
4. 若涉及 gateway 核心修复，优先“交叉修”（另一台机器发起）。

