# OpenClaw 中国国内 VPS/服务器部署实操（含海外对照）

> 本文聚焦中国国内 VPS 场景，给出可执行顺序与分支判断；结论仅基于本地 docs 已确认信息。

## 1. 先定目标架构

推荐默认架构（国内 VPS）：
- VPS 上运行 Gateway（状态与 workspace 在 VPS）
- `gateway.bind` 保持 loopback（默认）
- 通过 SSH 隧道或 Tailscale 访问控制面
- 需要对外绑定 `lan/tailnet` 时，必须配置 `gateway.auth.token` 或 `gateway.auth.password`

依据：`vps.md`, `gateway/index.md`, `gateway/configuration-reference.md`。

---

## 2. 国内 VPS 与海外 VPS 对照

| 项目 | 中国国内 VPS/机房 | 国外 VPS |
|---|---|---|
| 重点风险 | 外网连通性波动、部分上游 API 访问不稳定 | 跨区域时延、合规与访问源策略 |
| 网关暴露策略 | 优先 loopback + 隧道/内网 | 同样优先 loopback；公网暴露也需 auth |
| 通道层建议 | 按通道单独验证（如 Telegram 可用 proxy 配置） | 按默认路径验证，必要时再加 proxy |
| 运行方式建议 | Ubuntu/Debian + systemd user（首选） | Ubuntu/Debian + systemd user（首选） |
| 备份重点 | `~/.openclaw`（尤其 config/workspace/sessions） | 同左 |

补充：Telegram 文档明确支持 `channels.telegram.proxy` 处理不稳定直连场景（`channels/telegram.md`）。

---

## 3. 推荐部署分支（决策树）

### 分支 A：单机最快上线（推荐给个人）

1. 系统选 Ubuntu / Debian（LTS 优先）  
2. 安装 OpenClaw（installer）  
3. 初始化：`openclaw onboard` 或 `openclaw configure`  
4. 安装服务：`openclaw gateway install`  
5. 验证与收尾：`openclaw gateway status` + `openclaw logs --follow`

### 分支 B：容器化上线

1. 进入 OpenClaw 仓库目录  
2. `./docker-setup.sh`  
3. `docker compose run --rm openclaw-cli onboard`  
4. `docker compose up -d openclaw-gateway`  
5. 验证：`docker compose run --rm openclaw-cli dashboard --no-open`

### 分支 C：多机标准化（团队）

1. 采用 `openclaw-ansible`  2. 首机验证  3. 批量铺开  4. 统一按 `install/updating` 流程升级

---

## 4. Ubuntu / Debian（重点）最小可执行流程

## 4.1 安装后首轮检查

```bash
openclaw doctor
openclaw gateway status
```

判定：
- 若出现 `Gateway start blocked: set gateway.mode=local`：
  - 走 `openclaw configure`，确认网关运行位置选择 local；或直接修 `gateway.mode`。

## 4.2 服务化（长期运行）

```bash
openclaw gateway install
systemctl --user enable --now openclaw-gateway.service
openclaw gateway status
```

若需要“用户退出后仍持续”，按 runbook 启用 lingering（`gateway/index.md` 提示）。

## 4.3 日志与故障定位

```bash
openclaw logs --follow
openclaw gateway status --deep
openclaw gateway status --json
```

常见报错分流（来自 `gateway/troubleshooting.md`）：
- `EADDRINUSE`：端口冲突
- `refusing to bind gateway ... without auth`：非 loopback 暴露缺 auth
- `RPC probe: failed` 且 runtime running：连接参数或 auth 不匹配

---

## 5. Windows 路径（必须区分）

## 5.1 WSL2 路径（推荐）

- 按 `platforms/windows.md`：OpenClaw 推荐在 WSL2（Ubuntu）里跑。
- 关键是启用 systemd（`/etc/wsl.conf` + `wsl --shutdown` 后生效），再执行 Linux 流程。

## 5.2 原生 PowerShell 路径（可安装 CLI）

- 安装器支持 `install.ps1`（`install/installer.md`）。
- 但 Gateway 长期运行稳定性与生态兼容，文档建议仍以 WSL2 为主路径。

---

## 6. macOS 路径

- 以 launchd/companion app 组合为主（`platforms/macos.md`）。
- 基础运维命令仍是：

```bash
openclaw gateway install
openclaw gateway status
openclaw gateway restart
openclaw logs --follow
```

---

## 7. 升级策略（国内 VPS 建议）

推荐顺序：
1. `openclaw doctor`（先看配置/服务漂移）
2. `openclaw update --dry-run`（可选）
3. `openclaw update`
4. `openclaw gateway restart`
5. `openclaw gateway status` + `openclaw logs --follow`

依据：`install/updating.md`, `cli/update.md`。

---

## 8. 持久化与备份要点

- 文档明确：VPS 是状态源（state + workspace）。
- 备份最少覆盖：
  - `~/.openclaw/openclaw.json`
  - `~/.openclaw/workspace/`
  - 会话/状态目录（同 `~/.openclaw` 下）

容器场景：
- Docker 用 bind/volume 保证 config/workspace 与 `/home/node`（若启用）持久化。
- Podman 默认也把 config/workspace 放宿主目录，删容器不等于删数据。

