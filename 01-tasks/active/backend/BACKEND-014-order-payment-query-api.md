# Tech-Spec: 新增订单支付查询 API

**任务ID:** BACKEND-014
**创建时间:** 2026-03-09
**状态:** 准备开发
**角色:** 后端工程师
**项目:** moxton-lotapi (E:\moxton-lotapi)
**优先级:** P1
**技术栈:** Node.js + Koa + TypeScript + Prisma + MySQL

---

## 执行上下文（强约束）

- **Task File = 唯一执行输入源**：派遣消息可能是短文本，必须以本任务文件为准，不得依赖派遣消息补充细节。
- **工作目录**：`E:\moxton-lotapi`
- **必读文档**：
  - `E:\moxton-lotapi\CLAUDE.md`
  - `E:\moxton-lotapi\AGENTS.md`
  - `E:\moxton-ccb\02-api\payments.md` - 支付 API 文档
  - `E:\moxton-ccb\02-api\orders.md` - 订单 API 文档
- **开始后 60 秒内**：必须 `report_route(status="in_progress")`
- **执行中每 90~120 秒**：发送一次 `in_progress` 心跳
- **遇阻塞 2 分钟内**：`report_route(status="blocked", body="blocker_type=...;question=...;attempted=...;next_action_needed=...")`
- **完成后必须**：`report_route(status="success|fail|blocked", body=变更文件+命令+测试结果)`

---

## 概述

### 问题陈述

当前前端在进入支付页面时，会直接调用 `POST /payments/stripe/create-intent` 创建新的支付意图。但如果订单已有活跃的支付意图（用户刷新页面、返回支付页面等场景），后端会返回 400 错误："Payment already in progress"。

前端需要一个 API 来查询订单是否已有活跃的支付意图，以便决定是复用现有的还是创建新的。

### 解决方案

新增 `GET /payments/order/:orderId` API 端点，返回订单关联的支付记录。前端可以通过此接口：
1. 检查订单是否已有活跃的支付意图
2. 如果有且状态为 PENDING/PAYMENT_INITIATED/REQUIRES_ACTION 且未过期，复用其 `clientSecret`
3. 否则创建新的支付意图

### 范围 (包含/排除)

**包含:**
- 新增 `GET /payments/order/:orderId` API 端点
- 返回订单关联的支付记录（按创建时间倒序）
- 支持游客和登录用户权限验证
- 更新 API 文档（`E:\moxton-ccb\02-api\payments.md`）

**不包含:**
- 前端逻辑修改（由 SHOP-FE-013 任务处理）
- 支付意图自动清理逻辑
- 支付记录的删除或归档功能

---

## 开发上下文

### 现有实现

**相关文件：**
- `src/routes/payments.ts` - 支付路由定义
- `src/controllers/Payment.ts` - 支付控制器
- `src/services/StripePaymentService.ts` - Stripe 支付服务
- `src/models/Payment.ts` - 支付数据模型

**现有支付 API：**
- `POST /payments/stripe/create-intent` - 创建支付意图
- `GET /payments/stripe/status/:paymentIntentId` - 查询支付意图状态
- `POST /payments/stripe/webhook` - Stripe Webhook 回调
- `GET /payments/history` - 获取支付历史（需要登录）

### 前置依赖

无（独立任务）

### 依赖项

- 使用现有的 `optionalAuthMiddleware` 中间件（支持游客和登录用户）
- 使用现有的 Prisma Payment 模型
- 使用现有的权限验证逻辑（参考 `create-intent` 端点）

---

## 技术方案

### API 设计

**端点**: `GET /payments/order/:orderId`

**认证**: Optional (支持游客和登录用户)

**说明**: 查询订单关联的支付记录，优先返回活跃的支付意图

**路径参数**:
- `orderId`: 订单ID (例如: `clt123456789`)

**请求头**:
```http
Authorization: Bearer <token>       // 可选，登录用户需提供
X-Guest-ID: <guest-session-id>     // 游客必填，用于验证订单归属
```

