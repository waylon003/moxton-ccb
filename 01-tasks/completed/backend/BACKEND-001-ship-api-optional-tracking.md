# BACKEND-001: 发货接口参数调整

**创建时间**: 2025-02-09
**优先级**: 中
**任务类型**: 后端
**关联项目**: moxton-lotapi

---

## 需求描述

将发货接口的物流单号、物流公司、发货备注都改为可选参数，允许先发货（更新状态），后续通过 **BACKEND-004** 接口补充物流信息。

---

## 配合任务

**BACKEND-004**: 补充/修改物流信息接口 (`PATCH /orders/admin/:id/shipping-info`)

发货后如果需要补充或修改物流信息，使用该接口。

---

## 修改文件

**文件**: `E:\moxton-lotapi\src\controllers\Order.ts`

**方法**: `shipOrder` (第 813-877 行)

**当前验证逻辑**:
```typescript
// trackingNumber 是必填的
if (!trackingNumber) {
  return ctx.badRequest('Tracking number is required')
}
```

---

## 修改要求

移除 `trackingNumber` 的必填验证，允许以下场景：
1. 只传 `trackingNumber`（物流单号）
2. 只传 `carrier`（物流公司）
3. 只传 `notes`（发货备注）
4. 全部不传（仅更新订单状态为已发货）
5. 任意组合

**发货时保持记录**:
- 如果提供了物流信息，记录到 `metadata` 中
- 如果未提供，`metadata` 中对应字段为空或不存在

---

## 验收标准

1. ✅ 发货接口允许不传 `trackingNumber`
2. ✅ 发货接口允许不传 `carrier`
3. ✅ 发货接口允许不传 `notes`
4. ✅ 三个参数都为空时，订单状态仍能正常更新为 `SHIPPED`
5. ✅ 提供的参数正确记录到 `metadata` 中

---

## 测试用例

```bash
# 场景1: 无物流信息发货
curl -X PUT "http://localhost:3000/orders/admin/{id}/ship" \
  -H "Authorization: Bearer {token}" \
  -H "Content-Type: application/json"

# 场景2: 仅物流单号
curl -X PUT "http://localhost:3000/orders/admin/{id}/ship" \
  -H "Authorization: Bearer {token}" \
  -H "Content-Type: application/json" \
  -d '{"trackingNumber": "SF1234567890"}'

# 场景3: 完整物流信息
curl -X PUT "http://localhost:3000/orders/admin/{id}/ship" \
  -H "Authorization: Bearer {token}" \
  -H "Content-Type: application/json" \
  -d '{"trackingNumber": "SF1234567890", "carrier": "顺丰速运", "notes": "轻拿轻放"}'
```
