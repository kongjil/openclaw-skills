# OpenClaw 部署顾问（可执行框架）

脚本位置：`scripts/openclaw-deploy-advisor.py`

## 目标

在保留“检测 + 推荐 + 计划渲染”能力基础上，补齐可真正执行的框架，并分阶段：

1. 检测/推荐（report）
2. choose 方案（choose A / choose option-id）
3. 依赖缺口分析（choose 输出）
4. remediation（补齐依赖）
5. deploy（真正部署）

---

## 命令总览

### 1) 检测/推荐（report）

```bash
./scripts/openclaw-deploy-advisor.py --format text report --plan-only
./scripts/openclaw-deploy-advisor.py --format json report --plan-only
```

输出：系统/网络/工具检测、候选方案 A/B/C 映射、推荐方案、下一步命令。

### 2) choose + 依赖缺口分析

```bash
./scripts/openclaw-deploy-advisor.py --format text choose A --plan-only
./scripts/openclaw-deploy-advisor.py --format text choose ubuntu-systemd-node --plan-only
```

输出：
- 状态分级（ready/remediable/unsupported/risky）
- 已满足依赖 / 缺失依赖
- 自动可补齐与需人工处理分组
- remediation 计划与 deploy 计划

### 3) render 模式（只渲染，不执行）

```bash
./scripts/openclaw-deploy-advisor.py --format text choose A --render-remediation -
./scripts/openclaw-deploy-advisor.py --format text choose A --render-deploy -
```

`-` 表示输出到 stdout；也可传文件路径落盘。

### 4) apply 模式（可进入真实执行路径）

> apply 现在带通用安全闸门：
> - 第一层：`--confirm remediation|deploy`（动作确认）
> - 第二层：`--execute`（执行开关）
>
> 两层都满足才会执行真实命令。

```bash
# remediation 真实执行
./scripts/openclaw-deploy-advisor.py --format text choose A --apply-remediation --confirm remediation --execute

# deploy 真实执行
./scripts/openclaw-deploy-advisor.py --format text choose A --apply-deploy --confirm deploy --execute
```

#### 无确认参数时的行为

例如：

```bash
./scripts/openclaw-deploy-advisor.py --format text choose A --apply-deploy
```

不会执行真实命令，会明确提示：

- `当前仅预演，将执行哪些命令；如需真实执行请补充确认参数。`
- 并列出待执行命令清单（text/json 都会返回）。

#### 仅有 `--confirm` 但未加 `--execute`

例如：

```bash
./scripts/openclaw-deploy-advisor.py --format text choose A --apply-deploy --confirm deploy
```

仍不会执行真实命令，会提示进入二次确认前的预演状态。

### 5) 兼容旧命令

```bash
./scripts/openclaw-deploy-advisor.py --format text apply ubuntu-systemd-node
```

等价于：`choose <option-id> --apply-deploy`，并同样受确认闸门约束。

---

## render 与 apply 的区别

- `render-*`：只输出脚本/步骤，永不执行。
- `apply-*`：具备执行能力，但默认被安全闸门拦截，必须显式确认后才执行。

---

## 为什么这是通用安全闸门

这套闸门只依赖“操作类型（remediation/deploy）+ 显式确认参数”，不依赖任何机器私有特征（IP、主机名、路径拓扑、环境标签等）。

因此它适用于公开分发场景：
- 降低误触发真实执行的概率；
- 保持跨环境一致行为；
- 同时保留自动化可执行路径。

---

## JSON 输出说明

- 键名保持稳定英文（兼容机器消费）
- 描述性文案尽量中文
- `choose` 结果重点包括：
  - `dependency_analysis`
  - `remediation_plan`
  - `deploy_plan`
  - `apply.remediation` / `apply.deploy`
  - `apply.*.gate`（闸门判定结果）
  - `requested_commands` / `executed_commands`
  - `apply_messages`

---

## 安全边界

- `render-*` 只生成脚本/步骤，不执行
- `apply-*` 需显式确认参数与执行开关，才进入真实执行
- 建议先在测试环境验证，再进入生产环境
