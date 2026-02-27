# BACKEND-002: 订单操作历史功能

**创建时间**: 2025-02-09
**优先级**: 中
**任务类型**: 后端
**关联项目**: moxton-lotapi

---

## 需求描述

为在线订单添加操作历史记录功能，包括创建数据表、自动记录操作和提供查询接口。

---

## 子任务

### 1. 创建数据模型

**文件**: `E:\moxton-lotapi\prisma\schema.prisma`

参考 `OfflineOrderHistory` 模型（第 446-482 行），创建 `OnlineOrderHistory` 模型：

```prisma
model OnlineOrderHistory {
  id          String   @id @default(cuid())
  orderId     String
  order       Order    @relation(fields: [orderId], references: [id], onDelete: Cascade)
  action      String   // 操作类型: CREATED, PAID, CONFIRMED, SHIPPED, DELIVERED, CANCELLED
  operatorId  String?  // 操作人ID
  operator    User?    @relation("OnlineOrderHistoryOperator", fields: [operatorId], references: [id])
  notes       String?  // 备注信息
  metadata    String?  @db.Text // 额外信息（JSON格式）
  createdAt   DateTime @default(now())

  @@index([orderId])
  @@index([createdAt])
}
```

**同时更新 Order 模型**，添加关联：
```prisma
model Order {
  // ... 现有字段
  history     OnlineOrderHistory[]
}
```

**更新 User 模型**，添加关联：
```prisma
model User {
  // ... 现有字段
  onlineOrderHistories   OnlineOrderHistory[] @relation("OnlineOrderHistoryOperator")
}
```

---

### 2. 实现历史记录逻辑

**文件**: `E:\moxton-lotapi\src\controllers\Order.ts`

创建辅助方法 `recordOrderHistory`：

```typescript
private recordOrderHistory = async (
  orderId: string,
  action: string,
  operatorId?: string,
  notes?: string,
  metadata?: any
) => {
  await prisma.onlineOrderHistory.create({
    data: {
      orderId,
      action,
      operatorId,
      notes,
      metadata: metadata ? JSON.stringify(metadata) : null
    }
  });
}
```

**在以下操作中调用此方法**：
- 订单创建 → `CREATED`
- 订单支付 → `PAID`
- 订单确认 → `CONFIRMED`
- 订单发货 → `SHIPPED`
- 订单收货 → `DELIVERED`
- 订单取消 → `CANCELLED`

---

### 3. 提供查询接口

**文件**: `E:\moxton-lotapi\src\controllers\Order.ts`

添加方法 `getOrderHistory`：

```typescript
getOrderHistory = asyncHandler(async (ctx: Context) => {
  const { id } = ctx.params;

  const history = await prisma.onlineOrderHistory.findMany({
    where: { orderId: id },
    include: {
      operator: {
        select: {
          id: true,
          username: true,
          nickname: true
        }
      }
    },
    orderBy: { createdAt: 'desc' }
  });

  return ctx.ok(history);
});
```

---

### 4. 添加路由

**文件**: `E:\moxton-lotapi\src\routers\order.ts`

添加路由：
```typescript
// 获取订单操作历史
router.get('/admin/:id/history', auth, adminRole, orderController.getOrderHistory);
```

---

## 验收标准

1. ✅ Prisma 迁移成功执行，`OnlineOrderHistory` 表创建
2. ✅ 订单状态变更时自动记录历史
3. ✅ `GET /orders/admin/:id/history` 接口返回正确的历史记录
4. ✅ 历史记录包含操作时间、操作人信息、操作类型和备注

---

## 测试用例

```bash
# 执行 Prisma 迁移
npx prisma migrate dev --name add_online_order_history

# 测试历史记录接口
curl -X GET "http://localhost:3000/orders/admin/{id}/history" \
  -H "Authorization: Bearer {token}"

# 预期返回
[
  {
    "id": "...",
    "orderId": "...",
    "action": "SHIPPED",
    "operator": {
      "id": "...",
      "username": "admin",
      "nickname": "管理员"
    },
    "notes": "顺丰速运",
    "metadata": "{\"trackingNumber\":\"SF1234567890\"}",
    "createdAt": "2025-02-09T10:30:00.000Z"
  }
  // ... 更多历史记录
]
```
