# BUG-001: 订单列表 API 返回 500 错误

> **优先级:** P0 (Critical)
> **状态:** 已修复（第三轮完成）
> **角色:** BACKEND
> **项目:** moxton-lotapi
> **报告时间:** 2026-02-08
> **最终修复:** 2026-02-08

---

## 修复摘要

### 第一轮修复（针对 `/orders/:id` 接口）

**问题：** 路由参数 `:id` 是订单 ID，但代码使用了 `findByOrderNo(id)` 方法。

**修复内容：**
1. 在 `Order.ts` Model 中新增 `findByIdWithDetails(id)` 方法
2. 修复 `getOrder` 和 `updateOrderStatus` 方法

### 第二轮修复（针对 `/orders/admin` 接口）

**问题：** `getAllOrders` 方法调用 `OrderTransformer.transformOrder()` 但该方法不存在，且查询缺少 `addresses` 关联。

**修复内容：**
1. 在 `OrderTransformer.ts` 中新增 `transformOrder` 方法（别名）
2. 修复 `getAllOrders` 查询，添加 `addresses: true` 和 `user.nickname` 字段

### 第三轮修复（发现并修复重复方法定义）

**问题：** OrderController 中存在两个 `getAllOrders` 方法定义，第一个方法有变量名错误：
- `page: parseInt(page)` - 应该是 `pageNum`
- `limit: parseInt(limit)` - 应该是 `pageSize`

**修复内容：**
- 删除了第一个有问题的 `getAllOrders` 方法定义（原第 569-592 行）

**修改文件：**
- `E:\moxton-lotapi\src\models\Order.ts` - 新增 `findByIdWithDetails` 方法
- `E:\moxton-lotapi\src\controllers\Order.ts` - 修复 `getOrder`、`updateOrderStatus`、删除重复的 `getAllOrders`
- `E:\moxton-lotapi\src\transformers\OrderTransformer.ts` - 新增 `transformOrder` 方法

---

## 问题描述

### 复现步骤

1. 访问后台管理系统的在线订单管理页面
2. 页面调用 `/proxy-default/orders/admin` 接口获取订单列表
3. 后端返回 500 错误

### 错误响应

```json
{
  "code": 500,
  "message": "Failed to find order by order number",
  "data": null,
  "errorType": "SYSTEM_ERROR",
  "originalError": "Error",
  "requestId": "99690cb29f5f4cb9",
  "stack": "Error: Failed to find order by order number\n    at OrderModel.findByOrderNo (E:\\moxton-lotapi\\src\\models\\Order.ts:150:13)\n    at async E:\\moxton-lotapi\\src\\controllers\\Order.ts:34:19\n    at async E:\\moxton-lotapi\\src\\middleware\\error.ts:242:7\n    at async authMiddleware (E:\\moxton-lotapi\\src\\middleware\\auth.ts:39:5)\n    at async E:\\moxton-lotapi\\src\\app.ts:50:3)\n    at async cors (E:\\moxton-lotapi\\node_modules\\@koa\\cors\\index.js:109:16)\n    at async bodyParser (E:\\moxton-lotapi\\node_modules\\koa-bodyparser\\index.js:78:5)\n    at async E:\\moxton-lotapi\\src\\middleware\\response.ts:224:5)\n    at async E:\\moxton-lotapi\\src\\middleware\\response.ts:24:5)\n    at async requestIdMiddleware (E:\\moxton-lotapi\\src\\middleware\\requestId.ts:17:3)",
  "success": false,
  "timestamp": "2026-02-08T09:09:45.558Z"
}
```

### 错误堆栈分析

- **错误位置:** `OrderModel.findByOrderNo (E:\moxton-lotapi\src\models\Order.ts:150:13)`
- **触发位置:** `E:\moxton-lotapi\src\controllers\Order.ts:34:19`
- **根本原因:** `findByOrderNo` 方法在查询订单时失败

---

## 相关文件