**成功响应** (200 OK):
```json
{
  "code": 200,
  "message": "Payment records retrieved successfully",
  "data": {
    "orderId": "clt123456789",
    "payments": [
      {
        "id": "clt987654321",
        "paymentNo": "PAY202603090001",
        "paymentIntentId": "pi_1234567890",
        "clientSecret": "pi_1234567890_secret_xxxxxxxxxxxxxxxxxxxx",
        "amount": 599.98,
        "currency": "AUD",
        "status": "PENDING",
        "expiresAt": "2026-03-09T10:30:00.000Z",
        "createdAt": "2026-03-09T10:00:00.000Z"
      }
    ],
    "activePayment": {
      "id": "clt987654321",
      "paymentIntentId": "pi_1234567890",
      "clientSecret": "pi_1234567890_secret_xxxxxxxxxxxxxxxxxxxx",
      "status": "PENDING",
      "expiresAt": "2026-03-09T10:30:00.000Z"
    }
  },
  "success": true,
  "timestamp": "2026-03-09T10:05:00.000Z"
}
```

**说明：**
- `payments`: 所有支付记录（按创建时间倒序，最多返回最近 5 条）
- `activePayment`: 活跃的支付意图（状态为 PENDING/PAYMENT_INITIATED/REQUIRES_ACTION 且未过期），如果没有则为 `null`

**错误响应**:
```json
{
  "code": 400,
  "message": "orderId is required",
  "timestamp": "2026-03-09T10:00:00.000Z",
  "success": false
}
```

**错误码**:
- `400`: `orderId is required` - 缺少订单ID
- `404`: `Order not found` - 订单不存在
- `403`: `Access denied: Order does not belong to user` - 订单不属于当前登录用户
- `403`: `Access denied: Order does not belong to this guest session` - 游客订单与 X-Guest-ID 不匹配

### 权限验证逻辑

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

### 业务逻辑

**活跃支付意图判定标准：**
- 状态为 `PENDING` 或 `PAYMENT_INITIATED` 或 `REQUIRES_ACTION`
- `expiresAt` 大于当前时间（未过期）

**实现流程：**
1. 从路径参数获取 `orderId`
2. 查询订单是否存在
3. 验证订单归属权限（登录用户或游客）
4. 查询订单关联的支付记录（按 `createdAt` 倒序，限制 5 条）
5. 筛选出活跃的支付意图（符合上述判定标准）
6. 返回支付记录列表和活跃支付意图

---

## 实施步骤

### Step 1: 添加路由定义

**目标**: 在 `src/routes/payments.ts` 中添加新路由

**操作**:
```typescript
// 在 payments.ts 中添加
router.get('/order/:orderId', optionalAuthMiddleware, paymentController.getOrderPayments);
```

**验收**:
- [ ] 路由定义已添加
- [ ] 使用 `optionalAuthMiddleware` 中间件

---

### Step 2: 实现控制器方法

**目标**: 在 `src/controllers/Payment.ts` 中实现 `getOrderPayments` 方法

**操作**:
1. 获取 `orderId` 路径参数
2. 验证 `orderId` 是否存在
3. 调用服务层方法获取支付记录
4. 返回成功响应

**代码示例**:
```typescript
async getOrderPayments(ctx: Context) {
  const { orderId } = ctx.params;

  if (!orderId) {
    return ctx.error('orderId is required', 400);
  }

  try {
    const userId = ctx.user?.id || null;
    const guestId = ctx.headers['x-guest-id'] as string | undefined;

    const result = await stripePaymentService.getOrderPayments(orderId, userId, guestId);

    ctx.success(result, 'Payment records retrieved successfully');
  } catch (error: any) {
    console.error('Failed to get order payments:', error);
    ctx.error(error.message || 'Failed to get order payments', error.statusCode || 500);
  }
}
```

**验收**:
- [ ] 控制器方法已实现
- [ ] 参数验证正确
- [ ] 错误处理完善

---

### Step 3: 实现服务层方法

**目标**: 在 `src/services/StripePaymentService.ts` 中实现 `getOrderPayments` 方法

**操作**:
1. 查询订单是否存在
2. 验证订单归属权限
3. 查询支付记录（按创建时间倒序，限制 5 条）
4. 筛选活跃支付意图
5. 返回结果

