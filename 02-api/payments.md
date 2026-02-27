# Moxton Lot API - 支付系统接口文档

**版本**: v1.14.0
**最后更新**: 2026-02-09
**服务地址**: http://localhost:3033

---

## 概述

支付系统基于 Stripe Payment Intent API 实现，支持站内支付体验，无需跳转到第三方支付页面。

### 核心特性
- 无缝支付体验：用户在网站内完成支付
- 支持游客支付：无需注册即可下单支付
- 实时状态查询：支付状态实时更新
- 安全可靠：Webhook 签名验证 + 事件去重机制

### 技术架构
```
Routes (payments.ts)
  ↓
Controllers (Payment.ts)
  ↓
Services (StripePaymentService.ts)
  ↓
Models (Payment.ts) + Prisma ORM
```

---

## API 端点

### 1. 创建支付意图

**端点**: `POST /payments/stripe/create-intent`

**认证**: Optional (支持游客和登录用户)

**说明**: 创建 Stripe 支付意图，返回 `clientSecret` 供前端 Stripe Elements 使用

**请求头**:
```http
Content-Type: application/json
Authorization: Bearer <token>       // 可选，登录用户需提供
X-Guest-ID: <guest-session-id>     // 游客必填，用于验证订单归属
```

**请求体**:
```json
{
  "orderId": "clt123456789"  // 必需 - 订单ID (字符串类型)
}
```

**成功响应** (200 OK):
```json
{
  "code": 200,
  "message": "Payment intent created successfully",
  "data": {
    "clientSecret": "pi_1234567890_secret_xxxxxxxxxxxxxxxxxxxx",
    "publishableKey": "pk_test_51SWp4fAdUxdJL62WadIF0ekRQWLcoQ0RHijCvfQXePy0QHPt7uqJ407X02vgpVvo0SgAkwMZWEqK13JturY4q8cv0015drns3F",
    "paymentIntentId": "pi_1234567890",
    "paymentId": "clt123456789",
    "amount": 599.98,
    "currency": "AUD",
    "expiresAt": "2025-12-18T15:30:00.000Z"
  },
  "success": true,
  "timestamp": "2025-12-18T10:00:00.000Z"
}
```

