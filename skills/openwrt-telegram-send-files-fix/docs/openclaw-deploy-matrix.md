# OpenClaw 部署矩阵（多系统 + 多方式）

> 本文仅基于本地文档 `/root/openclaw/docs` 已确认信息整理，重点覆盖：Linux（Ubuntu/Debian）、macOS、Windows（WSL / 原生 PowerShell）、中国国内 VPS 与国外 VPS 对照。

## 1. 先做系统级判断（推荐顺序）

1. **先定运行环境**：本机长期运行 / VPS 运行 / 容器运行。  
2. **再定服务托管方式**：前台调试 or `openclaw gateway install`（launchd/systemd）or 容器编排。  
3. **最后定渠道与模型**：`openclaw configure` 或 `openclaw config set`。

核心参考：
- 安装总览：`/root/openclaw/docs/install/index.md`
- 平台：`/root/openclaw/docs/platforms/index.md`
- Gateway runbook：`/root/openclaw/docs/gateway/index.md`
- 更新：`/root/openclaw/docs/install/updating.md`

---

## 2. 操作系统建议（结论版）

- **Linux 通用**：Gateway 完整支持，推荐 Node 运行时。`Bun` 不推荐用于 Gateway 生产运行（文档注明 WhatsApp/Telegram bugs）。
- **Ubuntu / Debian（重点）**：最稳妥默认项，尤其是 VPS 与自动化（Ansible 文档前提即 Debian 11+ / Ubuntu 20.04+）。
- **macOS**：有 menu-bar companion，服务托管以 launchd 为主。
- **Windows**：官方建议 **WSL2（Ubuntu 推荐）** 运行 OpenClaw；原生 PowerShell 可安装 CLI，但长期运行 Gateway 仍建议 WSL2 路径。

---

## 3. 部署方式矩阵（核心）

## 3.1 直接源码 / 本机运行（Node）

| 维度 | 说明 |
|---|---|
| 适用场景 | 本机开发、快速验证、单人环境 |
| 典型命令 | `openclaw gateway --port 18789`、`openclaw onboard`、`openclaw doctor` |
| 优点 | 简单、可见性高、调试快 |
| 缺点 | 进程管理/自启要另配；会话退出可能中断 |
| 国内 VPS 推荐度 | 中（建议最终切到服务托管） |
| 日志/升级/重启/持久化 | 日志：`openclaw logs --follow`；升级：`openclaw update`；重启：`openclaw gateway restart`；状态落在 `~/.openclaw` |
| 常见坑 | `gateway.mode` 非 `local` 导致启动阻塞；非 loopback 绑定未配 auth 会被拒绝；端口冲突 `EADDRINUSE` |

已确认点：
- 默认会校验 `gateway.mode=local`（`gateway/index.md`, `cli/gateway.md`）
- 非 loopback bind 需 token/password（`gateway/index.md`, `gateway/troubleshooting.md`）

## 3.2 服务托管：systemd / launchd

| 维度 | Linux/WSL2（systemd user） | macOS（launchd） |
|---|---|---|
| 适用场景 | 长期运行、登出后持续服务 | 本机常驻、伴随菜单栏/本地能力 |
| 安装方式 | `openclaw gateway install` | `openclaw gateway install` |
| 控制命令 | `systemctl --user ...` + `openclaw gateway status/restart` | `launchctl kickstart ...` + `openclaw gateway status/restart` |
| 优点 | 自启动、重启可控、日志链路稳定 | 与 macOS 生态一致，配套 app 能力 |
| 缺点 | 需处理 user lingering（Linux） | 需关注 profile 对应 label |
| 国内 VPS 推荐度 | **高（Ubuntu/Debian 首选）** | 低（VPS 几乎不用） |
| 日志/升级/重启/持久化 | Linux 常用 `journalctl --user` + `openclaw logs --follow`；升级后建议 `openclaw doctor` + `openclaw gateway restart` | launchd 由 CLI/应用管理，升级后同样执行 doctor + restart |
| 常见坑 | 未启用 lingering 导致退出会话后服务不持续；service 配置漂移需 `openclaw gateway install --force` 修复 | label/profile 混淆，重启了错误实例 |

已确认点：
- Linux/WSL2 使用 systemd user service（`platforms/index.md`, `platforms/linux.md`, `platforms/windows.md`）
- macOS LaunchAgent label：`ai.openclaw.gateway` / `ai.openclaw.<profile>`（`gateway/index.md`, `platforms/macos.md`）

## 3.3 Docker / Docker Compose

