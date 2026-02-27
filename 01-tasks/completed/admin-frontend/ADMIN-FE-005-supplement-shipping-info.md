# ADMIN-FE-005: 补充物流信息UI

**创建时间**: 2025-02-09
**优先级**: 中
**任务类型**: 前端
**关联项目**: moxton-lotadmin
**前置任务**: BACKEND-004

---

## 需求描述

在订单详情页，当订单状态为 `SHIPPED`（已发货）且缺少物流信息时，显示"补充物流信息"按钮，允许管理员补充或修改物流信息。

---

## 业务规则

### 1. 显示条件

订单满足以下**所有**条件时显示"补充物流信息"按钮：
- 订单状态为 `SHIPPED`
- 物流信息不完整（`trackingNumber`、`carrier`、`notes` 全部为空或不存在）

### 2. 按钮位置

建议放在订单详情页的物流信息区域，或者操作按钮区域。

---

## UI 设计

### 场景1: 有完整物流信息

```
┌─────────────────────────────────────┐
│ 物流信息                              │
├─────────────────────────────────────┤
│ 物流单号: SF1234567890               │
│ 物流公司: 顺丰速运                    │
│ 发货备注: 轻拿轻放                    │
│                                     │
│ [修改物流信息]                        │  ← 可选：也允许修改已有信息
└─────────────────────────────────────┘
```

### 场景2: 无物流信息（SHIPPED 状态）

```
┌─────────────────────────────────────┐
│ 物流信息                              │
├─────────────────────────────────────┤
│ 暂无物流信息                          │
│                                     │
│ [补充物流信息]                        │  ← 显示此按钮
└─────────────────────────────────────┘
```

---

## 修改文件

**文件**: `E:\moxton-lotadmin\src\views\online-order\modules\online-order-detail.vue`

---

## 实现步骤

### 1. 添加 API 方法

**文件**: `E:\moxton-lotadmin\src\service\api\order.ts`

```typescript
export function updateShippingInfo(id: string, data: {
  trackingNumber?: string;
  carrier?: string;
  notes?: string;
}) {
  return request({
    url: `/orders/admin/${id}/shipping-info`,
    method: 'patch',
    data
  });
}
```

---

### 2. 添加物流信息弹窗

```vue
<script setup lang="ts">
// 物流信息弹窗状态
const showShippingModal = ref(false);
const shippingForm = ref({
  trackingNumber: '',
  carrier: '',
  notes: ''
});

// 打开补充物流信息弹窗
const handleOpenShippingModal = () => {
  // 如果已有物流信息，回填到表单
  if (order.value?.metadata) {
    const metadata = JSON.parse(order.value.metadata);
    shippingForm.value = {
      trackingNumber: metadata.trackingNumber || '',
      carrier: metadata.carrier || '',
      notes: metadata.shippingNotes || ''
    };
  }
  showShippingModal.value = true;
};

// 提交物流信息
const handleUpdateShippingInfo = async () => {
  if (!props.orderId) return;

  await onlineOrderService.updateShippingInfo(props.orderId, {
    trackingNumber: shippingForm.value.trackingNumber || undefined,
    carrier: shippingForm.value.carrier || undefined,
    notes: shippingForm.value.notes || undefined
  });

  message.success('物流信息已更新');
  showShippingModal.value = false;
  fetchOrderDetail(); // 刷新订单详情
};

// 判断是否需要显示补充按钮
const needSupplementShipping = computed(() => {
  if (!order.value || order.value.status !== 'SHIPPED') {
    return false;
  }

  const metadata = order.value.metadata ? JSON.parse(order.value.metadata) : {};
  return !metadata.trackingNumber && !metadata.carrier && !metadata.shippingNotes;
});
</script>

<template>
  <!-- 补充物流信息弹窗 -->
  <NModal v-model:show="showShippingModal" preset="card" title="补充物流信息" style="width: 500px">
    <NForm :model="shippingForm" label-placement="left" label-width="80">
      <NFormItem label="物流单号">
        <NInput v-model:value="shippingForm.trackingNumber" placeholder="请输入物流单号" />
      </NFormItem>
      <NFormItem label="物流公司">
        <NInput v-model:value="shippingForm.carrier" placeholder="请输入物流公司" />
      </NFormItem>
      <NFormItem label="发货备注">
        <NInput v-model:value="shippingForm.notes" type="textarea" placeholder="请输入发货备注（可选）" />
      </NFormItem>
    </NForm>
    <template #footer>
      <NSpace justify="end">
        <NButton @click="showShippingModal = false">取消</NButton>
        <NButton type="primary" @click="handleUpdateShippingInfo">确认</NButton>
      </NSpace>
    </template>
  </NModal>

  <!-- 物流信息区域 -->
  <div v-if="order?.status === 'SHIPPED'" class="shipping-info-section">
    <h3>物流信息</h3>
    <div v-if="hasShippingInfo" class="shipping-details">
      <!-- 显示已有物流信息 -->
      <p>物流单号: {{ metadata.trackingNumber }}</p>
      <p>物流公司: {{ metadata.carrier }}</p>
      <p v-if="metadata.shippingNotes">发货备注: {{ metadata.shippingNotes }}</p>
      <NButton type="primary" text @click="handleOpenShippingModal">
        修改物流信息
      </NButton>
    </div>
    <div v-else class="no-shipping-info">
      <p class="text-placeholder">暂无物流信息</p>
      <NButton type="primary" @click="handleOpenShippingModal">
        补充物流信息
      </NButton>
    </div>
  </div>
</template>
```

---

## 验收标准

1. ✅ 订单状态为 `SHIPPED` 且无物流信息时，显示"补充物流信息"按钮
2. ✅ 点击按钮弹出表单弹窗
3. ✅ 表单包含物流单号、物流公司、发货备注三个字段
4. ✅ 提交后调用 `PATCH /orders/admin/:id/shipping-info` 接口
5. ✅ 成功后刷新订单详情，显示补充的物流信息
6. ✅ （可选）已有物流信息时，显示"修改物流信息"按钮，允许修改

---

## 依赖

- **后端接口**: `PATCH /orders/admin/:id/shipping-info` (BACKEND-004)