**错误响应**:
```json
{
  "code": 400,
  "message": "Failed to create payment intent: Order not found",
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

**错误码**:
- `400`: `orderId is required` - 缺少订单ID
- `400`: `Failed to create payment intent: Order not found` - 订单不存在
- `400`: `Failed to create payment intent: Order is not eligible for payment` - 订单状态不允许支付
- `400`: `Failed to create payment intent: Payment already in progress` - 支付已在进行中
- `403`: `Access denied: Order does not belong to user` - 订单不属于当前登录用户
- `403`: `Access denied: Order does not belong to this guest session` - 游客订单与 X-Guest-ID 不匹配

**权限验证逻辑**:

**登录用户**:
1. 从 `ctx.user?.id` 获取用户ID
2. 验证订单 `userId` 与当前用户ID匹配
3. 不匹配返回 403 错误

**游客用户**:
1. 从请求头 `X-Guest-ID` 获取游客会话ID
2. 验证订单 `userId=null`（游客订单）
3. 解析订单 `metadata.guestId` 字段
4. 验证 `guestId` 与 `X-Guest-ID` 匹配
5. 不匹配返回 403 错误

**实现细节**:
- 从 `ctx.user?.id` 获取用户ID（支持游客，返回 `null`）
- 从请求头 `X-Guest-ID` 获取游客会话ID（游客必填）
- 调用 `stripePaymentService.createPaymentIntent()` 创建支付意图
- 提取设备信息（`user-agent`, `ip`）用于安全追踪
- 游客订单：验证 `X-Guest-ID` 与订单 `metadata.guestId` 匹配

---

### 2. 获取支付状态

**端点**: `GET /payments/stripe/status/:paymentIntentId`

**认证**: Optional (智能权限验证)

**说明**: 实时查询 Stripe 支付意图状态，用于前端状态轮询

**路径参数**:
- `paymentIntentId`: Stripe 支付意图ID (例如: `pi_1234567890`)

**成功响应** (200 OK):
```json
{
  "code": 200,
  "message": "Payment status retrieved successfully",
  "data": {
    "status": "requires_payment_method",
    "requiresAction": false,
    "nextActionType": null,
    "lastPaymentError": null,
    "amount": 59998,
    "currency": "aud"
  },
  "success": true,
  "timestamp": "2025-12-18T10:00:00.000Z"
}
```

**Stripe 状态说明**:
| 状态 | 说明 |
|------|------|
| `requires_payment_method` | 需要添加支付方式 |
| `requires_confirmation` | 需要确认支付 |
| `requires_action` | 需要额外操作 (3D Secure) |
| `processing` | 支付处理中 |
| `succeeded` | 支付成功 |
| `canceled` | 支付取消 |
| `requires_capture` | 需要捕获资金 |

**错误响应**:
- `400`: `paymentIntentId is required` - 缺少支付意图ID
- `500`: `Failed to get payment status: [具体错误]` - 状态查询失败

---

### 3. Stripe Webhook

**端点**: `POST /payments/stripe/webhook`

**认证**: None (通过 Stripe 签名验证)

**说明**: 接收 Stripe 支付事件通知，异步更新支付状态

**请求头**:
```http
Content-Type: application/json
stripe-signature: stripe_signature_hash
```

**支持的 Stripe 事件类型**:
| 事件类型 | 处理逻辑 |
|---------|---------|
| `payment_intent.succeeded` | 支付成功，更新订单和支付记录 |
| `payment_intent.payment_failed` | 支付失败，记录错误信息 |
| `payment_intent.canceled` | 支付取消，更新状态 |
| `payment_intent.payment_expired` | 支付过期，自动取消订单（24小时） |
| `payment_intent.requires_action` | 需要3D Secure等额外验证 |
| `payment_intent.partially_funded` | 部分资金到账 |

**成功响应**:
```http
Status: 200 OK
Body: "OK"
```

**错误响应**:
```http
Status: 400 Bad Request
Body: "Webhook Error: Invalid webhook signature"
```

**安全机制**:
1. **签名验证**: 验证 Stripe 事件签名
2. **时效性检查**: 事件时间戳超过5分钟拒绝处理（防重放攻击）
3. **事件去重**: Redis + 数据库双重去重机制
4. **快速响应**: 立即返回 200，异步处理事件

**实现细节**:
- 从 `ctx.headers['stripe-signature']` 获取签名
- 从 `ctx.request.rawBody` 获取原始请求体
- 使用 `stripePaymentService.verifyWebhookSignature()` 验证签名
- 调用 `checkEventProcessed()` 检查事件是否已处理
- 调用 `markEventProcessed()` 标记事件为已处理

---

### 4. 获取支付历史

**端点**: `GET /payments/history`

**认证**: Required (需要用户认证)

**说明**: 获取当前用户的支付历史记录，支持分页和状态过滤

**请求头**:
```http
Authorization: Bearer <token>
```

**查询参数**:
```typescript
{
  pageNum?: number,   // 可选 - 页码，默认 1
  pageSize?: number,  // 可选 - 每页大小，默认 10
  status?: string     // 可选 - 支付状态过滤 (PENDING, SUCCESS, FAILED 等)
}
```

**成功响应** (200 OK):
```json
{
  "code": 200,
  "message": "Success",
  "data": [
    {
      "id": "clt123456789",
      "paymentNo": "PAY202512180001",
      "orderId": "clt123456788",
      "userId": null,
      "amount": "599.98",
      "currency": "AUD",
      "paymentMethod": "STRIPE",
      "status": "SUCCESS",
      "paymentIntentId": "pi_1234567890",
      "createdAt": "2025-12-18T09:30:00.000Z",
      "paidAt": "2025-12-18T09:35:00.000Z",
      "order": {
        "orderNo": "ORD202512180001",
        "totalAmount": "599.98",
        "createdAt": "2025-12-18T09:25:00.000Z"
      }
    }
  ],
  "pagination": {
    "pageNum": 1,
    "pageSize": 10,
    "total": 25,
    "totalPages": 3
  },
  "success": true,
  "timestamp": "2025-12-18T10:00:00.000Z"
}
```

**错误响应**:
- `403`: `Authentication required` - 需要用户认证
- `500`: `Failed to get payment history: [具体错误]` - 获取支付历史失败

**实现细节**:
- 从 `ctx.user?.id` 获取用户ID
- 支持按 `status` 字段过滤
- 使用 `prisma.payment.findMany()` 查询支付记录
- 包含订单信息（`orderNo`, `totalAmount`, `createdAt`）
- 使用 `ctx.paginatedSuccess()` 返回分页数据

---

## 数据模型

### Payment 模型

```typescript
model Payment {
  id                      String        @id @default(cuid())
  paymentNo               String        @unique
  orderId                 String
  userId                  String?       // 支持游客支付

  // 金额相关
  amount                  Decimal       @db.Decimal(10, 2)
  currency                String        @default("AUD") // 澳洲市场

  // 支付方式
  paymentMethod           String        // STRIPE, OFFLINE
  paymentProvider         String?       // stripe
  status                  PaymentStatus @default(PENDING)

  // Stripe Elements 特定字段
  paymentIntentId                String?   // Stripe Payment Intent ID
  paymentIntentClientSecret      String?   // 客户端密钥
  paymentMethodId                String?   // 支付方法 ID
  lastPaymentError               String?   @db.Text // 最后一次支付错误

  // 兼容旧版本字段
  stripePaymentIntentId  String?   // 保留兼容性
  checkoutSessionId      String?
  providerPaymentId      String?
  providerCustomerId     String?
  paypalOrderId          String?

  // 安全字段
  paymentAttemptCount    Int       @default(0)
  deviceInfo             String?   @db.Text
  clientIp               String?

  // 时间戳
  expiresAt              DateTime?
  paidAt                 DateTime?
  refundedAt             DateTime?
  createdAt              DateTime  @default(now())
  updatedAt              DateTime  @updatedAt
  metadata               String?   @db.Text

  // 关系
  order                  Order     @relation(fields: [orderId], references: [id])
  user                   User?     @relation(fields: [userId], references: [id])

  @@index([orderId])
  @@index([userId])
  @@index([paymentIntentId])
  @@map("payments")
}
```

### PaymentStatus 枚举

```typescript
enum PaymentStatus {
  PENDING              // 待支付
  PAYMENT_INITIATED    // 支付已启动
  REQUIRES_ACTION      // 需要额外操作（3D Secure）
  PROCESSING           // 处理中
  SUCCESS              // 支付成功
  FAILED               // 支付失败
  CANCELLED            // 支付取消
  EXPIRED              // 支付过期
  REFUNDED             // 已退款
}
```

### OrderPaymentStatus 枚举

```typescript
enum OrderPaymentStatus {
  PENDING    // 待支付
  PAID       // 已支付
  FAILED     // 支付失败
  EXPIRED    // 支付过期
  REFUNDED   // 已退款
}
```

### ProcessedWebhookEvent 模型（事件去重）

```typescript
model ProcessedWebhookEvent {
  id          String    @id @default(cuid())
  eventId     String    @unique  // Stripe 事件ID
  processedAt DateTime  @default(now())
  eventType   String?            // 事件类型

  @@index([eventId])
  @@map("processed_webhook_events")
}
```

---

## 前端集成指南

### Stripe Elements SDK 集成

**1. 安装 Stripe.js**:
```bash
npm install @stripe/stripe-js
```

**2. 初始化 Stripe**:
```typescript
import { loadStripe } from '@stripe/stripe-js';