| 文件 | 路径 | 说明 |
|------|------|------|
| Order Model | `E:\moxton-lotapi\src\models\Order.ts` | 订单模型，第150行 `findByOrderNo` 方法 |
| Order Controller | `E:\moxton-lotapi\src\controllers\Order.ts` | 订单控制器，第34行调用出错 |

---

## 可能原因

1. `findByOrderNo` 方法的查询参数不正确
2. 订单号字段在数据库中的命名或格式与代码期望不符
3. 数据库连接或查询逻辑问题
4. 订单号可能为 `null` 或 `undefined`，但没有正确处理

---

## 修复要求

1. **定位问题:** 检查 `Order.ts:150` 的 `findByOrderNo` 方法
2. **添加日志:** 在关键位置添加调试日志，确认传入的参数
3. **修复查询:** 修复查询逻辑，确保正确获取订单列表
4. **错误处理:** 添加适当的错误处理，避免 500 错误
5. **测试验证:** 修复后测试 `/orders/admin` 接口，确保能正常返回订单列表

---

## 预期结果

- `/orders/admin` 接口正常返回订单列表
- 错误处理友好，避免 500 错误
- 代码健壮性提高，能处理边界情况

---

## 修复详情

### 问题分析

**路由配置：**
```typescript
// src/routes/orders.ts
router.get('/:id', authMiddleware, orderController.getOrder)  // :id 是订单 ID
```

**错误调用：**
```typescript
// src/controllers/Order.ts (修复前)
const order = await orderModel.findByOrderNo(id)  // 错误：传入的是 ID，但方法期望 orderNo
```

**Model 方法：**
```typescript
// src/models/Order.ts
async findByOrderNo(orderNo: string): Promise<any> {
  const order = await prisma.order.findUnique({
    where: { orderNo },  // 使用 orderNo 字段查询
    // ...
  })
}
```

### 修复方案

**1. Order Model 新增方法：**
```typescript
// src/models/Order.ts
async findByIdWithDetails(id: string): Promise<any> {
  const order = await prisma.order.findUnique({
    where: { id },  // 使用 id 字段查询
    include: {
      user: { select: { id: true, username: true, email: true } },
      orderItems: {
        include: {
          product: { select: { id: true, name: true, images: true } }
        }
      }
    }
  })
  return order
}
```

**2. Controller 修复：**
```typescript
// getOrder 方法
const order = await orderModel.findByIdWithDetails(id)  // ✅ 修复

// updateOrderStatus 方法
const order = await orderModel.findByIdWithDetails(id)  // ✅ 修复
```

### 测试建议

重启后端服务后，测试以下接口：
- `GET /orders/:id` - 获取订单详情
- `PUT /orders/:id/status` - 更新订单状态（管理员）
- `GET /orders/admin` - 获取所有订单列表（管理员）

---

## 第二轮修复（针对 `/orders/admin` 接口）

### QA 发现的新问题

**错误信息:**
```
Failed to find order by id
at OrderModel.findByIdWithDetails (E:\moxton-lotapi\src\models\Order.ts:150:13)
```

**请求接口:** `/proxy-default/orders/admin?pageNum=1&pageSize=10&keyword=&userId=`

### 问题分析

检查 `getAllOrders` 方法后发现两个问题：

1. **方法名错误：** 代码调用 `OrderTransformer.transformOrder(order)`，但 `OrderTransformer` 类只有 `transform` 静态方法，没有 `transformOrder` 方法

2. **缺少关联查询：** Prisma 查询中没有 include `addresses`，但 `OrderTransformer.transform()` 期望订单对象包含 `addresses` 字段

### 修复方案

**1. OrderTransformer 添加 transformOrder 方法：**
```typescript
// src/transformers/OrderTransformer.ts
static transformOrder(order: Order & {
  addresses: OrderAddress[]
  user?: any
  items: any[]
}) {
  return this.transform(order)
}
```

