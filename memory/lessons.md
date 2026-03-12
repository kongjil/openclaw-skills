# 踩坑与经验 (Lessons Learned)
## Telegram 409 getUpdates conflict（同一 botToken 多实例轮询）
- **现象**：Telegram 里发 `ping` 没回复，也不显示“正在输入”；gateway 日志反复出现：
  - `Telegram getUpdates conflict (409: Conflict: terminated by other getUpdates request; make sure that only one bot instance is running)`
- **原因**：同一个 Telegram botToken 同时被另一处进程/机器用 **getUpdates(long polling)** 拉取更新；Telegram 会终止其中一个请求，被踢掉的一端就收不到消息。
- **关键点**：仅重启当前网关通常无效；必须停掉“另一处轮询者”，或换 token。
- **推荐解法（最快闭环）**：
  1) 在 BotFather 对该 bot 执行 **Revoke token**（重置 token）；
  2) 更新 `~/.openclaw/openclaw.json` → `channels.telegram.botToken`；
  3) 重启 gateway；
  4) 用 `openclaw status --deep` + `openclaw logs | grep -E "getUpdates|409|Conflict"` 验证不再报错。
- **预防**：同一 token 只允许一个地方跑 long polling；需要多机部署就用不同 bot 或改用 webhook。

## 网络拦截
- **问题**: OpenClaw 网页端/TG 出现 403 拦截。
- **原因**: Cloudflare 开启了 "Block AI training bots" 规则，将 OpenClaw 请求识别为爬虫。
- **解法**: 在 CF 后台关闭该规则，或将 VPS IP 加入白名单。

## 网关启动失败 / 端口不监听
- **现象**: 网页端（如 `kongopenclaw.2020427.xyz`）打不开，CF 报 Host Error；`netstat -tulpn | grep 18789` 无输出。
- **原因**: `~/.openclaw/openclaw.json` 含新版已不支持的配置键，导致 gateway 进程直接退出，systemd 进入重启风暴。
  - 例：`browser.cdpPort` / `browser.args` 在某些版本会报 `Unrecognized keys`。
- **解法**: 运行 `openclaw doctor --fix` 自动清理无效键（会生成 `~/.openclaw/openclaw.json.bak` 备份），然后 `systemctl --user restart openclaw-gateway`。

## 权限与安全
- **问题**: OpenClaw 状态目录权限为 `777`（任何同机用户/进程可读写）。
- **风险**: 可能泄露 token/配置/运行状态，或被篡改导致接管与持久化风险。
- **解法**: 将 `~/.openclaw` 权限收紧到 `700`（如：`chmod 700 /home/node/.openclaw`），并确保归属为运行用户（node:node）。

## 软件配置 (OpenClaw 2026.2.26)
- **问题**: 修改 config 提示 "Unrecognized key"。
- **记录**: 新版配置项已变动。
  - Embedding 地址须使用 `remote.baseUrl`。
  - 自动归档 `memoryFlushEnabled` 已废弃，目前仅支持 `compaction.mode: safeguard`。

## 远程执行命令：二号灵机控制一号灵机时，避免 SSH 引号断裂导致“后半段在本机执行”
- **现象**: 从二号机远程操作一号机时，命令里包含多段引号/管道/换行，容易发生引号没收好，导致一部分命令在远端执行，后半段却在本机执行，输出会混在一起，看起来像“本机 gateway/TG 出错”。
- **推荐写法**: 用 `-- bash -lc '...'` 把整段命令封进远端 shell（避免本机 shell 把后半段吃掉）：
  - `ssh -p <PORT> -i <KEY> -o IdentitiesOnly=yes root@<IP> -- bash -lc '你要执行的命令'`

## OpenClaw Gateway 高可用：Restart=always + 10 分钟健康检查
- **背景**：gateway 可能被 SIGTERM/“正常退出(0)”干净停掉，`Restart=on-failure` 不会拉起；另有“进程在跑但端口未监听/服务假死”的场景。
- **做法**：
  1) `openclaw-gateway.service` 设置 `Restart=always` + 合理 `RestartSec`，实现秒级自恢复。
  2) 额外加一个 systemd timer：每 10 分钟 `curl http://127.0.0.1:<port>/` 探活；失败则 `systemctl restart openclaw-gateway.service`，兜底假活。