const stripe = await loadStripe('pk_test_51SWp4fAdUxdJL62WadIF0ekRQWLcoQ0RHijCvfQXePy0QHPt7uqJ407X02vgpVvo0SgAkwMZWEqK13JturY4q8cv0015drns3F');
```

**3. 创建支付意图**:
```typescript
// 调用后端API创建支付意图
const headers: Record<string, string> = {
  'Content-Type': 'application/json',
};

// 如果是登录用户，添加认证token
if (isLoggedIn) {
  headers['Authorization'] = `Bearer ${token}`;
}

// 如果是游客，必须提供 X-Guest-ID
if (!isLoggedIn) {
  headers['X-Guest-ID'] = guestId;
}

const response = await fetch('http://localhost:3033/payments/stripe/create-intent', {
  method: 'POST',
  headers,
  body: JSON.stringify({
    orderId: 'clt123456789'
  })
});

const result = await response.json();

if (result.success) {
  const { clientSecret, publishableKey } = result.data;

  // 使用返回的clientSecret初始化Elements
  const stripe = await loadStripe(publishableKey);
  const elements = stripe.elements({ clientSecret });
} else {
  // 处理错误，包括权限错误
  console.error('Payment intent creation failed:', result.message);
}
```

**4. 创建支付表单**:
```typescript
// 创建卡片输入元素
const cardElement = elements.create('card', {
  style: {
    base: {
      color: '#424770',
      fontSize: '16px',
      '::placeholder': {
        color: '#aab7c4',
      },
    },
    invalid: {
      color: '#9e2146',
    },
  },
});

