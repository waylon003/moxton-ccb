# Tech-Spec: 支付意图智能复用

**任务ID:** SHOP-FE-013
**创建时间:** 2026-03-09
**状态:** 准备开发
**角色:** 独立站前端工程师
**项目:** nuxt-moxton (E:\nuxt-moxton)
**优先级:** P1
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia + Reka UI + UnoCSS

---

## 执行上下文（强约束）

- **Task File = 唯一执行输入源**：派遣消息可能是短文本，必须以本任务文件为准，不得依赖派遣消息补充细节。
- **工作目录**：`E:\nuxt-moxton`
- **必读文档**：
  - `E:\nuxt-moxton\CLAUDE.md`
  - `E:\nuxt-moxton\AGENTS.md`
  - `E:\moxton-ccb\02-api\payments.md` - 支付 API 文档
- **开始后 60 秒内**：必须 `report_route(status="in_progress")`
- **执行中每 90~120 秒**：发送一次 `in_progress` 心跳
- **遇阻塞 2 分钟内**：`report_route(status="blocked", body="blocker_type=...;question=...;attempted=...;next_action_needed=...")`
- **完成后必须**：`report_route(status="success|fail|blocked", body=变更文件+命令+测试结果)`

---

## 概述

### 问题陈述

当前用户从订单列表点击"去支付"跳转到 checkout 页面时，`CheckoutPayment.vue` 组件会直接调用 `POST /payments/stripe/create-intent` 创建新的支付意图。但如果订单已有活跃的支付意图（用户刷新页面、返回支付页面等场景），后端会返回 400 错误："Payment already in progress"。

这导致用户无法继续支付，体验很差。

### 解决方案

实现智能复用逻辑：
1. 在创建支付意图之前，先调用 `GET /payments/order/:orderId` 检查订单是否已有活跃的支付意图
2. 如果有活跃支付意图（状态为 PENDING/PAYMENT_INITIATED/REQUIRES_ACTION 且未过期），复用其 `clientSecret`
3. 如果没有活跃支付意图，调用 `POST /payments/stripe/create-intent` 创建新的
4. 添加错误处理和降级逻辑

### 范围 (包含/排除)

**包含:**
- 新增 `composables/api/payments.ts` 中的 `getOrderPayment` 方法
- 修改 `CheckoutPayment.vue` 组件的支付意图初始化逻辑
- 实现智能复用：先查询 → 判断 → 复用或创建
- 添加错误处理和用户提示

**不包含:**
- 后端 API 修改（由 BACKEND-014 任务处理）
- 支付流程的其他优化
- 订单列表页的修改

---

## 开发上下文

### 现有实现

**相关文件：**
- `pages/checkout/index.vue` - Checkout 主页面
- `components/checkout/CheckoutPayment.vue` - 支付步骤组件
- `composables/api/payments.ts` - 支付 API 调用封装
- `composables/useCheckout.ts` - Checkout 状态管理

**当前支付流程：**
1. 用户进入 checkout 页面，URL 包含 `step=payment&orderId=xxx`
2. `CheckoutPayment.vue` 组件 mounted 时调用 `createPaymentIntent(orderId)`
3. 直接调用 `POST /payments/stripe/create-intent` 创建支付意图
4. 如果订单已有活跃支付意图，后端返回 400 错误
5. 前端显示错误提示，用户无法继续支付

### 前置依赖

- **BACKEND-014**：新增订单支付查询 API（必须先完成并通过 QA）
- API 文档已同步到 `E:\moxton-ccb\02-api\payments.md`

### 依赖项

- 使用现有的 `$api` 实例（Nuxt 插件）
- 使用现有的认证 token 和 X-Guest-ID 头管理
- 使用现有的 Stripe Elements 集成

---

## 技术方案

### 架构设计

**智能复用流程：**
```
用户进入支付页面
    ↓
调用 getOrderPayment(orderId) 查询支付记录
    ↓
判断是否有 activePayment
    ↓
有 activePayment → 复用 clientSecret → 初始化 Stripe Elements
    ↓
无 activePayment → 调用 createPaymentIntent → 初始化 Stripe Elements
    ↓
用户输入卡片信息并确认支付
```

### API 调用

**新增 API 方法：**

在 `composables/api/payments.ts` 中添加：