**代码示例**:
```typescript
async getOrderPayments(orderId: string, userId: string | null, guestId?: string) {
  // 1. 查询订单
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    select: { id: true, userId: true, metadata: true }
  });

  if (!order) {
    const error: any = new Error('Order not found');
    error.statusCode = 404;
    throw error;
  }

  // 2. 权限验证
  if (userId) {
    // 登录用户：验证订单归属
    if (order.userId !== userId) {
      const error: any = new Error('Access denied: Order does not belong to user');
      error.statusCode = 403;
      throw error;
    }
  } else {
    // 游客：验证 X-Guest-ID
    if (order.userId !== null) {
      const error: any = new Error('Access denied: Order does not belong to this guest session');
      error.statusCode = 403;
      throw error;
    }

    const orderMetadata = order.metadata ? JSON.parse(order.metadata as string) : {};
    const orderGuestId = orderMetadata.guestId;

    if (!guestId || orderGuestId !== guestId) {
      const error: any = new Error('Access denied: Order does not belong to this guest session');
      error.statusCode = 403;
      throw error;
    }
  }

  // 3. 查询支付记录
  const payments = await prisma.payment.findMany({
    where: { orderId },
    orderBy: { createdAt: 'desc' },
    take: 5,
    select: {
      id: true,
      paymentNo: true,
      paymentIntentId: true,
      paymentIntentClientSecret: true,
      amount: true,
      currency: true,
      status: true,
      expiresAt: true,
      createdAt: true
    }
  });

  // 4. 筛选活跃支付意图
  const now = new Date();
  const activePayment = payments.find(p =>
    ['PENDING', 'PAYMENT_INITIATED', 'REQUIRES_ACTION'].includes(p.status) &&
    p.expiresAt &&
    p.expiresAt > now
  );

  // 5. 返回结果
  return {
    orderId,
    payments: payments.map(p => ({
      id: p.id,
      paymentNo: p.paymentNo,
      paymentIntentId: p.paymentIntentId,
      clientSecret: p.paymentIntentClientSecret,
      amount: Number(p.amount),
      currency: p.currency,
      status: p.status,
      expiresAt: p.expiresAt,
      createdAt: p.createdAt
    })),
    activePayment: activePayment ? {
      id: activePayment.id,
      paymentIntentId: activePayment.paymentIntentId,
      clientSecret: activePayment.paymentIntentClientSecret,
      status: activePayment.status,
      expiresAt: activePayment.expiresAt
    } : null
  };
}
```

**验收**:
- [ ] 服务层方法已实现
- [ ] 订单查询正确
- [ ] 权限验证逻辑正确（登录用户和游客）
- [ ] 支付记录查询正确（倒序，限制 5 条）
- [ ] 活跃支付意图筛选逻辑正确

---

### Step 4: 测试 API

**目标**: 验证 API 功能正确性

**测试场景**:

1. **登录用户 - 有活跃支付意图**:
   ```bash
   curl -X GET http://localhost:3033/payments/order/clt123456789 \
     -H "Authorization: Bearer <token>"
   ```
   预期：返回 200，`activePayment` 不为 null

2. **登录用户 - 无活跃支付意图**:
   预期：返回 200，`activePayment` 为 null

3. **游客 - 有活跃支付意图**:
   ```bash
   curl -X GET http://localhost:3033/payments/order/clt123456789 \
     -H "X-Guest-ID: <guest-id>"
   ```
   预期：返回 200，`activePayment` 不为 null

4. **权限错误 - 订单不属于用户**:
   预期：返回 403

5. **权限错误 - X-Guest-ID 不匹配**:
   预期：返回 403

6. **订单不存在**:
   预期：返回 404

**验收**:
- [ ] 所有测试场景通过
- [ ] 返回数据格式正确
- [ ] 权限验证正确

---

### Step 5: 更新 API 文档

**目标**: 更新 `E:\moxton-ccb\02-api\payments.md`

**操作**:
在 "API 端点" 部分添加新端点的完整文档，包括：
- 端点说明
- 请求参数
- 请求头
- 成功响应示例
- 错误响应示例
- 权限验证逻辑

**验收**:
- [ ] API 文档已更新
- [ ] 文档格式与现有端点一致
- [ ] 包含完整的请求/响应示例

---

## 验收标准

