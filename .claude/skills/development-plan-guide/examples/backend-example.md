# BACKEND-001: 支付 API 开发

> **示例任务：后端单角色任务**

**创建时间:** 2026-02-08
**状态:** 准备开发
**角色:** 后端工程师 (BACKEND)
**项目:** moxton-lotapi
**优先级:** P0
**技术栈:** Node.js + Koa + TypeScript + Prisma + MySQL

---

## 概述

### 问题陈述

商城系统需要支付处理 API，用于创建支付意图、确认支付和处理 webhook 事件。

### 解决方案

使用 Stripe SDK 实现支付相关的 API 端点，包括创建支付意图、确认支付和处理 webhook。

### 范围 (包含/排除)

**包含:**
- 创建支付意图 API
- 支付确认 API
- Stripe webhook 处理
- 支付记录存储
- 错误处理和日志

**不包含:**
- 退款功能（后续任务）
- 多种支付方式（仅 Stripe 卡支付）
- 支付统计分析

---

## 开发上下文

### 现有实现

- Koa 服务器：`src/server.ts`
- Prisma schema：已有 `Order` 和 `Payment` 模型
- 认证中间件：`src/middleware/auth.ts`

### 依赖项

- Stripe SDK
- Prisma ORM
- 环境变量：`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`

---

## 技术方案

### 架构设计

```
┌─────────────────────────────┐
│       API Endpoints         │
│                             │
│  POST /payments/intent      │
│  POST /payments/confirm     │
│  POST /payments/webhook     │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│      Service Layer          │
│                             │
│  PaymentService             │
│  - createIntent()           │
│  - confirmPayment()         │
│  - handleWebhook()          │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│      Data Layer             │
│                             │
│  Prisma + MySQL             │
│  - Payment                  │
│  - Order                    │
└─────────────────────────────┘
```

### 数据模型

```prisma
model Payment {
  id            String   @id @default(uuid())
  orderId       String
  amount        Decimal
  currency      String   @default("usd")
  status        String
  stripeIntentId String  @unique
  metadata      Json?
  createdAt     DateTime @default(now())
  updatedAt     DateTime @updatedAt

  order         Order    @relation(fields: [orderId], references: [id])
}
```

### API 端点

1. **创建支付意图**
   - 端点：`POST /api/payments/create-intent`
   - 认证：需要用户 token
   - 请求体：`{ amount: number, currency: string, orderId: string }`
   - 响应：`{ clientSecret: string, intentId: string }`

2. **Webhook 处理**
   - 端点：`POST /api/payments/webhook`
   - 认证：Stripe 签名验证
   - 处理事件：`payment_intent.succeeded`, `payment_intent.failed`

---

## 实施步骤

1. **安装 Stripe SDK**
   ```bash
   pnpm add stripe
   pnpm add -D @types/stripe
   ```

2. **创建支付服务**
   - 文件：`src/services/payment.service.ts`
   - 实现支付意图创建
   - 实现 webhook 处理

3. **创建 API 路由**
   - 文件：`src/api/routes/payments.routes.ts`
   - 配置路由和中间件

4. **实现 webhook 验证**
   - 使用 Stripe signature 验证
   - 处理各种事件类型

5. **更新数据库模型**
   - 添加 Payment 表
   - 运行迁移

6. **错误处理和日志**
   - 统一错误响应
   - 记录支付相关日志

---

## 验收标准

- [ ] POST /payments/create-intent 返回有效的 clientSecret
- [ ] Webhook 端点正确验证 Stripe 签名
- [ ] 支付成功时更新订单状态
- [ ] 支付失败时记录错误信息
- [ ] API 有适当的错误处理
- [ ] 所有操作记录日志
- [ ] 单元测试覆盖率 > 80%

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| Webhook 重复处理 | 使用 Stripe 事件的 idempotency key |
| 网络超时 | 设置合理的超时时间和重试机制 |
| 并发问题 | 使用数据库事务确保一致性 |
| 密钥泄露 | 使用环境变量，不提交到代码库 |

---

## 环境变量

```env
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

---

**相关文档:**
- [支付 API 文档](../../../02-api/payments.md)
- [Stripe 官方文档](https://stripe.com/docs/api)
- [项目状态](../../../04-projects/moxton-lotapi.md)
