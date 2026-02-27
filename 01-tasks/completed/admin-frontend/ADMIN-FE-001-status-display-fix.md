# ADMIN-FE-001: 订单状态显示优化

**创建时间**: 2025-02-09
**优先级**: 低
**任务类型**: 前端
**关联项目**: moxton-lotadmin

---

## 需求描述

将订单状态 `CONFIRMED` 的显示文本从"已确认"改为"待发货"，更符合业务流程理解。

---

## 修改文件

**文件**: `E:\moxton-lotadmin\src\views\online-order\index.vue`

**位置**: 第 25-32 行

---

## 修改内容

```typescript
// 修改前
const statusMap = {
  PENDING: { text: '待付款', type: 'warning' },
  PAID: { text: '已付款', type: 'info' },
  CONFIRMED: { text: '已确认', type: 'primary' },
  SHIPPED: { text: '已发货', type: 'info' },
  DELIVERED: { text: '已完成', type: 'success' },
  CANCELLED: { text: '已取消', type: 'error' }
} as const;

// 修改后
const statusMap = {
  PENDING: { text: '待付款', type: 'warning' },
  PAID: { text: '已付款', type: 'info' },
  CONFIRMED: { text: '待发货', type: 'primary' },
  SHIPPED: { text: '已发货', type: 'info' },
  DELIVERED: { text: '已完成', type: 'success' },
  CANCELLED: { text: '已取消', type: 'error' }
} as const;
```

---

## 验收标准

1. ✅ 订单列表中 `CONFIRMED` 状态显示为"待发货"
2. ✅ 订单详情中 `CONFIRMED` 状态显示为"待发货"（如果详情页也有状态映射）

---

## 影响范围

- 订单列表页状态列
- 订单详情页状态显示（如有独立状态映射）
