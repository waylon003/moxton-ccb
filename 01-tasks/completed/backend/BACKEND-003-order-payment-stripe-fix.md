# Tech-Spec: 在线订单 + Stripe 支付模块修复

**创建时间:** 2026-02-09
**状态:** 准备开发
**角色:** 后端工程师
**项目:** moxton-lotapi
**优先级:** P0
**技术栈:** Node.js + Koa + TypeScript + Prisma + MySQL

---

## 概述

### 问题陈述

当前在线订单与 Stripe 支付模块存在以下关键问题：

1. **OrderStatus 枚举缺失 `CONFIRMED`** - 管理员无法设置 `CONFIRMED`，发货接口被锁死
2. **`metadata` 字段写入类型不一致** - 多处直接写对象，字段类型为 `String`，易报错
3. **订单未绑定支付记录** - 创建支付后未写回 `order.paymentId`
4. **访客支付授权缺失** - 任意人可用 `orderId` 创建支付意图

### 解决方案

1. 完善 OrderStatus 枚举，增加 `CONFIRMED` 状态
2. 统一 `metadata` 字段的 JSON 序列化/反序列化处理
3. 补齐订单与支付记录的绑定逻辑
4. 强制校验访客支付的 `X-Guest-ID` 请求头

### 范围 (包含/排除)

**包含:**
- Prisma schema 更新（OrderStatus 增加 CONFIRMED）
- 订单状态流转逻辑统一
- metadata 字段规范化处理
- 支付意图创建时的订单绑定
- 访客支付权限校验
- Stripe Webhook 处理优化

**不包含:**
- 前端 Stripe Elements 集成（由 SHOP-FE 负责）
- 后台管理界面开发（由 ADMIN-FE 负责）
- Stripe 账户配置

---

## 开发上下文

### 现有实现

**相关文件位置:**
```
E:\moxton-lotapi\
├── prisma/
│   └── schema.prisma                    # OrderStatus 枚举定义
├── src/
│   ├── modules/
│   │   ├── order/
│   │   │   ├── order.service.ts        # 订单业务逻辑
│   │   │   └── order.controller.ts     # 订单 API 端点
│   │   └── payment/
│   │       ├── payment.service.ts      # 支付业务逻辑
│   │       └── stripe.controller.ts    # Stripe API 端点
│   └── webhooks/
│       └── stripe.webhook.ts           # Stripe Webhook 处理
```

### 依赖项

- Stripe SDK（已安装）
- Prisma ORM（已配置）
- Koa.js 框架
- MySQL 数据库

---

## 技术方案

### API 设计

**涉及的 API 端点:**

| 方法 | 路径 | 变更说明 |
|------|------|----------|
| POST | `/payments/stripe/create-intent` | 增加 `X-Guest-ID` 强制校验 |
| PUT | `/orders/admin/:id/ship` | 状态从 `PAID` 改为要求 `CONFIRMED` |
| PUT | `/orders/admin/:id/deliver` | 状态从 `SHIPPED` 要求不变 |
| POST | `/webhooks/stripe` | 优化状态流转逻辑 |

### 数据模型

**Prisma Schema 变更:**

```prisma
enum OrderStatus {
  PENDING
  PAID
  CONFIRMED      // 新增
  SHIPPED
  DELIVERED
  CANCELLED
}

model Order {
  // 现有字段保持不变
  paymentId         String?       // 需要补齐绑定逻辑
  paymentStatus     PaymentStatus
  metadata          String        // 需要统一 JSON 处理
  lastPaymentAttemptAt DateTime?  // 需要补齐更新
}
```

### 业务逻辑

#### 1. 订单状态流转规则

```
PENDING ──支付成功──> PAID ──自动确认──> CONFIRMED ──管理员发货──> SHIPPED ──确认收货──> DELIVERED
   │                                                              │
   └─────────────────────────────取消─────────────────────────────┘
```

#### 2. metadata 规范

**写入:**
```typescript
metadata = JSON.stringify({
  guestId: string,
  trackingNumber?: string,
  deliveryNotes?: string
})
```

**读取:**
```typescript
try {
  const data = JSON.parse(order.metadata)
} catch (e) {
  // 处理解析错误
}
```

