---
name: telegram-file-send-fix
description: Telegram 附件/文件发送失败排障与修复定位。用于 message 发送 attachment/file 时出现目标路由异常（如 legacy target 字段为空导致发送失败）的场景；按 commit 6e5c3ff67b 的改动进行快速确认、验证与回归检查。
---

# telegram-file-send-fix

## 触发条件（命中画像）
- Telegram 文本发送正常，但带附件（document/file）发送失败。
- 调用链路里 target/recipient 存在 legacy 字段（如 `target`、`channelId`）为空字符串或空值。
- 现象集中在“附件发送路径”，而不是纯文本路径。

## 关键事实
- 参考修复：`6e5c3ff67b fix(message): tolerate empty legacy target fields for attachment sends`
- 重点文件：
  - `src/infra/outbound/message-action-runner.ts`
  - `src/infra/outbound/channel-target.test.ts`
- 核心点：附件发送场景下，需要兼容 legacy target 空字段，避免把“空值”当成有效目标参与路由判定。

## 排查顺序（最短链路）
1. **先判定是否仅附件失败**
   - 同目标先发纯文本，再发同会话附件。
   - 若文本成功、附件失败，继续下一步。
2. **检查 target 归一化行为**
   - 看 `message-action-runner.ts` 中附件路径是否对 legacy 空字段做容错（空字符串/空值应被忽略）。
3. **看测试是否覆盖该回归**
   - 在 `channel-target.test.ts` 搜索 attachment + empty legacy target 相关用例。
   - 用例应证明：legacy 为空时，不应污染最终路由目标。
4. **最小回归验证**
   - 触发一次“legacy 字段为空 + attachment 发送”请求。
   - 预期：不再因目标解析失败而拒发，且发送链路进入 Telegram 正常投递逻辑。

## 命中该问题的典型信号
- 只在 attachment/file 发送失败，文本同目标可成功。
- 请求体含 legacy target 字段但值为空。
- 升级到包含 `6e5c3ff67b` 的代码后，同样请求恢复成功。

## 验证清单
- [ ] 代码包含 `6e5c3ff67b` 改动。
- [ ] `channel-target.test.ts` 相关用例存在并通过。
- [ ] 复现实例（空 legacy target + attachment）从失败变成功。
- [ ] 未引入文本发送回归。
