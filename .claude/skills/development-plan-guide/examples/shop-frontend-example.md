# SHOP-FE-001: Stripe 支付集成

> **示例任务：独立站前端单角色任务**

**创建时间:** 2026-02-08
**状态:** 准备开发
**角色:** 独立站前端工程师 (SHOP-FE)
**项目:** nuxt-moxton
**优先级:** P0
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia

---

## 概述

### 问题陈述

当前商城系统缺少在线支付功能，用户只能通过线下咨询下单。需要集成 Stripe 支付，让用户可以在线完成支付。

### 解决方案

使用 Stripe Elements 集成支付表单，在结账页面收集支付信息，通过后端创建支付意图并完成支付。

### 范围 (包含/排除)

**包含:**
- Stripe Elements 支付表单集成
- 支付状态显示（处理中、成功、失败）
- 支付错误处理和用户提示
- 与结账流程的集成

**不包含:**
- Stripe 后端集成（由 BACKEND 负责）
- 退款功能
- 多种支付方式（仅限信用卡）

---

## 开发上下文

### 现有实现

- 结账页面：`pages/checkout/index.vue`
- 结算 store：`stores/checkout.ts`
- 购物车 store：`stores/cart.ts`

### 依赖项

- 后端 API：`POST /api/payments/create-intent`
- Stripe.js SDK
- 环境变量：`STRIPE_PUBLIC_KEY`

---

## 技术方案

### 架构设计

```
┌─────────────────┐
│  Checkout Page  │
│                 │
│  ┌───────────┐  │
│  │  Stripe   │  │
│  │ Elements  │  │
│  └───────────┘  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Backend API    │
│  /payments/*    │
└─────────────────┘
```

### 数据模型

```typescript
interface PaymentIntent {
  id: string
  amount: number
  currency: string
  status: 'processing' | 'succeeded' | 'failed'
  clientSecret: string
}
```

### API 调用

1. **创建支付意图**
   - 端点：`POST /api/payments/create-intent`
   - 请求：`{ amount: number, currency: string, orderId: string }`
   - 响应：`{ clientSecret: string, intentId: string }`

2. **确认支付**
   - 使用 Stripe.js `confirmCardPayment`
   - 需要 `clientSecret` 和支付元素

---

## 实施步骤

1. **安装 Stripe SDK**
   ```bash
   pnpm add @stripe/stripe-js
   ```

2. **创建支付组件**
   - `components/payment/StripeElements.vue`
   - 集成 Card Element
   - 处理支付提交

3. **集成到结账页面**
   - 在 `pages/checkout/index.vue` 中添加支付组件
   - 连接结账流程

4. **处理支付状态**
   - 显示加载状态
   - 处理成功/失败回调
   - 更新订单状态

5. **错误处理**
   - 显示支付错误信息
   - 提供重试选项

---

## 验收标准

- [ ] 可以加载 Stripe Elements 支付表单
- [ ] 输入有效的信用卡信息可以提交支付
- [ ] 支付成功后显示成功消息并跳转到订单详情页
- [ ] 支付失败后显示错误信息
- [ ] 支付处理中显示加载状态
- [ ] 移动端响应式布局正常

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| Stripe SDK 加载失败 | 添加加载检测和错误处理 |
| 支付超时 | 设置合理的超时时间并提示用户 |
| 卡片验证错误 | 使用 Stripe 的实时验证功能 |

---

**相关文档:**
- [Stripe 集成指南](../../../03-guides/stripe-elements.md)
- [支付 API](../../../02-api/payments.md)
- [项目状态](../../../04-projects/nuxt-moxton.md)