// 挂载到DOM
cardElement.mount('#card-element');
```

**5. 处理支付**:
```typescript
// 确认支付
const { error, paymentIntent } = await stripe.confirmPayment({
  elements,
  confirmParams: {
    return_url: `${window.location.origin}/payment/confirm`,
  },
  redirect: 'if_required'
});

if (error) {
  // 处理错误
  console.error('Payment failed:', error.message);
} else if (paymentIntent) {
  // 支付成功
  console.log('Payment succeeded!', paymentIntent);

  // 轮询支付状态确认
  pollPaymentStatus(paymentIntent.id);
}
```

### 支付状态轮询

```typescript
async function pollPaymentStatus(paymentIntentId: string, maxAttempts = 30) {
  let attempts = 0;

  while (attempts < maxAttempts) {
    try {
      const response = await fetch(`http://localhost:3033/payments/stripe/status/${paymentIntentId}`);
      const result = await response.json();

      if (result.success) {
        const { data } = result;

        if (data.status === 'succeeded') {
          return { success: true, status: data.status };
        }

        if (data.status === 'canceled' || data.status === 'requires_payment_method') {
          return {
            success: false,
            status: data.status,
            error: data.lastPaymentError
          };
        }
      }

      // 等待2秒后再次查询
      await new Promise(resolve => setTimeout(resolve, 2000));
      attempts++;
    } catch (error) {
      console.error('Status poll error:', error);
      attempts++;
    }
  }

  return { success: false, error: 'Payment timeout' };
}
```

### 3D Secure 处理

```typescript
const { error, paymentIntent } = await stripe.confirmPayment({
  elements,
  confirmParams: {
    return_url: `${window.location.origin}/payment/confirm`,
  },
  redirect: 'if_required' // 自动处理3D Secure
});

if (error?.type === 'card_error' && error.code === 'transaction_requires_authentication') {
  // 3D Secure验证失败，需要用户重新尝试
  console.log('3D Secure authentication failed');
  // 显示错误信息，引导用户重新支付
}

// 如果需要重定向（某些银行需要）
if (paymentIntent?.next_action?.type === 'redirect_to_url') {
  // Stripe会自动处理重定向
  window.location.href = paymentIntent.next_action.redirect_to_url.url;
}
```

---

## 安全和性能

### Webhook 安全验证

```typescript
import Stripe from 'stripe';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);