- **端口**：建议脚本从 `systemctl show -p ExecStart openclaw-gateway.service` 自动解析 `--port`，避免 1/2 号串台。

## 一号/二号 systemd drop-in 不能机械照抄
- **现象**：二号机已有的 `20-path.conf` + `override.conf` 模板，直接覆盖到一号机后，`systemctl cat` 虽能加载，但重启验证阶段一号机出现端口未及时监听，最终依赖 dead-man switch 自动回滚才恢复稳定。
- **关键事实**：
  - 二号机原本就已实配，不代表一号机可无差别套用。
  - 一号机 journal 明确出现：`Failed to parse OOM policy, ignoring: restart`。
  - 一号机在回滚完成并经历一次 stop/start 后，最终恢复为 `active` + `127.0.0.1:18789` 持续监听 + `HTTP/1.1 200 OK`。
- **原因判断**：1号/2号的 systemd/宿主环境存在差异；二号机模板里还混入了本机工具链 PATH（如 `asdf` / `nvm` / `fnm`），不适合整文件覆盖到一号机。
- **操作原则**：
  1) 不要再把二号完整 drop-in 直接覆盖到一号。
  2) 若要统一，只做“一号兼容版”渐进式对齐：**每次只增量改一个点**（优先 PATH 单项），改完立即 `daemon-reload + restart + probe`。
  3) 保留 dead-man switch 自动回滚；验证通过后再取消。
  4) 对于 `OOMPolicy` 这类 systemd 版本/宿主相关字段，先以目标机 `systemd-analyze verify` / journal 实测为准，不凭另一台机器的可用配置推断。

## 2026-03-11：gateway safe restart 若从前台 exec 发起，可能出现“服务已重启但 summary 未落地”
- **现象**：`gateway-restart-safe.sh` 在前台 exec 中启动后，pending 已登记、gateway 也已成功重启，但当前 exec 被 SIGTERM 掐断；最终 `recover-pending.sh` 看到的是 `WAIT <taskId> no-result`，用户收不到自动补汇报。
- **根因**：重启带死当前承载链路时，postcheck/background summary writer 未必能稳定存活到落地 summary。
- **固定规则**：
  1) 不要默认在前台 exec 里直接跑 `gateway-restart-safe.sh` / `oc-gateway restart-safe`；
  2) gateway safe restart 默认改用更稳定的 detached 触发方式（如 `oc-longrun` / `systemd-run` / 独立 nohup shell）；
  3) 重启后验收不能只看 `systemctl is-active`，还要检查 `summaryPath` 是否存在、`recover-pending.sh` 是否 READY；
  4) 若服务已起但 summary 缺失，立即手工补写 summary 并 `close-pending`，补齐用户侧汇报；
  5) 判断“补汇报失效”时，分层排查：pending 是否登记、summary 是否落地、dispatch 是否有可发内容。

## 2026-03-11：重启补汇报不能只做“扫描”，必须有“分发层”
- **现象**：之前 root crontab 虽然每 2 分钟执行 `recover-pending.sh`，但只是把 READY/WAIT 结果写进 `memory/restart-report-recovery.cron.log`，用户仍然收不到自动补汇报。
- **根因**：`recover-pending.sh` 只是检测器，不是消息投递器；缺了“把 READY 任务真正送回主会话”的分发层。
- **固定方案**：
  1) skill 内保留 `recover-pending.sh` 作为扫描原语；
  2) 增加 `recover-dispatch.sh` 负责把 READY summary 读出来，生成用户可读补汇报，并在成功后 `close-pending`；
  3) 主会话层必须有一个定时 systemEvent/cron 负责检查 READY 并把补汇报真正发到聊天；
  4) 对 gateway 重启不要再裸跑 `systemctl restart openclaw-gateway.service`，默认改走 `oc-gateway restart-safe ...`；
  5) 对任意可能断链的脚本，默认包 `run-with-pending.sh ... -- <command...>`。
