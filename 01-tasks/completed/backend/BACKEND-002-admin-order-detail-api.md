# BACKEND-002: 管理员获取订单详情 API

**创建时间:** 2026-02-08
**状态:** 准备开发
**角色:** 后端工程师 (BACKEND)
**项目:** moxton-lotapi
**优先级:** P0
**技术栈:** Node.js + Koa + TypeScript + Prisma + MySQL

---

## 概述

### 问题陈述

后台管理系统需要查看订单详情功能，但当前后端缺少管理员专用的订单详情接口。

**现状：**
- `GET /orders/:id` 接口存在，但使用 `authMiddleware`，有 `isOrderBelongsToUser` 权限检查
- 管理员无法通过该接口查看所有订单的详情
- 前端调用 `/orders/admin/:id` 返回 404

### 解决方案

新增管理员专用的订单详情接口 `GET /orders/admin/:id`，使用 `adminMiddleware` 进行权限验证，允许管理员查看任意订单的完整详情。

### 范围 (包含/排除)

**包含:**
- 新增 `GET /orders/admin/:id` 接口
- 使用 `adminMiddleware` 权限验证
- 返回完整订单详情（使用 `OrderTransformer.transform`）
- 包含用户信息、收货地址、商品列表、支付信息、物流信息

**不包含:**
- 订单创建（已有接口）
- 订单状态修改（已有接口）
- 订单发货（已有接口）

---

## 开发上下文

### 现有实现

**相关文件:**
- 路由定义: `E:\moxton-lotapi\src\routes\orders.ts`
- 控制器: `E:\moxton-lotapi\src\controllers\Order.ts`
- 模型: `E:\moxton-lotapi\src\models\Order.ts`
- 数据转换: `E:\moxton-lotapi\src\transformers\OrderTransformer.ts`

**现有类似接口:**
```typescript
// 普通用户订单详情（有权限检查）
GET /orders/:id
- Middleware: authMiddleware
- Controller: getOrder
- 权限检查: isOrderBelongsToUser
```

**已有的管理员订单接口:**
```typescript
GET /orders/admin              - 获取订单列表
PUT /orders/admin/:id/ship     - 发货
PUT /orders/admin/:id/deliver  - 确认收货
PUT /orders/admin/:id/status   - 更新状态
GET /orders/admin/stats/all    - 订单统计
```

### 依赖项

- `adminMiddleware` - 已存在的管理员权限中间件
- `OrderModel.findByIdWithDetails` - 已存在的方法（需确认字段名已修复为 `items`）
- `OrderTransformer.transform` - 已存在的数据转换方法
- Prisma Order 模型 - 已定义

---

## 技术方案

### API 设计

**端点:** `GET /orders/admin/:id`

**认证:** Required + Admin (`adminMiddleware`)

**路径参数:**
- `id` - 订单 ID（数据库主键，字符串格式）

**响应 (200 OK):**
```json
{
  "code": 200,
  "message": "Success",
  "data": {
    "id": "cmjc8hq970017vf8gikafzjas",
    "orderNo": "ORD17660554764519925",
    "customer": {
      "id": "user_id",
      "name": "张三",
      "email": "user@example.com",
      "phone": "+86-13900139000",
      "isGuest": false
    },
    "address": {
      "recipientName": "张三",
      "phone": "+86-13900139000",
      "street": "123 Main St",
      "city": "Sydney",
      "state": "NSW",
      "zipCode": "2000",
      "country": "Australia",
      "fullAddress": "123 Main St, Sydney NSW 2000, Australia"
    },
    "items": [
      {
        "id": "item_id",
        "product": {
          "id": "product_id",
          "name": "商品名称",
          "image": "https://oss.example.com/image.jpg",
          "price": 129.00
        },
        "quantity": 2,
        "subtotal": 258.00
      }
    ],
    "amount": {
      "subtotal": 258.00,
      "discount": 0.00,
      "shipping": 0.00,
      "total": 258.00,
      "currency": "AUD"
    },
    "status": "CONFIRMED",
    "paymentStatus": "COMPLETED",
    "paymentMethod": "Stripe",
    "metadata": {
      "trackingNumber": "SF1234567890",
      "carrier": "顺丰快递",
      "shippingNotes": "已发货"
    },
    "remarks": "客户备注",
    "timestamps": {
      "created": "2025-12-18T10:00:00.000Z",
      "updated": "2025-12-18T15:00:00.000Z",
      "paid": "2025-12-18T10:05:00.000Z",
      "shipped": "2025-12-18T15:00:00.000Z",
      "delivered": null
    }
  },
  "timestamp": "2025-12-18T15:30:00.000Z",
  "success": true
}
```