```typescript
/**
 * 获取订单的支付记录
 * @param orderId 订单ID
 * @returns 支付记录和活跃支付意图
 */
export async function getOrderPayment(orderId: string) {
  return await $api.get<{
    orderId: string
    payments: Array<{
      id: string
      paymentNo: string
      paymentIntentId: string
      clientSecret: string
      amount: number
      currency: string
      status: string
      expiresAt: string
      createdAt: string
    }>
    activePayment: {
      id: string
      paymentIntentId: string
      clientSecret: string
      status: string
      expiresAt: string
    } | null
  }>(`/payments/order/${orderId}`)
}
```

**修改现有方法：**

保持 `createPaymentIntent` 方法不变，但在调用前先检查是否有活跃支付意图。

### 数据模型

**新增类型定义：**

```typescript
interface OrderPaymentResponse {
  orderId: string
  payments: PaymentRecord[]
  activePayment: ActivePayment | null
}

interface PaymentRecord {
  id: string
  paymentNo: string
  paymentIntentId: string
  clientSecret: string
  amount: number
  currency: string
  status: string
  expiresAt: string
  createdAt: string
}

interface ActivePayment {
  id: string
  paymentIntentId: string
  clientSecret: string
  status: string
  expiresAt: string
}
```

---

## 实施步骤

### Step 1: 新增 getOrderPayment API 方法

**目标**: 在 `composables/api/payments.ts` 中添加新的 API 调用方法

**操作**:
1. 打开 `composables/api/payments.ts`
2. 添加 `getOrderPayment` 方法
3. 添加相关类型定义

**代码示例**:
```typescript
// 在 payments.ts 中添加

export interface OrderPaymentResponse {
  orderId: string
  payments: PaymentRecord[]
  activePayment: ActivePayment | null
}

export interface PaymentRecord {
  id: string
  paymentNo: string
  paymentIntentId: string
  clientSecret: string
  amount: number
  currency: string
  status: string
  expiresAt: string
  createdAt: string
}

export interface ActivePayment {
  id: string
  paymentIntentId: string
  clientSecret: string
  status: string
  expiresAt: string
}

export async function getOrderPayment(orderId: string): Promise<OrderPaymentResponse> {
  const response = await $api.get<OrderPaymentResponse>(`/payments/order/${orderId}`)
  return response
}
```

**验收**:
- [ ] `getOrderPayment` 方法已添加
- [ ] 类型定义完整
- [ ] 方法签名正确

---

### Step 2: 修改 CheckoutPayment 组件逻辑

**目标**: 实现智能复用逻辑

**操作**:
1. 打开 `components/checkout/CheckoutPayment.vue`
2. 找到支付意图初始化的代码（通常在 `onMounted` 或 `watch` 中）
3. 修改为先调用 `getOrderPayment`，再决定是复用还是创建

**代码示例**:
```typescript
// 在 CheckoutPayment.vue 中修改

const initializePayment = async (orderId: string) => {
  try {
    loading.value = true
    error.value = null

    // 1. 先查询订单的支付记录
    const orderPayment = await getOrderPayment(orderId)

    let clientSecret: string
    let paymentIntentId: string

    // 2. 判断是否有活跃支付意图
    if (orderPayment.activePayment) {
      // 有活跃支付意图，复用
      console.log('Reusing existing payment intent:', orderPayment.activePayment.paymentIntentId)
      clientSecret = orderPayment.activePayment.clientSecret
      paymentIntentId = orderPayment.activePayment.paymentIntentId
    } else {
      // 无活跃支付意图，创建新的
      console.log('Creating new payment intent for order:', orderId)
      const paymentIntent = await createPaymentIntent(orderId)
      clientSecret = paymentIntent.clientSecret
      paymentIntentId = paymentIntent.paymentIntentId
    }

    // 3. 初始化 Stripe Elements
    await initializeStripeElements(clientSecret)

    // 4. 保存 paymentIntentId 用于后续状态查询
    currentPaymentIntentId.value = paymentIntentId

  } catch (err: any) {
    console.error('Failed to initialize payment:', err)
    error.value = err.message || t('checkout.payment.initError')
  } finally {
    loading.value = false
  }
}
```

**验收**:
- [ ] 智能复用逻辑已实现
- [ ] 先查询后决策的流程正确
- [ ] 日志输出清晰（便于调试）

---

### Step 3: 添加错误处理和降级逻辑

**目标**: 确保即使查询失败也能继续支付流程

**操作**:
1. 为 `getOrderPayment` 调用添加 try-catch
2. 如果查询失败（如网络错误、权限错误），降级为直接创建新支付意图
3. 添加用户友好的错误提示