| 维度 | 说明 |
|---|---|
| 适用场景 | 容器化隔离、跨机一致化、快速迁移 |
| 典型命令 | `./docker-setup.sh`、`docker compose up -d openclaw-gateway`、`docker compose run --rm openclaw-cli onboard` |
| 优点 | 环境可复制；可通过 volume/bind 管理持久化 |
| 缺点 | 容器/卷/宿主权限映射更复杂；网络与浏览器依赖需单独处理 |
| 国内 VPS 推荐度 | 中-高（会 Docker 的团队可选） |
| 日志/升级/重启/持久化 | compose 控制生命周期；`OPENCLAW_HOME_VOLUME` 可持久化 `/home/node`；config/workspace 可挂载到宿主 |
| 常见坑 | 忘记重跑 `docker-setup.sh` 导致 extra compose 未更新；宿主目录权限不匹配（文档给出 `chown 1000:1000` 示例）；非 loopback 暴露时未配置 auth |

已确认点：
- Docker 是可选方案，非必需（`install/docker.md`）
- 容器 Gateway 与 Agent Sandbox 是两件事（`install/docker.md`）

## 3.4 Podman（rootless）

| 维度 | 说明 |
|---|---|
| 适用场景 | 偏好 rootless 容器、Docker 替代 |
| 典型命令 | `./setup-podman.sh`、`./scripts/run-openclaw-podman.sh launch`、`./setup-podman.sh --quadlet` |
| 优点 | rootless；可选 Quadlet 接入 systemd user 服务 |
| 缺点 | subuid/subgid、machine user service、权限模型门槛更高 |
| 国内 VPS 推荐度 | 中（熟悉 Podman 才推荐） |
| 日志/升级/重启/持久化 | Quadlet: `journalctl --machine openclaw@ --user -u openclaw.service -f`；容器删了也可保留宿主 config/workspace |
| 常见坑 | `gateway.mode=local` 缺失阻塞启动；`/etc/subuid` `/etc/subgid` 未配置导致 rootless 失败；UID/GID 不一致触发 EACCES |

## 3.5 Ansible

| 维度 | 说明 |
|---|---|
| 适用场景 | 远程 Ubuntu/Debian 生产部署、要安全基线与可重复交付 |
| 入口 | `openclaw-ansible`（文档明确该仓库为 source of truth） |
| 优点 | 自动化硬化（UFW + Tailscale + systemd + Docker sandbox 相关） |
| 缺点 | 需要 Ansible 体系与运维流程 |
| 国内 VPS 推荐度 | 高（多机/正式环境） |
| 日志/升级/重启/持久化 | 网关运行在主机，日志用 `journalctl -u openclaw -f`；后续更新仍走标准 Updating 流程 |
| 常见坑 | 把“Docker 安装”误解成“Gateway 必须跑容器内”；实际上文档明确网关在 host，Docker 主要用于 sandbox |

## 3.6 Nix

| 维度 | 说明 |
|---|---|
| 适用场景 | 已有 Nix / Home Manager 体系、要求声明式可复现 |
| 入口 | `nix-openclaw`（文档明确该仓库为 source of truth） |
| 优点 | 配置与依赖可复现，适合长期一致化 |
| 缺点 | 学习曲线高；需要理解 Nix Mode 与状态路径 |
| 国内 VPS 推荐度 | 中（团队具备 Nix 经验再上） |
| 日志/升级/重启/持久化 | 按 nix-openclaw 约定；文档强调 `OPENCLAW_CONFIG_PATH` / `OPENCLAW_STATE_DIR` 明确化 |
| 常见坑 | macOS GUI 环境变量继承与 shell 不一致，需要按文档设置 nix mode |

## 3.7 Bun（实验）

| 维度 | 说明 |
|---|---|
| 适用场景 | 本地开发提速、TypeScript 直跑实验 |
| 优点 | 本地迭代快 |
| 缺点 | 文档明确：**不推荐 Gateway 生产运行**（WhatsApp/Telegram bugs） |
| 国内 VPS 推荐度 | 低（生产不建议） |
| 日志/升级/重启/持久化 | 作为开发 runtime 可用；生产升级与守护建议回到 Node 路径 |
| 常见坑 | 生命周期脚本信任机制（`bun pm trust`）导致依赖行为与 pnpm 不同 |

---

## 4. 平台 × 部署方式建议速查

- **Ubuntu / Debian VPS（中国/海外通用）**：
  1) Node + `openclaw gateway install`（首选）
  2) Docker Compose（次选）
  3) Ansible（多机/正式环境首选）
- **Linux 个人机**：Node 直跑调试 → 稳定后切 systemd user。
- **macOS**：以 launchd + companion app 为主。
- **Windows**：
  - 推荐：WSL2(Ubuntu) 内按 Linux 路径部署（含 systemd user）。
  - 原生 PowerShell：可安装/维护 CLI，但不作为长期 Gateway 主运行形态的优先选项。

---

## 5. 更新、重启、日志（统一操作基线）

推荐统一基线：

```bash
openclaw doctor
openclaw gateway status
openclaw logs --follow
openclaw update
openclaw gateway restart
```

关键事实（本地文档已确认）：
- `openclaw update` 是官方“安全更新流”入口之一，默认会触发重启（可 `--no-restart`）。
- `openclaw doctor` 会做配置迁移、服务检查与修复建议。
- 服务环境下优先用 `openclaw gateway restart`，不要粗暴 kill PID。