#### 3. 支付意图创建流程

```typescript
// 1. 校验 X-Guest-ID 请求头
// 2. 验证 guestId === order.metadata.guestId
// 3. 创建 Stripe PaymentIntent
// 4. 写回 order.paymentId
// 5. 更新 order.paymentStatus = PAYMENT_INITIATED
// 6. 记录 order.lastPaymentAttemptAt
```

#### 4. 访客支付权限校验

**请求头要求:**
```
X-Guest-ID: <访客唯一标识>
```

**校验逻辑:**
```typescript
const requestGuestId = ctx.headers['x-guest-id']
const orderGuestId = JSON.parse(order.metadata).guestId

if (requestGuestId !== orderGuestId) {
  throw new Error('Unauthorized: Guest ID mismatch')
}
```

---

## 实施步骤

### Step 1: 数据结构更新

1. 修改 `prisma/schema.prisma`
   - `enum OrderStatus` 增加 `CONFIRMED`
2. 执行 Prisma 迁移:
   ```bash
   npx prisma migrate dev -n add_confirmed_status
   ```

### Step 2: 订单状态逻辑统一

1. 校验管理员更新状态时允许 `CONFIRMED`
2. 支付成功 Webhook 流程:
   - `PENDING → PAID`
   - 自动 `PAID → CONFIRMED`

### Step 3: metadata 统一处理

1. 所有写入 `metadata` 的位置改为 `JSON.stringify`
2. 所有读取 `metadata` 位置加 `try/catch` 解析

**涉及文件:**
- `order.service.ts` - 订单创建、发货、收货、取消
- `payment.service.ts` - 支付过期处理

### Step 4: 支付意图创建补齐绑定

1. 创建 payment 后立即写回 `order.paymentId`
2. 同步更新 `paymentStatus` 与 `lastPaymentAttemptAt`

**文件:**
- `payment.service.ts` - `createPaymentIntent()` 方法

### Step 5: 访客支付校验

1. 在支付意图创建逻辑中校验 `X-Guest-ID`
2. 拒绝不匹配的访客请求

**文件:**
- `stripe.controller.ts` - `/create-intent` 端点

---

## 验收标准

- [ ] **A1. 数据库迁移成功** - `CONFIRMED` 状态已添加到 OrderStatus 枚举
- [ ] **A2. 订单创建正常** - `POST /orders/checkout` 返回订单，`metadata.guestId` 存在且为 JSON 字符串
- [ ] **A3. 创建支付意图** - `POST /payments/stripe/create-intent` 携带正确的 `X-Guest-ID` 时返回 `clientSecret` + `paymentIntentId`
- [ ] **A4. 访客支付权限拦截** - 错误的 `X-Guest-ID` 被拒绝，返回 403
- [ ] **A5. Stripe 测试支付成功** - 使用测试卡 `4242 4242 4242 4242` 支付后，订单状态变为 `PAID → CONFIRMED`
- [ ] **A6. 订单绑定支付记录** - `order.paymentId` 字段已正确写入
- [ ] **A7. 发货接口正常** - `PUT /orders/admin/:id/ship` 仅 `CONFIRMED` 状态可执行
- [ ] **A8. 收货接口正常** - `PUT /orders/admin/:id/deliver` 仅 `SHIPPED` 状态可执行
- [ ] **A9. metadata 解析安全** - 所有读取 metadata 的位置都有 try/catch 保护

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| Webhook 处理异常导致订单状态卡死 | 保留基础 `payment_intent.succeeded` 逻辑，暂停非必要事件处理 |
| `CONFIRMED` 状态迁移影响现有数据 | 若迁移失败，可暂时将支付成功后只保留 `PAID` |
| metadata JSON 解析失败 | 所有读取位置加 try/catch，解析失败时返回空对象 |
| 访客 ID 篡改 | 仅作基础校验，生产环境建议结合 IP 限流 |

---

**相关文档:**
- [API 文档](../../02-api/)
- [项目状态](../../04-projects/moxton-lotapi.md)
- [原始修复方案](../../../FIX-PLAN-order-payment-stripe.md)