- **操作原则**：以后判断“自动补汇报失效”时，必须分三层排查：
  - 有没有 `register-pending`
  - 有没有 `READY summary`
  - 有没有“分发到聊天”的投递层

## QQBot 主动发送与跨通道限制（2026-03-10）
- **现象**：从某些会话上下文（例如 Telegram provider）尝试 `message(action=send, channel=qqbot, target=...)` 会失败。
- **根因**：OpenClaw 有 **cross-context messaging** 策略，禁止“绑定在 A provider 的会话”直接向 B provider 主动发消息。
- **可用路径**：
  1) 在 **QQ 会话上下文**内发送（自动回复/同 provider）。
  2) 使用 **cron delivery(announce)** 直投到 `channel=qqbot`（绕开工具层跨 provider 限制）。
- **坑点**：message 工具参数里可能带空字符串 `channelId:""` 这类默认值，旧校验把它当 legacy 字段导致 `Use target instead of to/channelId`。
- **修复摘要**：
  - `src/agents/tools/message-tool.ts`：不再把 `target` 映射到 legacy `to`。
  - `src/infra/outbound/channel-target.ts`：legacy 字段仅在非空时才算“存在”，并允许内部调用在无 target 时使用 legacy `to/channelId`。
- **验收**：QQ 侧收到“未触发用户先发”的主动推送（有延迟时可能数分钟后才到）。

## QQBot 发送文件/图片的最简方式
- **图片**：直接用 `<qqimg>/绝对路径/xxx.png</qqimg>`（qqbot-media 技能约定）。
- **文件/附件（工具层）**：用 message 工具 `filePath`/`media` 发送附件（QQBot 插件会走 mediaUrl）。
  - 例：`message(action=send, channel=qqbot, target=..., filePath=/path/a.txt, filename=a.txt, caption=说明)`

## 2026-03-11：GitHub 发布流程固定为 SSH 双跳（重要）
- 用户明确要求：二号机发布 GitHub 时，必须走 **二号 -> SSH 到一号 -> 一号使用 GitHub SSH(remote=git@github.com:...) 推送**。
- 禁止默认走 HTTPS push（避免凭据交互/失败）。
- 本次仓库：`kongjil/openclaw-auto-work`
- 验证方式：在一号机执行 `ssh -T git@github.com` 应返回 `Hi <user>!` 后再 `git push -u origin main`。

## 2026-03-11：Git 提交身份强制规范（重要）
- 用户要求：所有 Git 提交作者必须是：`kongji <67133458+kongjil@users.noreply.github.com>`。
- 禁止出现 `root <...>` 作为提交作者。
- 执行顺序：
  1) 先在执行机设置 `git config --global user.name/user.email`
  2) 仓库内再设置一次 `git config user.name/user.email`（双保险）
  3) 若已产生错误作者提交，使用 `git filter-repo --mailmap` 重写历史并 force push。

## 2026-03-12：workspace skills 路径下 `edit` 可能假失败，但 shell 直写已成功（重要）
- **现象**：对 `~/.openclaw/workspace/skills/**/SKILL.md` 使用工具层 `edit` 时，偶发报 `File not found` 或 edit failed；但同一路径用 shell / Python 直接读写是成功的。
- **风险**：容易出现“实际上文件已经改成了，但中途弹出一条 edit failed”，误判为修复未落地。
- **固定处理**：
  1) 若 `edit` 在 workspace skills 路径下报假失败，立即改用 `exec + python/sed/cat` 直写文件；
  2) 写完必须立刻做二次验证（`sed/head/grep/stat`）；
  3) 若涉及运行中技能链，再额外验证 `skillsSnapshot` / session store / cron 状态，而不是只看 edit 返回值；
  4) 对用户汇报时，优先以“最终文件状态和运行验证”为准，不以中途某次 edit 报错为准。
- **一句话规则**：`edit` 报错 ≠ 文件未改成；以落盘结果和运行结果为准。

