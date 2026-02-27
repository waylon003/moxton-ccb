# BACKEND-004: 补充/修改物流信息接口

**创建时间**: 2025-02-09
**优先级**: 中
**任务类型**: 后端
**关联项目**: moxton-lotapi

---

## 需求描述

允许管理员在发货后补充或修改订单的物流信息（物流单号、物流公司、发货备注）。

---

## 接口定义

**路径**: `PATCH /orders/admin/:id/shipping-info`

**权限**: 管理员

**参数**:
```typescript
{
  trackingNumber?: string;  // 物流单号
  carrier?: string;         // 物流公司
  notes?: string;           // 发货备注
}
```

---

## 业务规则

### 1. 状态限制
- 只有 `SHIPPED` 状态的订单可以修改物流信息
- `DELIVERED`（已完成）订单不允许修改（历史记录不应变更）

### 2. 更新逻辑
- 部分更新：只传需要修改的字段
- 覆盖更新：新值覆盖旧值，不传的字段保持不变

### 3. 操作记录
- 修改物流信息时，需要在 `OnlineOrderHistory` 中记录操作
- 操作类型建议：`SHIPPING_INFO_UPDATED`

---

## 实现要求

**文件**: `E:\moxton-lotapi\src\controllers\Order.ts`

```typescript
updateShippingInfo = asyncHandler(async (ctx: Context) => {
  const { id } = ctx.params;
  const { trackingNumber, carrier, notes } = ctx.request.body as any;

  // 1. 验证订单存在
  const order = await prisma.order.findUnique({
    where: { id },
    select: { id: true, status: true, metadata: true }
  });

  if (!order) {
    return ctx.notFound('Order not found');
  }

  // 2. 验证订单状态
  if (order.status !== 'SHIPPED') {
    return ctx.badRequest('Only SHIPPED orders can update shipping info');
  }

  // 3. 解析现有 metadata
  const existingMetadata = order.metadata ? JSON.parse(order.metadata as string) : {};

  // 4. 合并新的物流信息
  const updatedMetadata = {
    ...existingMetadata,
    ...(trackingNumber && { trackingNumber }),
    ...(carrier && { carrier }),
    ...(notes !== undefined && { shippingNotes: notes }) // notes 允许清空
  };

  // 5. 更新订单
  await prisma.order.update({
    where: { id },
    data: {
      metadata: JSON.stringify(updatedMetadata)
    }
  });

  // 6. 记录操作历史（如果 BACKEND-002 已完成）
  if (prisma.onlineOrderHistory) {
    await prisma.onlineOrderHistory.create({
      data: {
        orderId: id,
        action: 'SHIPPING_INFO_UPDATED',
        operatorId: ctx.user!.id,
        notes: `更新物流信息: ${[trackingNumber, carrier, notes].filter(Boolean).join(', ') || '清空部分信息'}`
      }
    });
  }

  return ctx.ok({ message: 'Shipping info updated successfully' });
});
```

---

## 路由配置

**文件**: `E:\moxton-lotapi\src\routers\order.ts`

```typescript
// 补充/修改物流信息
router.patch('/admin/:id/shipping-info', auth, adminRole, orderController.updateShippingInfo);
```

---

## 验收标准

1. ✅ `SHIPPED` 状态的订单可以更新物流信息
2. ✅ `DELIVERED` 状态的订单不允许更新
3. ✅ 支持部分更新（只传需要修改的字段）
4. ✅ 未传字段保持原值不变
5. ✅ 更新成功后返回成功响应
6. ✅ 如果 BACKEND-002 已完成，更新时记录操作历史

---

## 测试用例

```bash
# 场景1: 补充完整物流信息
curl -X PATCH "http://localhost:3000/orders/admin/{id}/shipping-info" \
  -H "Authorization: Bearer {token}" \
  -H "Content-Type: application/json" \
  -d '{
    "trackingNumber": "SF1234567890",
    "carrier": "顺丰速运",
    "notes": "轻拿轻放"
  }'

# 场景2: 只修改物流单号
curl -X PATCH "http://localhost:3000/orders/admin/{id}/shipping-info" \
  -H "Authorization: Bearer {token}" \
  -H "Content-Type: application/json" \
  -d '{"trackingNumber": "YT9876543210"}'

# 场景3: 清空发货备注
curl -X PATCH "http://localhost:3000/orders/admin/{id}/shipping-info" \
  -H "Authorization: Bearer {token}" \
  -H "Content-Type: application/json" \
  -d '{"notes": ""}'

# 预期返回
{
  "message": "Shipping info updated successfully"
}
```

---

## 前端配合（可选）

**对应前端任务**: ADMIN-FE-005

在订单详情页添加"修改物流信息"按钮，仅 `SHIPPED` 状态时显示。