function verifyWebhookSignature(payload: string, signature: string, secret: string): Stripe.Event {
  try {
    return stripe.webhooks.constructEvent(payload, signature, secret);
  } catch (error) {
    console.error('Webhook signature verification failed:', error);
    throw new Error('Invalid webhook signature');
  }
}
```

### 防重复支付措施

| 措施 | 实现方式 |
|------|---------|
| 幂等性检查 | 基于订单ID检查是否已有活跃支付 |
| 支付意图过期 | 30分钟自动过期机制 |
| 状态锁 | 支付进行中禁止创建新支付 |
| 设备追踪 | 记录支付时的设备信息和IP地址 |
| 事件去重 | Redis + 数据库双重去重机制 |

### 性能优化

| 优化项 | 实现方式 |
|--------|---------|
| 异步处理 | Webhook 事件异步处理，避免阻塞 |
| 并发控制 | Promise.all 并行处理相关操作 |
| 分页查询 | 支付历史使用分页，避免大数据量 |
| 数据库索引 | 关键字段建立索引优化查询性能 |
| 缓存机制 | Redis 缓存已处理的 Webhook 事件 |

---

## 错误处理

### HTTP 状态码

| 状态码 | 说明 |
|--------|------|
| 200 | 成功 |
| 400 | 请求参数错误 |
| 403 | 权限不足 |
| 500 | 服务器内部错误 |

### 业务错误代码

| 错误代码 | 说明 |
|---------|------|
| 4001 | 支付记录不存在 |
| 4002 | 支付状态不允许此操作 |
| 4003 | 支付金额不匹配 |
| 3001 | 订单不存在 |
| 3002 | 订单状态不允许此操作 |

---

## 服务层架构

### StripePaymentService

支付业务逻辑核心服务，负责：

1. **支付意图管理**
   - 创建 Stripe Payment Intent
   - 查询支付意图状态
   - 处理支付成功/失败/取消事件

2. **安全验证**
   - Webhook 签名验证
   - 支付金额二次验证
   - 防重复支付检查

3. **状态同步**
   - 同步支付状态到数据库
   - 更新订单状态
   - 记录支付历史

### CacheService

缓存服务，负责：

1. **Webhook 事件去重**
   - 检查事件是否已处理（Redis）
   - 标记事件为已处理
   - 设置过期时间（7天）

2. **性能优化**
   - 减少数据库查询
   - 快速响应该重复事件

---

## 代码文件结构

```
src/
├── routes/
│   └── payments.ts                    # 支付路由定义
├── controllers/
│   └── Payment.ts                     # 支付控制器
├── services/
│   ├── StripePaymentService.ts        # Stripe 支付服务
│   └── CacheService.ts                # 缓存服务
├── models/
│   └── Payment.ts                     # 支付数据模型
└── middleware/
    └── auth.ts                        # 认证中间件 (authMiddleware, optionalAuthMiddleware)
```

---

## 重要说明

### 认证方式

- **optionalAuthMiddleware**: 支持游客和登录用户的混合模式
  - 登录用户：`ctx.user` 包含用户信息
  - 游客用户：`ctx.user` 为 `null`
  - 从 `ctx.headers['authorization']` 获取 Bearer token

- **authMiddleware**: 必须登录用户
  - 未登录返回 403 错误

### 响应格式

所有 API 响应遵循统一格式：

```typescript
// 成功响应
ctx.success(data, message)

// 分页响应
ctx.paginatedSuccess(data, total, pageNum, pageSize)

// 错误响应
ctx.error(message, statusCode)

// 验证错误
ctx.validationError(fields)

// 权限错误
ctx.forbidden(message)
```

### 日志记录

系统使用 Winston 记录以下日志：

- 支付意图创建失败
- 支付状态查询失败
- Webhook 处理失败
- 支付历史获取失败
- 安全事件（重复事件、过期事件等）

---

## 版本历史

### v1.14.0 (2026-02-09)
- 添加 `X-Guest-ID` 请求头到创建支付意图接口
- 添加游客支付权限校验：验证 `X-Guest-ID` 与订单 `metadata.guestId` 匹配
- 添加 403 错误码：`Access denied: Order does not belong to this guest session`
- 更新权限验证逻辑说明

### v1.13.0 (2026-02-04)
- 完全重写支付系统，从 Stripe Checkout Session 升级为 Stripe Elements + Payment Intent API
- 新增支付意图创建端点
- 新增支付状态查询端点
- 新增 Webhook 事件去重机制
- 新增支付过期事件处理
- 支持 24 小时支付过期自动取消订单

### v1.12.x (已废弃)
- 使用 Stripe Checkout Session 跳转模式
- 相关端点已移除

---

## 支持和帮助

如有问题，请联系技术支持或查看：
- Stripe 官方文档: https://docs.stripe.com/api
- Stripe Webhooks: https://docs.stripe.com/webhooks
- Stripe Payment Intents: https://docs.stripe.com/api/payment_intents
