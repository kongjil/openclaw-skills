## 一号灵机：Gateway 重启规范

- 一号灵机当前架构是 **systemd system 级服务**托管 OpenClaw Gateway。
- **所有重启一律用：**
  - `systemctl restart openclaw-gateway.service`
- **不要用：**
  - `openclaw gateway run --force`

原因：`run --force` 容易绕开 systemd，导致多实例/抢端口/状态目录不一致等混乱。

## OpenClaw 自修/交叉修原则

- 当修复动作会影响**当前承载本会话的 OpenClaw/Gateway**（如 build、重启 gateway、替换 dist、核心配置热切换）时，**优先从另一台机子发起并收尾**。
- 推荐默认策略：
  - **修一号核心服务 → 尽量从二号发起**
  - **修二号核心服务 → 尽量从一号发起**
- 原因：本机自修时，一旦执行 `systemctl restart openclaw-gateway.service`，当前会话所在的执行链/agent 链路容易一起被 SIGTERM 掐断，常导致“build 跑完、restart 已发起，但最后 active/status 确认缺失”，还要额外补查。
- 因此：
  - **只读排查 / 普通文件改动** 可本机直接做
  - **会影响当前 OpenClaw 存活的核心修复** 优先交叉修，才能完整跑完“改动 → build → restart → status/log 验证”闭环


## GitHub 身份与提交流程

- 统一 GitHub push 身份：`kongjil`（GitHub SSH 账号）
- 统一 Git commit 作者/提交者：`kongji <67133458+kongjil@users.noreply.github.com>`
- 一号机：可直接通过 GitHub SSH 推送。
- 二号机：提交到 GitHub 时，统一复用一号机的 GitHub SSH 能力，不单独走二号机自己的 GitHub 凭据。

- 默认 GitHub 提交分支：`kong`
- 若仓库需要保留上游基线，则 `main` 优先保持对齐上游；自定义/修复版本默认落到 `kong` 分支（或 `kong/*` 命名空间）。
- 本次 qqbot 实例：修复分支为 `kong/qqbot-hardening-20260307`，`main` 已对齐回上游 `sliverp/qqbot:main`。

- 一号机、二号机默认长任务执行体系：`oc-longrun v2`
- 规则：短任务直接 exec；长任务/易被 SIGTERM 掐断的任务默认走 `oc-longrun v2`。
- 典型长任务：`npm ci`、`npm run build`、`git clone`、`rsync`、长 SSH 运维脚本、长输出命令。

## 2026-03-07 会话稳定性修复（webchat / session / compaction）

- 这次 webchat 长时间转圈、`/new` 变慢、回跳旧对话、最终 `error 1033`，不是单一旧问题复发，而是三类问题叠加：
  1. `Compaction wait timed out after 90000ms`
  2. `lane wait exceeded`
  3. session 文件 header `id` 与文件名 basename 错配
- 已提交并生效的修复：
  - `d539670de9` `fix: repair session header id mismatch and ignore missing daily memory reads`
  - `a3cc5fdfd5` `fix: degrade compaction wait timeouts to best-effort continuation`
- 已生效行为变化：
  - session 文件首行 header 合法但 `header.id !== 文件名` 时自动修正
  - `/new` 启动读取 `memory/YYYY-MM-DD.md` 若只是 daily memory 缺失 `ENOENT`，不再放大成会话异常
  - `waitForCompactionRetry()` 若卡到 compaction timeout，不再默认把整次 run 和整条 session lane 一起拖死，而是 best-effort continuation
- 重要认识：
  - `lane wait exceeded` 往往是**后果**，不是第一根因
  - 真正要先看的是 `journalctl -u openclaw-gateway.service` 时间窗里的 compaction / timeout / session repair 信号
  - 本机执行 `systemctl restart openclaw-gateway.service` 时，发起重启的 exec 很可能被 SIGTERM 掐断；要用 systemd 状态和 journal 回读确认是否实际成功