**错误响应 (404 Not Found):**
```json
{
  "code": 404,
  "message": "Order not found",
  "data": null,
  "errorType": "NOT_FOUND",
  "success": false,
  "timestamp": "2025-12-18T15:30:00.000Z"
}
```

### 业务逻辑

1. **权限验证:** 使用 `adminMiddleware` 确保请求者是管理员
2. **查询订单:** 使用 `findByIdWithDetails(id)` 获取订单完整数据
3. **数据转换:** 使用 `OrderTransformer.transform()` 转换为响应格式
4. **错误处理:** 订单不存在时返回 404

---

## 实施步骤

### Step 1: 在 OrderController 中新增方法

**文件:** `E:\moxton-lotapi\src\controllers\Order.ts`

```typescript
/**
 * 管理员获取订单详情
 * GET /orders/admin/:id
 */
getAdminOrderDetail = asyncHandler(async (ctx: Context) => {
  const { id } = ctx.params;

  // 查询订单详情
  const order = await orderModel.findByIdWithDetails(id);

  if (!order) {
    return ctx.notFound('Order not found');
  }

  // 使用 Transformer 转换数据
  const transformedOrder = OrderTransformer.transform(order);

  ctx.success(transformedOrder);
});
```

### Step 2: 在路由文件中添加路由

**文件:** `E:\moxton-lotapi\src\routes\orders.ts`

```typescript
// 在管理员路由组中添加
router.get('/admin/:id', adminMiddleware, orderController.getAdminOrderDetail);
```

**位置:** 建议放在 `GET /orders/admin` 之后，其他 `/orders/admin/:id/*` 路由之前

### Step 3: 确认 OrderModel.findByIdWithDetails 正确

**文件:** `E:\moxton-lotapi\src\models\Order.ts`

确认 `findByIdWithDetails` 方法使用正确的字段名：

```typescript
async findByIdWithDetails(id: string): Promise<any> {
  const order = await prisma.order.findUnique({
    where: { id },
    include: {
      user: {
        select: {
          id: true,
          username: true,
          email: true,
          nickname: true
        }
      },
      items: {  // ✅ 确认是 items 不是 orderItems
        include: {
          product: {
            select: {
              id: true,
              name: true,
              images: true,  // 或 image
              price: true
            }
          }
        }
      },
      addresses: true  // ✅ 确认包含地址信息
    }
  });

  if (!order) {
    throw new Error('Failed to find order by id');
  }

  return order;
}
```

### Step 4: 测试接口

**测试命令:**
```bash
# 获取订单详情
curl -X GET "http://localhost:3000/orders/admin/cmjc8hq970017vf8gikafzjas" \
  -H "Authorization: Bearer <admin-token>"
```

**预期结果:**
- 200 OK - 返回完整订单详情
- 404 Not Found - 订单不存在

### Step 5: 更新 API 文档

**文件:** `E:\moxton-docs\02-api\orders.md`

在管理员端点部分添加：

```markdown
### 获取订单详情

**GET** `/orders/admin/:id`

**认证**: Required + Admin

**路径参数:**
- `id` - 订单 ID

**响应:** (同上技术方案)
```

---

## 验收标准

- [ ] 接口 `GET /orders/admin/:id` 正常响应
- [ ] 使用 `adminMiddleware` 权限验证
- [ ] 返回完整的订单详情数据
- [ ] 订单不存在时返回 404
- [ ] 数据格式与 `OrderTransformer.transform` 一致
- [ ] API 文档已更新

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| `findByIdWithDetails` 字段名错误 (`orderItems` vs `items`) | 确保 Step 3 检查并修复字段名 |
| 路由顺序冲突（需要放在其他 `/admin/:id/*` 路由之前） | 注意路由定义顺序，将详情路由放在更新类路由之前 |
| 数据转换不一致 | 复用现有的 `OrderTransformer.transform` 方法 |
| 权限验证遗漏 | 使用已存在的 `adminMiddleware` |

---

## 相关依赖

### 前置任务
- [BACKEND-001] 订单列表接口修复（orderItems → items 字段名修复）

### 后续任务
- [ADMIN-FE-001] 在线订单管理页面 - 前端需要调用此接口获取订单详情

---

**相关文档:**
- [API 文档](../../02-api/orders.md)
- [项目状态](../../04-projects/moxton-lotapi.md)
- [前端任务](../admin-frontend/ADMIN-FE-001-online-order-management.md)
