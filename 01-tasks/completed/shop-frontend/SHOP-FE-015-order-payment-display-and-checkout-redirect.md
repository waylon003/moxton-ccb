# Tech-Spec: 订单详情支付信息展示 + 结账第4步确认直达 /shop

**任务ID:** SHOP-FE-015
**创建时间:** 2026-03-25
**状态:** 准备开发
**角色:** 独立站前端工程师
**项目:** nuxt-moxton
**优先级:** P1
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia
**QA_LEVEL:** smoke

---

## 执行上下文（强约束）

- **Task File = 唯一执行输入源**：派遣消息可能是短文本，必须以本任务文件为准，不得依赖派遣消息补充细节。
- **工作目录**：`E:\nuxt-moxton`
- **必读文档**：
  - `E:\nuxt-moxton\CLAUDE.md`
  - `E:\nuxt-moxton\AGENTS.md`
  - `E:\moxton-ccb\02-api\orders.md`
- **开始后 60 秒内**：必须 `report_route(status="in_progress")`
- **执行中每 90~120 秒**：发送一次 `in_progress` 心跳
- **遇阻塞 2 分钟内**：`report_route(status="blocked", body="blocker_type=...;question=...;attempted=...;next_action_needed=...")`
- **完成后必须**：`report_route(status="success|fail|blocked", body=变更文件+命令+测试结果)`

---

## 概述

### 问题陈述

1) 订单状态为“待发货”（已支付）时，支付方式与支付时间未展示。
2) 结账第4步订单确认点击右下角“确认”后，未直接回到 `/shop`，而是回到第1步等待进度条后才跳转。

### 解决方案

- 订单详情页：已支付状态下显示支付方式 `Stripe` 与支付时间；支付时间优先取 `paidAt`，为空则降级 `lastPaymentAttemptAt`，两者皆空显示 `-`。
- 结账第4步：确认完成后直接跳转 `/shop`，避免回到第1步与等待进度条。

### 范围 (包含/排除)

**包含:**
- 订单详情页支付信息展示（前端展示层）
- 结账第4步确认后的跳转逻辑

**不包含:**
- 后端接口或字段变更
- 支付状态流转逻辑调整
- 订单列表页/其他页面改动

---

## 开发上下文

### 现有实现

- 订单详情页面支付信息区域当前未在“待发货”状态下展示支付方式/支付时间（需定位现有组件）。
- 结账第4步确认按钮当前会先回到第1步等待进度条后再跳转（需定位现有逻辑）。

### 依赖项

- `E:\moxton-ccb\02-api\orders.md`（`GET /orders/:id`、`GET /orders/guest/orders/:id` 的 `paidAt`、`lastPaymentAttemptAt`、`paymentStatus` 字段）
- `E:\moxton-ccb\04-projects\nuxt-moxton.md`

---

## 技术方案

### 架构设计

- 仅调整前端展示与跳转逻辑，不新增 API 调用。

### 数据模型

- 读取订单详情返回字段：`paidAt`、`lastPaymentAttemptAt`、`paymentStatus`。

### API 调用

- 使用现有订单详情接口返回字段，无新增请求。

---

## 实施步骤

1. 定位订单详情页支付信息区域（支付方式/支付时间展示处）。
2. 增加展示规则：支付方式固定显示 `Stripe`；支付时间优先 `paidAt`，为空则 `lastPaymentAttemptAt`，两者皆空显示 `-`。
3. 定位结账第4步确认按钮处理逻辑，确认成功后直接路由到 `/shop`（避免回到第1步）。

---

## 验收标准

- [ ] 订单状态为“待发货”（已支付）时，支付方式显示 `Stripe`，支付时间显示 `paidAt`（为空则显示 `lastPaymentAttemptAt`）。
- [ ] 第4步确认后直接跳转 `/shop`，不再回到第1步等待进度条。
- [ ] 未新增后端接口调用。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| `paidAt` 为空 | 降级使用 `lastPaymentAttemptAt`，仍为空显示 `-` |

---

**相关文档:**
- [API 文档](../../02-api/)
- [项目状态](../../04-projects/nuxt-moxton.md)

<!-- AUTO-QA-SUMMARY:BEGIN -->
## QA 摘要（自动回写）

- 最后更新: `2026-03-25T16:33:37+08:00`
- QA Worker: `shop-fe-qa`
- 路由状态: `success`
- 验收结论: `PASS`
- 结论摘要: 已验证订单详情在 CONFIRMED 已支付场景展示 Stripe 与 lastPaymentAttemptAt 回退时间，且 checkout 第4步完成后直接跳转 /shop。
- 证据索引:
  - `component_api`: `PASS` -> `05-verification/SHOP-FE-015/component-api-navigateTo.txt`
  - `console`: `PASS` -> `05-verification/SHOP-FE-015/order-detail-console.log`, `05-verification/SHOP-FE-015/console-checkout-redirect.log`
  - `failure_path`: `PASS` -> `05-verification/SHOP-FE-015/order-detail-failure-500.png`, `05-verification/SHOP-FE-015/failure-path-assertion.txt`, `05-verification/SHOP-FE-015/network-failure-path.log`, `05-verification/SHOP-FE-015/console-failure-path.log`
  - `network`: `PASS` -> `05-verification/SHOP-FE-015/order-detail-network.json`, `05-verification/SHOP-FE-015/network-checkout-redirect.log`
  - `ui`: `PASS` -> `05-verification/SHOP-FE-015/order-detail-1280-playwright.png`, `05-verification/SHOP-FE-015/order-detail-tablet-768.png`, `05-verification/SHOP-FE-015/order-detail-mobile-390.png`, `05-verification/SHOP-FE-015/selected-order-detail.json`, `05-verification/SHOP-FE-015/checkout-step4-before-click.png`, `05-verification/SHOP-FE-015/checkout-redirect-shop-final.png`, `05-verification/SHOP-FE-015/checkout-redirect-assertion.txt`
- 验证命令:
  - `pnpm type-check`
  - `pnpm build`
  - `pnpm test:e2e -- tests/e2e/smoke.spec.ts`
- 原始证据仍以 `05-verification/` 中的文件为准。
<!-- AUTO-QA-SUMMARY:END -->
