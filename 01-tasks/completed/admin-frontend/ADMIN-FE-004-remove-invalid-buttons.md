# ADMIN-FE-004: 移除无效按钮

**创建时间**: 2025-02-09
**优先级**: 低
**任务类型**: 前端
**关联项目**: moxton-lotadmin

---

## 需求描述

在线订单无法手动新增和删除，需要移除列表页的"新增"按钮和"批量删除"按钮。

---

## 修改文件

**文件**: `E:\moxton-lotadmin\src\views\online-order\index.vue`

---

## 修改内容

### 1. 移除新增按钮

**位置**: 查找页面顶部的新增按钮（通常在表格上方工具栏）

**移除类似代码**:
```vue
<NButton type="primary" @click="handleAdd">
  <template #icon><NIcon :component="Plus" /></template>
  新增订单
</NButton>
```

---

### 2. 移除批量删除按钮

**位置**: 查找批量操作相关的按钮

**移除类似代码**:
```vue
<NButton type="error" :disabled="!checkedRowKeys.length" @click="handleBatchDelete">
  批量删除
</NButton>
```

**同时移除**:
- `checkedRowKeys` 相关的状态定义
- 表格的 `row-key` 和 `@update:checked-row-keys` 绑定（如果仅用于批量删除）
- `handleBatchDelete` 方法

---

## 验收标准

1. ✅ 列表页无"新增订单"按钮
2. ✅ 列表页无"批量删除"按钮
3. ✅ 页面功能正常，无控制台错误

---

## 说明

在线订单由用户在前台创建，后台无法手动新增。订单取消而非删除，因此不需要批量删除功能。
