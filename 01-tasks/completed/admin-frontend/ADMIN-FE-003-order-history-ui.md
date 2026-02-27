# ADMIN-FE-003: 操作历史UI对接

**创建时间**: 2025-02-09
**优先级**: 中
**任务类型**: 前端
**关联项目**: moxton-lotadmin

---

## 需求描述

对接后端操作历史接口，在订单详情页展示订单操作历史记录。

---

## 修改文件

### 1. API 接口定义

**文件**: `E:\moxton-lotadmin\src\service\api\order.ts`

添加获取操作历史的 API 方法：

```typescript
export function fetchOrderHistory(id: string) {
  return request<OrderHistory[]>({
    url: `/orders/admin/${id}/history`,
    method: 'get'
  });
}
```

**类型定义** (添加到 `src\service\api\order.ts` 或单独的类型文件):
```typescript
export interface OrderHistory {
  id: string;
  orderId: string;
  action: 'CREATED' | 'PAID' | 'CONFIRMED' | 'SHIPPED' | 'DELIVERED' | 'CANCELLED';
  operator?: {
    id: string;
    username: string;
    nickname: string;
  };
  notes?: string;
  metadata?: string;
  createdAt: string;
}
```

---

### 2. 操作历史组件实现

**文件**: `E:\moxton-lotadmin\src\views\online-order\modules\online-order-history.vue`

**当前状态**: 组件已创建，但使用空数据。

**修改要求**:

1. 添加 props 接收订单 ID:
```typescript
const props = defineProps<{
  orderId: string;
}>();
```

2. 添加获取历史数据的方法:
```typescript
const historyData = ref<OrderHistory[]>([]);
const loading = ref(false);

const fetchHistory = async () => {
  if (!props.orderId) return;
  loading.value = true;
  try {
    const data = await onlineOrderService.fetchOrderHistory(props.orderId);
    historyData.value = data;
  } catch (error) {
    // 错误由 axios 层统一处理
  } finally {
    loading.value = false;
  }
};

watch(() => props.orderId, fetchHistory, { immediate: true });
```

3. 添加操作类型映射:
```typescript
const actionMap: Record<string, string> = {
  CREATED: '创建订单',
  PAID: '支付成功',
  CONFIRMED: '订单确认',
  SHIPPED: '已发货',
  DELIVERED: '确认收货',
  CANCELLED: '取消订单'
};
```

4. 更新模板使用真实数据:
```vue
<NTimeline>
  <NTimelineItem
    v-for="item in historyData"
    :key="item.id"
    :type="getActionType(item.action)"
  >
    <template #header>
      {{ actionMap[item.action] || item.action }}
    </template>
    <div class="history-meta">
      <span>{{ item.operator?.nickname || '系统' }}</span>
      <span>{{ formatTime(item.createdAt) }}</span>
    </div>
    <div v-if="item.notes" class="history-notes">{{ item.notes }}</div>
  </NTimelineItem>
</NTimeline>
```

---

### 3. 详情页集成

**文件**: `E:\moxton-lotadmin\src\views\online-order\modules\online-order-detail.vue`

**确保**: 操作历史组件正确接收 `orderId` prop。

---

## 验收标准

1. ✅ API 接口正确调用后端 `GET /orders/admin/:id/history`
2. ✅ 操作历史按时间倒序展示
3. ✅ 显示操作人、操作时间、操作类型
4. ✅ 备注信息正确显示
5. ✅ 操作类型有对应的中文标签

---

## UI 示意

```
┌─────────────────────────────────────┐
│ 操作历史                              │
├─────────────────────────────────────┤
│ ● 确认收货                            │
│   管理员 · 2025-02-09 15:30          │
│                                     │
│ ● 已发货                              │
│   管理员 · 2025-02-09 10:20          │
│   顺丰速运 SF1234567890              │
│                                     │
│ ● 订单确认                            │
│   系统 · 2025-02-09 09:15            │
│                                     │
│ ● 支付成功                            │
│   系统 · 2025-02-09 09:10            │
└─────────────────────────────────────┘
```

---

## 依赖

此任务依赖于 **BACKEND-002** (订单操作历史功能) 完成。
