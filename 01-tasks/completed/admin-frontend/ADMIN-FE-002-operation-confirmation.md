# ADMIN-FE-002: 订单操作二次确认

**创建时间**: 2025-02-09
**优先级**: 中
**任务类型**: 前端
**关联项目**: moxton-lotadmin

---

## 需求描述

为取消订单和确认收货操作添加二次确认弹窗，防止误触。

---

## 子任务

### 1. 确认收货添加二次确认

**文件**: `E:\moxton-lotadmin\src\views\online-order\modules\online-order-detail.vue`

**当前实现** (第 253-258 行):
```vue
<NButton v-if="canConfirmDelivery" type="success" @click="handleConfirmDelivery">
  <template #icon>
    <NIcon :component="CircleCheck" />
  </template>
  确认收货
</NButton>
```

**修改为**: 使用 `NPopconfirm` 包裹
```vue
<NPopconfirm @positive-click="handleConfirmDelivery">
  <template #trigger>
    <NButton v-if="canConfirmDelivery" type="success">
      <template #icon>
        <NIcon :component="CircleCheck" />
      </template>
      确认收货
    </NButton>
  </template>
  确认将此订单标记为已收货吗？
</NPopconfirm>
```

---

### 2. 检查并确保取消订单有二次确认

**检查文件**:
1. `E:\moxton-lotadmin\src\views\online-order\index.vue` (列表页)
2. `E:\moxton-lotadmin\src\views\online-order\modules\online-order-detail.vue` (详情页)

**确保**: 两处取消订单操作都使用 `NPopconfirm` 组件进行二次确认。

**列表页** (index.vue 第 199-228 行):
```vue
<NPopconfirm @positive-click="() => handleCancelOrder(row.id)">
  <template #trigger>
    <NButton>取消订单</NButton>
  </template>
  确认取消此订单吗？
</NPopconfirm>
```

**详情页** (online-order-detail.vue 第 228-243 行):
```vue
<NPopconfirm @positive-click="handleCancelOrder">
  <template #trigger>
    <NButton type="warning">取消订单</NButton>
  </template>
  确认取消此订单吗？
</NPopconfirm>
```

---

## 验收标准

1. ✅ 点击"确认收货"按钮时弹出二次确认弹窗
2. ✅ 点击"取消订单"按钮时弹出二次确认弹窗
3. ✅ 点击"取消"不执行操作
4. ✅ 点击"确认"才执行对应操作

---

## 交互示意

```
用户点击 [确认收货]
    ↓
弹出弹窗: "确认将此订单标记为已收货吗？" [取消] [确认]
    ↓
用户点击 [确认]
    ↓
执行确认收货操作
```
