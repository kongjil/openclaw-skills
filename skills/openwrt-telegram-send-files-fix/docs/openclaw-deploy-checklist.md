# OpenClaw 部署检查清单（多系统 + 多方式）

## 0. 选型分支（先判断再执行）

- [ ] **系统分支**
  - [ ] Linux（Ubuntu/Debian 优先）
  - [ ] macOS
  - [ ] Windows WSL2（推荐）
  - [ ] Windows 原生 PowerShell（仅补充路径）
- [ ] **部署方式分支**
  - [ ] 直接源码/本机 Node
  - [ ] systemd/launchd 服务托管
  - [ ] Docker / Docker Compose
  - [ ] Podman
  - [ ] Ansible
  - [ ] Nix
  - [ ] Bun（实验，不用于 Gateway 生产）

---

## 1. 通用前置检查

```bash
openclaw doctor
openclaw gateway status
openclaw config get gateway.mode
```

判定：
- [ ] `gateway.mode=local`（本机跑网关必须）
- [ ] 若 bind 非 loopback，已配置 token/password

---

## 2. Linux（Ubuntu / Debian）执行清单

- [ ] 安装完成后跑 onboarding/configure
- [ ] 安装服务：

```bash
openclaw gateway install
systemctl --user enable --now openclaw-gateway.service
```

- [ ] 验证：

```bash
openclaw gateway status
openclaw logs --follow
```

- [ ] 若需退出登录后仍保持：确认 systemd user lingering（runbook）

---

## 3. macOS 执行清单

- [ ] `openclaw gateway install`
- [ ] `openclaw gateway status`
- [ ] 需要时用 launchctl 进行 kickstart/bootout（按 runbook label）
- [ ] `openclaw logs --follow` 验证

---

## 4. Windows 执行清单（区分）

### 4.1 WSL2（推荐）
- [ ] `wsl --install` + Ubuntu
- [ ] 启用 WSL systemd
- [ ] 在 WSL 内执行 Linux 完整流程

### 4.2 原生 PowerShell（补充）
- [ ] 可用 `install.ps1` 安装 CLI
- [ ] 长期 Gateway 运行仍建议迁移到 WSL2

---

## 5. Docker / Compose 清单

```bash
./docker-setup.sh
docker compose run --rm openclaw-cli onboard
docker compose up -d openclaw-gateway
```

- [ ] 已确认 config/workspace 挂载策略
- [ ] 需要持久化 `/home/node` 时已设置 `OPENCLAW_HOME_VOLUME`
- [ ] 改动 mounts/volume/apt packages 后已重跑 `docker-setup.sh`

---

## 6. Podman 清单

```bash
./setup-podman.sh
./scripts/run-openclaw-podman.sh launch
# 或
./setup-podman.sh --quadlet
```

- [ ] rootless user 的 `/etc/subuid` `/etc/subgid` 正常
- [ ] `gateway.mode=local` 已写入配置
- [ ] 日志命令可用（quadlet/journalctl 或 podman logs）

---

## 7. Ansible / Nix / Bun 清单

### 7.1 Ansible
- [ ] 目标系统 Debian 11+ / Ubuntu 20.04+
- [ ] 使用 `openclaw-ansible`（其仓库为 SoT）
- [ ] 部署后能 `journalctl -u openclaw -f` 查看日志

### 7.2 Nix
- [ ] 使用 `nix-openclaw`（其仓库为 SoT）
- [ ] 已明确 `OPENCLAW_CONFIG_PATH` / `OPENCLAW_STATE_DIR`
- [ ] Nix mode 环境变量/配置生效

### 7.3 Bun（实验）
- [ ] 仅用于本地开发 loop
- [ ] 未用于生产 Gateway 运行

---

## 8. 中国国内 VPS 专项检查

- [ ] Gateway 默认 loopback，不直接裸露公网
- [ ] 远程访问优先 SSH 隧道或 Tailscale
- [ ] Telegram/Discord 等通道已做连通性验证
- [ ] Telegram 不稳定时已评估 `channels.telegram.proxy`
- [ ] 已备份 `~/.openclaw` 关键状态

---

## 9. 升级/回归检查

```bash
openclaw update --dry-run
openclaw update
openclaw gateway restart
openclaw gateway status
openclaw logs --follow
```

- [ ] 更新后无 `RPC probe failed`
- [ ] 无 `EADDRINUSE`
- [ ] 无 bind/auth 配置冲突报错