| # | 标准 | 验证方式 |
|---|------|---------|
| 1 | API 端点正确响应 | 使用 curl 或 Postman 测试 |
| 2 | 登录用户权限验证正确 | 测试不同用户访问不同订单 |
| 3 | 游客权限验证正确 | 测试 X-Guest-ID 匹配和不匹配场景 |
| 4 | 活跃支付意图筛选正确 | 测试不同支付状态和过期时间 |
| 5 | 返回数据格式正确 | 验证响应 JSON 结构 |
| 6 | 错误处理完善 | 测试各种错误场景（404, 403, 400） |
| 7 | API 文档已更新 | 检查 `02-api/payments.md` |
| 8 | 代码无 TypeScript 编译错误 | 运行 `npm run build` |

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 权限验证逻辑与 create-intent 不一致 | 参考 `create-intent` 端点的权限验证实现，保持一致 |
| 支付记录过多导致性能问题 | 限制返回最近 5 条记录 |
| metadata 字段解析失败 | 添加 try-catch 处理 JSON 解析错误 |
| 游客 X-Guest-ID 缺失 | 明确返回 403 错误，提示需要 X-Guest-ID |

---

## 相关文档

- [支付 API 文档](../../02-api/payments.md)
- [订单 API 文档](../../02-api/orders.md)
- [项目状态](../../04-projects/moxton-lotapi.md)
- [项目协调](../../04-projects/COORDINATION.md)

## QA 驳回整改项（必须修复）

1) **核心链路闭环（阻断 SHOP-FE-013）**
- 现象：`GET /payments/order/:orderId` 对“已过期的 PENDING 支付”会返回 `activePayment=null`（正确），但随后 `POST /payments/stripe/create-intent` 仍返回 400 `Payment already in progress`。
- 原因：`validateNoActivePayment()` 仅按状态拦截（PENDING/PAYMENT_INITIATED/PROCESSING/REQUIRES_ACTION 等），**未考虑 expiresAt**。
- 目标：当历史支付已过期时，允许创建新 intent（必要时同步更新/标记历史记录），确保“查询后创建”链路可工作。
- 复现证据：`E:\moxton-ccb\05-verification\BACKEND-014\failure-path.json`（scenario: expired-query-followed-by-create-intent）

2) **构建 Gate**
- QA 执行 `npm run build` 失败，且报出大量 TypeScript 错误（含多个非本任务文件）。
- 要求：请先明确这些错误是否为 baseline（对比干净 main/或提交点），并在回传中**区分 pre-existing vs 本次引入**；若 baseline 即失败且无法在本任务范围内修复，请按协议 `report_route(status="blocked")` 请求拆分/调整 gate。
- 证据：`E:\moxton-ccb\05-verification\BACKEND-014\build.txt`

<!-- AUTO-QA-SUMMARY:BEGIN -->
## QA 摘要（自动回写）

- 最后更新: `2026-03-20T12:29:27+08:00`
- QA Worker: `backend-qa`
- 路由状态: `success`
- 验收结论: `PASS`
- 结论摘要: 新增订单支付查询 API 契约、权限校验、过期支付后重新创建 intent 的闭环已通过验证，当前构建与 Vitest 也为绿色。
- 证据索引:
  - `build`: `PASS` -> `05-verification/BACKEND-014/runtime-precheck-20260320-1223.txt`, `05-verification/BACKEND-014/build-20260320-1223.txt`
  - `contract`: `PASS` -> `05-verification/BACKEND-014/contract-check-20260320-1227.json`
  - `failure_path`: `PASS` -> `05-verification/BACKEND-014/failure-path-20260320-1227.json`
  - `network`: `PASS` -> `05-verification/BACKEND-014/network-20260320-1227.json`
  - `tests`: `PASS` -> `05-verification/BACKEND-014/vitest-20260320-1224.json`
- 验证命令:
  - `node -e "const {spawnSync}=require('node:child_process');const r=spawnSync(process.execPath,['-v']);console.log(r.error?.code||'OK')"`
  - `npm run build`
  - `vitest-mcp: run_tests ./tests/api`
  - `node E:/moxton-ccb/05-verification/BACKEND-014/run-runtime-20260320-1227.js`
- 原始证据仍以 `05-verification/` 中的文件为准。
<!-- AUTO-QA-SUMMARY:END -->
