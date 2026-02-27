# BUG-002: findByIdWithDetails 使用错误的字段名

> **优先级:** P0 (Critical)
> **状态:** 发现新问题
> **角色:** BACKEND
> **项目:** moxton-lotapi
> **发现时间:** 2026-02-08
> **发现方式:** QA 测试

---

## 问题描述

### Bug 详情

`findByIdWithDetails` 方法在 Prisma 查询中使用了错误的字段名 `orderItems`，但 schema 中定义的是 `items`。

### 错误堆栈

```
Error: Failed to find order by id
    at OrderModel.findByIdWithDetails (E:\moxton-lotapi\src\models\Order.ts:150:13)
    at E:\moxton-lotapi\src\controllers\Order.ts:558:19
```

### 根本原因

**Schema 定义 (prisma/schema.prisma 第136行):**
```prisma
model Order {
  ...
  items               OrderItem[]  // ✅ 正确字段名: items
  ...
}
```

**错误代码 (src/models/Order.ts 第139行):**
```typescript
include: {
  user: { select: { id: true, username: true, email: true } },
  orderItems: {  // ❌ 错误: 应该是 items
    include: {
      product: { select: { id: true, name: true, images: true } }
    }
  }
}
```

### 影响范围

- `GET /orders/admin/:id` - 获取订单详情失败
- `PUT /orders/admin/:id/status` - 更新订单状态失败
- `PUT /orders/admin/:id/ship` - 发货失败
- `PUT /orders/admin/:id/deliver` - 确认收货失败

所有需要通过 ID 查询订单的管理员功能都会受影响。

---

## 修复方案

### 文件: `E:\moxton-lotapi\src\models\Order.ts`

将 `findByIdWithDetails` 方法中的 `orderItems` 改为 `items`:

```typescript
async findByIdWithDetails(id: string): Promise<any> {
  try {
    const order = await prisma.order.findUnique({
      where: { id },
      include: {
        user: {
          select: { id: true, username: true, email: true }
        },
        items: {  // ✅ 修复: orderItems → items
          include: {
            product: {
              select: { id: true, name: true, images: true }
            }
          }
        }
      }
    })
    return order
  } catch (error) {
    throw new Error('Failed to find order by id')
  }
}
```

---

## 测试验证

修复后，使用以下命令测试:

```bash
# 1. 重新生成 Prisma Client
cd E:\moxton-lotapi
npx prisma generate

# 2. 重启后端服务
npm run dev

# 3. 生成测试 token
node -e "const jwt = require('jsonwebtoken'); const payload = {id: 'admin-id', username: 'admin', email: 'admin@moxton.com', role: 'admin'}; console.log(jwt.sign(payload, 'your-super-secret-jwt-key'));"

# 4. 测试订单详情 API
TOKEN="<生成的token>"
ORDER_ID="<从订单列表获取的订单ID>"
curl -H "Authorization: Bearer $TOKEN" "http://localhost:3033/orders/admin/$ORDER_ID"

# 5. 测试更新订单状态
curl -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"status":"PAID"}' "http://localhost:3033/orders/admin/$ORDER_ID/status"
```

---

## 相关文件

| 文件 | 行号 | 问题 |
|------|------|------|
| `E:\moxton-lotapi\src\models\Order.ts` | 139 | `orderItems` 应改为 `items` |
| `E:\moxton-lotapi\prisma\schema.prisma` | 136 | Schema 定义为 `items` |

---

## 预期结果

修复后:
- `GET /orders/admin/:id` 应返回完整订单详情（包含商品列表）
- `PUT /orders/admin/:id/status` 应成功更新订单状态
- 其他管理员订单操作API应正常工作

---

**发现者:** admin-fe-qa
**分配给:** backend