**代码示例**:
```typescript
const initializePayment = async (orderId: string) => {
  try {
    loading.value = true
    error.value = null

    let clientSecret: string
    let paymentIntentId: string

    try {
      // 1. 尝试查询订单的支付记录
      const orderPayment = await getOrderPayment(orderId)

      if (orderPayment.activePayment) {
        // 有活跃支付意图，复用
        console.log('Reusing existing payment intent:', orderPayment.activePayment.paymentIntentId)
        clientSecret = orderPayment.activePayment.clientSecret
        paymentIntentId = orderPayment.activePayment.paymentIntentId
      } else {
        // 无活跃支付意图，创建新的
        console.log('No active payment intent, creating new one')
        const paymentIntent = await createPaymentIntent(orderId)
        clientSecret = paymentIntent.clientSecret
        paymentIntentId = paymentIntent.paymentIntentId
      }
    } catch (queryError: any) {
      // 2. 查询失败，降级为直接创建新支付意图
      console.warn('Failed to query order payment, falling back to create new:', queryError.message)
      const paymentIntent = await createPaymentIntent(orderId)
      clientSecret = paymentIntent.clientSecret
      paymentIntentId = paymentIntent.paymentIntentId
    }

    // 3. 初始化 Stripe Elements
    await initializeStripeElements(clientSecret)
    currentPaymentIntentId.value = paymentIntentId

  } catch (err: any) {
    console.error('Failed to initialize payment:', err)

    // 4. 用户友好的错误提示
    if (err.message?.includes('Payment already in progress')) {
      error.value = t('checkout.payment.alreadyInProgress')
    } else {
      error.value = err.message || t('checkout.payment.initError')
    }
  } finally {
    loading.value = false
  }
}
```

**验收**:
- [ ] 错误处理完善
- [ ] 降级逻辑正确（查询失败时仍能创建支付意图）
- [ ] 错误提示用户友好

---

### Step 4: 添加 i18n 翻译

**目标**: 为新的错误提示添加多语言支持

**操作**:
1. 在 `i18n/locales/zh.ts` 中添加中文翻译
2. 在 `i18n/locales/en.ts` 中添加英文翻译

**代码示例**:
```typescript
// zh.ts
checkout: {
  payment: {
    initError: '初始化支付失败，请刷新页面重试',
    alreadyInProgress: '支付正在进行中，请稍候',
    // ... 其他翻译
  }
}

// en.ts
checkout: {
  payment: {
    initError: 'Failed to initialize payment, please refresh and try again',
    alreadyInProgress: 'Payment is already in progress, please wait',
    // ... 其他翻译
  }
}
```

**验收**:
- [ ] 中文翻译已添加
- [ ] 英文翻译已添加
- [ ] 翻译键与代码中使用的一致

---

### Step 5: 测试智能复用逻辑

**目标**: 验证各种场景下的复用逻辑

**测试场景**:

1. **首次进入支付页面（无活跃支付意图）**:
   - 操作：创建订单 → 点击"去支付"
   - 预期：调用 `createPaymentIntent` 创建新的支付意图

2. **刷新支付页面（有活跃支付意图）**:
   - 操作：进入支付页面 → 刷新页面
   - 预期：复用现有的 `clientSecret`，不创建新的

3. **返回支付页面（有活跃支付意图）**:
   - 操作：进入支付页面 → 返回订单列表 → 再次点击"去支付"
   - 预期：复用现有的 `clientSecret`

4. **支付失败后重试（无活跃支付意图）**:
   - 操作：支付失败 → 返回订单列表 → 点击"去支付"
   - 预期：创建新的支付意图（旧的已失败）

5. **查询 API 失败降级**:
   - 操作：模拟 `getOrderPayment` 返回 500 错误
   - 预期：降级为直接创建新支付意图，不阻塞支付流程

6. **权限错误处理**:
   - 操作：使用错误的 token 或 X-Guest-ID
   - 预期：显示权限错误提示

**验收**:
- [ ] 所有测试场景通过
- [ ] Console 日志清晰（显示是复用还是创建）
- [ ] 用户体验流畅，无卡顿

---

### Step 6: 验证与后端 API 的集成

**目标**: 确保前后端联调正常

**操作**:
1. 确认后端 BACKEND-014 任务已完成并通过 QA
2. 确认 API 文档已同步到 `E:\moxton-ccb\02-api\payments.md`
3. 使用真实后端 API 进行集成测试
4. 验证请求头（Authorization 或 X-Guest-ID）正确传递