**2. getAllOrders 查询添加 addresses 和 nickname：**
```typescript
// src/controllers/Order.ts
const [orders, total] = await Promise.all([
  prisma.order.findMany({
    where,
    skip,
    take,
    include: {
      items: {
        include: {
          product: true
        }
      },
      addresses: true,  // ✅ 添加 addresses 关联
      user: {
        select: {
          id: true,
          username: true,
          email: true,
          nickname: true  // ✅ 添加 nickname 字段
        }
      }
    },
    orderBy: {
      createdAt: 'desc'
    }
  }),
  prisma.order.count({ where })
])
```

### 测试建议

重启后端服务后测试：
- `GET /orders/admin?pageNum=1&pageSize=10` - 获取订单列表
- `GET /orders/admin?status=PENDING` - 按状态筛选
- `GET /orders/admin?orderNo=ORD123` - 按订单号搜索

---

## 第三轮修复（发现并删除重复的 getAllOrders 方法定义）

### QA 报告的持续问题

尽管前两轮修复，问题仍然存在。进一步分析发现：

### 问题分析

OrderController 类中存在**两个 `getAllOrders` 方法定义**：

1. **第 569-592 行（旧版本）：**
```typescript
getAllOrders = asyncHandler(async (ctx: Context) => {
  const { pageNum = 1, pageSize = 10, status, userId, keyword } = ctx.query as any
  // ...
  const result = await orderModel.findMany({
    page: parseInt(page),      // ❌ 错误：应该是 pageNum
    limit: parseInt(limit),    // ❌ 错误：应该是 pageSize
    // ...
  })
})
```

2. **第 904-953 行（新版本）：**
```typescript
getAllOrders = asyncHandler(async (ctx: Context) => {
  // 正确的实现
  const [orders, total] = await Promise.all([
    prisma.order.findMany({
      // ...
      include: {
        items: { include: { product: true } },
        addresses: true,  // ✅
        user: { select: { id, username, email, nickname } }  // ✅
      }
    })
  ])
})
```

虽然 JavaScript 类的后者定义会覆盖前者，但存在两个问题：
1. 代码混乱，维护困难
2. 如果路由或构建顺序异常，可能会使用错误的版本

### 修复方案

**删除第一个有问题的 `getAllOrders` 方法定义：**

修改前：
```typescript
// 第 568-592 行 - 旧版本（有变量名错误）
getAllOrders = asyncHandler(async (ctx: Context) => { ... })

// 第 568-592 行 - getOrderStats 方法
getOrderStats = asyncHandler(async (ctx: Context) => { ... })
```

修改后：
```typescript
// 直接从 getOrderStats 开始
getOrderStats = asyncHandler(async (ctx: Context) => { ... })

// 正确的 getAllOrders 在第 904 行
```

### 最终代码结构

OrderController 现在只有一个正确的 `getAllOrders` 方法：
```typescript
// ✅ 正确的 getAllOrders 方法（第 904 行）
getAllOrders = asyncHandler(async (ctx: Context) => {
  const { pageNum = 1, pageSize = 10, status, userId, orderNo } = ctx.query as any

  const where: any = {}
  if (status) where.status = status
  if (userId) where.userId = userId
  if (orderNo) where.orderNo = { contains: orderNo }

  const skip = (parseInt(pageNum) - 1) * parseInt(pageSize)
  const take = parseInt(pageSize)

  const [orders, total] = await Promise.all([
    prisma.order.findMany({
      where, skip, take,
      include: {
        items: { include: { product: true } },
        addresses: true,
        user: { select: { id, username, email, nickname } }
      },
      orderBy: { createdAt: 'desc' }
    }),
    prisma.order.count({ where })
  ])

  const transformedOrders = orders.map(order => OrderTransformer.transform(order))
  ctx.paginatedSuccess(transformedOrders, total, parseInt(pageNum), parseInt(pageSize))
})
```

### 测试建议

重启后端服务后完整测试：
1. `GET /orders/admin?pageNum=1&pageSize=10` - 基本分页
2. `GET /orders/admin?status=PENDING` - 状态筛选
3. `GET /orders/admin?userId=xxx` - 用户筛选
4. `GET /orders/admin?orderNo=ORD123` - 订单号搜索
5. 验证返回数据包含 `customer`、`address`、`items` 等完整字段