**验收**:
- [ ] 前后端联调成功
- [ ] API 请求和响应格式正确
- [ ] 权限验证正常（登录用户和游客）

---

## 验收标准

| # | 标准 | 验证方式 |
|---|------|---------|
| 1 | `getOrderPayment` 方法正确调用后端 API | 浏览器 Network 面板查看请求 |
| 2 | 有活跃支付意图时复用 `clientSecret` | Console 日志显示 "Reusing existing payment intent" |
| 3 | 无活跃支付意图时创建新的 | Console 日志显示 "Creating new payment intent" |
| 4 | 查询失败时降级为创建新支付意图 | 模拟 API 错误，验证降级逻辑 |
| 5 | 用户刷新页面不再出现 400 错误 | 刷新支付页面，验证无错误 |
| 6 | 错误提示用户友好且本地化 | 测试中英文环境 |
| 7 | Console 无错误 | DevTools Console 检查 |
| 8 | 移动端显示正常 | 手机/模拟器测试 |

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 后端 API 未就绪 | 等待 BACKEND-014 完成并通过 QA 后再开始开发 |
| 查询 API 失败导致支付流程中断 | 添加降级逻辑，查询失败时直接创建新支付意图 |
| 活跃支付意图判定不准确 | 严格按照后端返回的 `activePayment` 字段判断，不自行判断 |
| 多标签页同时打开支付页面 | 后端已有防重复机制，前端复用逻辑可以处理 |
| 权限验证失败 | 添加明确的错误提示，引导用户重新登录或检查订单归属 |

---

## 相关文档

- [支付 API 文档](../../02-api/payments.md)
- [项目状态](../../04-projects/nuxt-moxton.md)
- [项目协调](../../04-projects/COORDINATION.md)
- [前置依赖任务](../backend/BACKEND-014-order-payment-query-api.md)

<!-- AUTO-QA-SUMMARY:BEGIN -->
## QA 摘要（自动回写）

- 最后更新: `2026-03-24T15:21:54+08:00`
- QA Worker: `shop-fe-qa`
- 路由状态: `success`
- 验收结论: `PASS`
- 结论摘要: 支付页已验证通过：首次进入会创建 intent，刷新后会复用 active intent，查询接口网络失败时会降级创建，403 失败路径的中英文提示均已产品化且不透出后端原文。
- 证据索引:
  - `component_api`: `PASS` -> `05-verification/SHOP-FE-013/context7-stripe-check-20260324.txt`
  - `console`: `PASS` -> `05-verification/SHOP-FE-013/console-refresh-reuse.log`, `05-verification/SHOP-FE-013/page-errors-refresh.log`
  - `failure_path`: `PASS` -> `05-verification/SHOP-FE-013/payment-failure-en.png`, `05-verification/SHOP-FE-013/payment-failure-zh.png`, `05-verification/SHOP-FE-013/console-failure-en.log`
  - `network`: `PASS` -> `05-verification/SHOP-FE-013/network-reuse-refresh.json`, `05-verification/SHOP-FE-013/network-fallback-network-error.json`, `05-verification/SHOP-FE-013/network-failure-en.json`
  - `smart_reuse`: `PASS` -> `05-verification/SHOP-FE-013/console-first-create.log`, `05-verification/SHOP-FE-013/payment-en-1280.png`, `05-verification/SHOP-FE-013/payment-reuse-refresh-1280.png`, `05-verification/SHOP-FE-013/payment-fallback-network-error.png`
  - `ui`: `PASS` -> `05-verification/SHOP-FE-013/payment-reuse-1280.png`, `05-verification/SHOP-FE-013/payment-reuse-768.png`, `05-verification/SHOP-FE-013/payment-reuse-390.png`
- 验证命令:
  - `pnpm type-check`
  - `pnpm build`
  - `$env:PLAYWRIGHT_SKIP_WEBSERVER='1'; pnpm test:e2e -- tests/e2e/smoke.spec.ts`
  - `agent-browser open/snapshot/click runtime verification`
  - `node inline runtime probes for fallback/i18n/responsive evidence`
  - `E:\moxton-ccb\scripts\validate-qa-evidence.ps1 -TaskId SHOP-FE-013 -EvidencePaths ...`
- 原始证据仍以 `05-verification/` 中的文件为准。
<!-- AUTO-QA-SUMMARY:END -->
