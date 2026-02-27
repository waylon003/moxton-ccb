# ADMIN-FE-001: 在线订单管理页面实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**创建时间:** 2026-02-08
**完成时间:** 2026-02-08
**状态:** 已完成
**角色:** CRUD前端工程师 (ADMIN-FE)
**项目:** moxton-lotadmin
**优先级:** P0
**技术栈:** Vue 3 + TypeScript + SoybeanAdmin + Naive UI

---

## 概述

### 问题陈述

moxton-lotadmin 后台管理系统缺少在线订单的管理界面。后端 API 已完成（位于 moxton-lotapi 项目的 `/orders/admin` 路由），需要前端开发对应的管理页面。

### 解决方案

参考 `consultation-order`（咨询订单）页面的实现风格，创建在线订单管理页面，包括订单列表、搜索筛选、订单详情、发货管理、状态更新等功能。

### 范围 (包含/排除)

**包含:**
- 订单列表展示（支持分页、筛选、排序）
- 订单搜索（订单号、客户信息、状态、日期范围）
- 订单详情查看（客户信息、收货地址、商品列表、支付信息）
- 订单操作（发货、确认收货、更新状态、取消订单）
- 订单操作历史记录
- 响应式布局（支持移动端）

**不包含:**
- 订单创建（由商城前端完成）
- 订单退款功能（后续单独开发）
- 订单导出功能（后续扩展）

---

## 开发上下文

### 现有实现

**参考页面:**
- `E:\moxton-lotadmin\src\views\consultation-order\` - 咨询订单页面（完整参考实现）

**后端 API:**
- `E:\moxton-lotapi\src\routes\orders.ts` - 在线订单路由定义
- `E:\moxton-lotapi\src\controllers\Order.ts` - 在线订单控制器

**现有前端 API 服务:**
- `E:\moxton-lotadmin\src\service\api\order.ts` - 需要修复并补充完整

### 依赖项

- Naive UI 组件库（已安装）
- `@vicons/tabler` 图标库（已安装）
- `useNaivePaginatedTable` hook（已实现）
- `TableHeaderOperation` 组件（已实现）

---

## 技术方案

### 页面结构

```
src/views/online-order/
├── index.vue                    # 主页面
├── types.ts                     # 类型定义
└── modules/
    ├── online-order-search.vue  # 搜索组件
    ├── online-order-detail.vue  # 详情抽屉
    ├── online-order-ship.vue    # 发货弹窗
    └── online-order-history.vue # 操作历史
```

### API 端点映射

| 功能 | 方法 | 端点 | 说明 |
|------|------|------|------|
| 获取订单列表 | GET | `/orders/admin` | 支持分页、筛选 |
| 获取订单详情 | GET | `/orders/admin/:id` | 完整订单信息 |
| 发货 | PUT | `/orders/admin/:id/ship` | 更新物流单号 |
| 确认收货 | PUT | `/orders/admin/:id/deliver` | 标记已送达 |
| 更新状态 | PUT | `/orders/admin/:id/status` | 修改订单状态 |
| 取消订单 | PUT | `/:id/cancel` | 取消订单 |
| 订单统计 | GET | `/orders/admin/stats/all` | 统计数据 |

### 订单状态映射

```typescript
const statusMap = {
  PENDING: { text: '待付款', type: 'warning' },
  PAID: { text: '已付款', type: 'info' },
  CONFIRMED: { text: '已确认', type: 'primary' },
  SHIPPED: { text: '已发货', type: 'info' },
  DELIVERED: { text: '已完成', type: 'success' },
  CANCELLED: { text: '已取消', type: 'error' }
};
```

---

## 实施步骤

### Task 1: 修复并完善在线订单 API 服务

**文件:**
- 修改: `E:\moxton-lotadmin\src\service\api\order.ts`

**Step 1: 备份现有文件并重写 API 服务**

当前 `order.ts` 使用的端点 `/admin/orders` 不正确，需要修复为 `/orders/admin`。

```typescript
// E:\moxton-lotadmin\src\service\api\order.ts

import { request } from '../request';

// 订单相关类型定义
export type OrderStatus = 'PENDING' | 'PAID' | 'CONFIRMED' | 'SHIPPED' | 'DELIVERED' | 'CANCELLED';

export interface OnlineOrder {
  id: string;
  orderNumber: string;
  userId: string | null;
  guestId: string | null;
  user?: {
    id: string;
    username: string;
    email: string;
  };
  items: OnlineOrderItem[];
  totalAmount: number;
  discountAmount: number;
  finalAmount: number;
  status: OrderStatus;
  paymentStatus: 'PENDING' | 'COMPLETED' | 'FAILED' | 'REFUNDED';
  paymentMethod?: string;
  shippingAddress: {
    recipientName: string;
    phone: string;
    street: string;
    city: string;
    state: string;
    zipCode: string;
    country: string;
  };
  trackingNumber?: string;
  notes?: string;
  createdAt: string;
  updatedAt: string;
  shippedAt?: string;
  deliveredAt?: string;
}

export interface OnlineOrderItem {
  id: string;
  productId: string;
  product?: {
    id: string;
    name: string;
    images: string[];
    price: number;
  };
  quantity: number;
  unitPrice: number;
  totalPrice: number;
  specifications?: Record<string, any>;
}

export interface OnlineOrderListParams {
  pageNum?: number;
  pageSize?: number;
  status?: OrderStatus;
  userId?: string;
  keyword?: string;
  startDate?: string;
  endDate?: string;
}

export interface UpdateOrderStatusData {
  status: OrderStatus;
  notes?: string;
}

export interface ShipOrderData {
  trackingNumber: string;
  notes?: string;
}

export interface PaginatedOnlineOrderResponse {
  list: OnlineOrder[];
  total: number;
  pageNum: number;
  pageSize: number;
  totalPages: number;
}

namespace ApiOnlineOrder {
  /** 获取在线订单列表（管理员） */
  export function fetchGetOnlineOrders(params?: OnlineOrderListParams) {
    return request<PaginatedOnlineOrderResponse>({
      url: '/orders/admin',
      method: 'get',
      params
    });
  }

  /** 获取在线订单详情 */
  export function fetchGetOnlineOrder(id: string) {
    return request<OnlineOrder>({
      url: `/orders/admin/${id}`,
      method: 'get'
    });
  }

  /** 更新订单状态 */
  export function fetchUpdateOrderStatus(id: string, data: UpdateOrderStatusData) {
    return request<OnlineOrder>({
      url: `/orders/admin/${id}/status`,
      method: 'put',
      data
    });
  }

  /** 发货 */
  export function fetchShipOrder(id: string, data: ShipOrderData) {
    return request<OnlineOrder>({
      url: `/orders/admin/${id}/ship`,
      method: 'put',
      data
    });
  }

  /** 确认收货 */
  export function fetchConfirmDelivery(id: string) {
    return request<OnlineOrder>({
      url: `/orders/admin/${id}/deliver`,
      method: 'put'
    });
  }

  /** 取消订单 */
  export function fetchCancelOrder(id: string, reason: string) {
    return request<OnlineOrder>({
      url: `/orders/${id}/cancel`,
      method: 'put',
      data: { reason }
    });
  }

  /** 获取订单统计数据 */
  export function fetchGetOnlineOrderStats() {
    return request<{
      totalOrders: number;
      totalRevenue: number;
      statusDistribution: Array<{
        status: OrderStatus;
        count: number;
        amount: number;
      }>;
    }>({
      url: '/orders/admin/stats/all',
      method: 'get'
    });
  }
}

export { ApiOnlineOrder as onlineOrderService };
```

**Step 2: 运行类型检查验证**

Run: `cd E:\moxton-lotadmin && npm run type-check`
Expected: No TypeScript errors

**Step 3: Commit**

```bash
git add src/service/api/order.ts
git commit -m "fix(online-order): 修复在线订单 API 端点路径"
```

---

### Task 2: 创建在线订单类型定义文件

**文件:**
- 创建: `E:\moxton-lotadmin\src\views\online-order\types.ts`

**Step 1: 创建类型定义文件**

```typescript
// E:\moxton-lotadmin\src\views\online-order\types.ts

import type { OnlineOrder, OrderStatus, OnlineOrderListParams } from '@/service/api/order';

/** 导出在线订单类型 */
export type { OnlineOrder, OrderStatus, OnlineOrderListParams };

/** 在线订单列表查询参数（扩展） */
export interface OnlineOrderListQuery extends OnlineOrderListParams {
  pageNum: number;
  pageSize: number;
}

/** 在线订单统计数据 */
export interface OnlineOrderStats {
  totalOrders: number;
  totalRevenue: number;
  pendingOrders: number;
  shippedOrders: number;
  deliveredOrders: number;
  cancelledOrders: number;
  statusDistribution: Array<{
    status: OrderStatus;
    count: number;
    amount: number;
  }>;
}
```

**Step 2: Commit**

```bash
git add src/views/online-order/types.ts
git commit -m "feat(online-order): 添加在线订单类型定义"
```

---

### Task 3: 创建在线订单搜索组件

**文件:**
- 创建: `E:\moxton-lotadmin\src\views\online-order\modules\online-order-search.vue`

**Step 1: 创建搜索组件**

```vue
<!-- E:\moxton-lotadmin\src\views\online-order\modules\online-order-search.vue -->
<script setup lang="ts">
import { computed, ref } from 'vue';
import { NButton, NCard, NGi, NGrid, NIcon, NInput, NSelect, NDatePicker } from 'naive-ui';
import { Refresh, Search } from '@vicons/tabler';
import type { OnlineOrderListQuery } from '../types';

interface Props {
  loading?: boolean;
}

interface Emits {
  (e: 'search', params: Partial<OnlineOrderListQuery>): void;
  (e: 'reset'): void;
}

const props = withDefaults(defineProps<Props>(), {
  loading: false
});

const emit = defineEmits<Emits>();

// 搜索表单
const searchForm = ref<Partial<OnlineOrderListQuery>>({
  keyword: '',
  status: undefined,
  userId: '',
  startDate: undefined,
  endDate: undefined
});

// 日期范围
const dateRange = ref<[number, number] | null>(null);

// 计算属性：是否有搜索条件
const hasSearchConditions = computed(() => {
  return Boolean(
    searchForm.value.keyword ||
      searchForm.value.status !== undefined ||
      searchForm.value.userId ||
      dateRange.value
  );
});

// 状态选项
const statusOptions = [
  { label: '全部状态', value: undefined },
  { label: '待付款', value: 'PENDING' },
  { label: '已付款', value: 'PAID' },
  { label: '已确认', value: 'CONFIRMED' },
  { label: '已发货', value: 'SHIPPED' },
  { label: '已完成', value: 'DELIVERED' },
  { label: '已取消', value: 'CANCELLED' }
];

// 用户类型选项
const userTypeOptions = [
  { label: '全部用户', value: '' },
  { label: '注册用户', value: 'registered' },
  { label: '游客订单', value: 'guest' }
];

// 搜索
const handleSearch = () => {
  // 处理日期范围
  let startDate: string | undefined;
  let endDate: string | undefined;

  if (dateRange.value && dateRange.value.length === 2) {
    startDate = new Date(dateRange.value[0]).toISOString();
    endDate = new Date(dateRange.value[1]).toISOString();
  }

  emit('search', {
    ...searchForm.value,
    startDate,
    endDate
  });
};

// 重置
const handleReset = () => {
  searchForm.value = {
    keyword: '',
    status: undefined,
    userId: '',
    startDate: undefined,
    endDate: undefined
  };
  dateRange.value = null;
  emit('reset');
};

// 回车搜索
const handleKeyPress = (e: KeyboardEvent) => {
  if (e.key === 'Enter') {
    handleSearch();
  }
};

// 用户类型筛选处理
const handleUserTypeFilter = (type: string) => {
  if (type === 'guest') {
    searchForm.value.userId = 'null';
  } else if (type === 'registered') {
    searchForm.value.userId = 'not-null';
  } else {
    searchForm.value.userId = '';
  }
};

// 日期范围变化处理
const handleDateRangeChange = (value: [number, number] | null) => {
  dateRange.value = value;
};
</script>

<template>
  <NCard :bordered="false" class="online-order-search-card">
    <NGrid cols="1 s:2 m:3 l:4" responsive="screen" :x-gap="16" :y-gap="16">
      <NGi>
        <NInput
          v-model:value="searchForm.keyword"
          placeholder="搜索订单号、收货人、电话、地址"
          clearable
          @keypress="handleKeyPress"
        >
          <template #prefix>
            <NIcon :component="Search" />
          </template>
        </NInput>
      </NGi>

      <NGi>
        <NSelect v-model:value="searchForm.status" :options="statusOptions" placeholder="订单状态" clearable />
      </NGi>

      <NGi>
        <NSelect
          :value="searchForm.userId === 'null' ? 'guest' : searchForm.userId === 'not-null' ? 'registered' : ''"
          :options="userTypeOptions"
          placeholder="订单类型"
          clearable
          @update:value="handleUserTypeFilter"
        />
      </NGi>

      <NGi>
        <NDatePicker
          v-model:value="dateRange"
          type="daterange"
          clearable
          placeholder="选择日期范围"
          @update:value="handleDateRangeChange"
        />
      </NGi>
    </NGrid>

    <!-- 搜索按钮行 -->
    <div class="search-actions-row">
      <div></div>
      <div class="search-actions">
        <NButton type="primary" :loading="loading" @click="handleSearch">
          <template #icon>
            <NIcon :component="Search" />
          </template>
          搜索
        </NButton>

        <NButton v-if="hasSearchConditions" quaternary @click="handleReset">
          <template #icon>
            <NIcon :component="Refresh" />
          </template>
          重置
        </NButton>
      </div>
    </div>
  </NCard>
</template>

<style scoped>
.online-order-search-card {
  margin-bottom: 16px;
}

.search-actions-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-top: 16px;
}

.search-actions {
  display: flex;
  gap: 8px;
  align-items: center;
}

@media (max-width: 768px) {
  .search-actions-row {
    flex-direction: column;
    align-items: stretch;
    gap: 12px;
  }

  .search-actions {
    justify-content: center;
  }
}
</style>
```

**Step 2: Commit**

```bash
git add src/views/online-order/modules/online-order-search.vue
git commit -m "feat(online-order): 添加在线订单搜索组件"
```

---

### Task 4: 创建在线订单发货弹窗组件

**文件:**
- 创建: `E:\moxton-lotadmin\src\views\online-order\modules\online-order-ship.vue`

**Step 1: 创建发货弹窗组件**

```vue
<!-- E:\moxton-lotadmin\src\views\online-order\modules\online-order-ship.vue -->
<script setup lang="ts">
import { ref, watch } from 'vue';
import { NButton, NForm, NFormItem, NInput, NModal, NSpace } from 'naive-ui';
import { onlineOrderService } from '@/service/api/order';

interface Props {
  visible: boolean;
  orderId: string | null;
}

interface Emits {
  (e: 'update:visible', value: boolean): void;
  (e: 'success'): void;
}

const props = defineProps<Props>();
const emit = defineEmits<Emits>();

const formRef = ref();
const loading = ref(false);

// 表单数据
const formData = ref({
  trackingNumber: '',
  notes: ''
});

// 表单验证规则
const rules = {
  trackingNumber: {
    required: true,
    message: '请输入物流单号',
    trigger: 'blur'
  }
};

// 监听 visible 变化，重置表单
watch(
  () => props.visible,
  (val) => {
    if (!val) {
      formData.value = {
        trackingNumber: '',
        notes: ''
      };
      formRef.value?.restoreValidation();
    }
  }
);

// 处理确认发货
const handleConfirm = async () => {
  if (!props.orderId) return;

  try {
    await formRef.value?.validate();
    loading.value = true;

    await onlineOrderService.fetchShipOrder(props.orderId, {
      trackingNumber: formData.value.trackingNumber,
      notes: formData.value.notes
    });

    emit('success');
    emit('update:visible', false);
  } catch (error) {
    // API 错误由 axios 层统一处理
  } finally {
    loading.value = false;
  }
};

// 处理取消
const handleCancel = () => {
  emit('update:visible', false);
};
</script>

<template>
  <NModal
    :show="visible"
    :mask-closable="false"
    preset="card"
    title="订单发货"
    style="width: 500px"
    @update:show="handleCancel"
  >
    <NForm ref="formRef" :model="formData" :rules="rules" label-placement="left" label-width="100px">
      <NFormItem label="物流单号" path="trackingNumber">
        <NInput v-model:value="formData.trackingNumber" placeholder="请输入物流单号" />
      </NFormItem>

      <NFormItem label="备注" path="notes">
        <NInput
          v-model:value="formData.notes"
          type="textarea"
          placeholder="选填：发货备注信息"
          :autosize="{ minRows: 3, maxRows: 5 }"
        />
      </NFormItem>
    </NForm>

    <template #footer>
      <NSpace justify="end">
        <NButton @click="handleCancel">取消</NButton>
        <NButton type="primary" :loading="loading" @click="handleConfirm">确认发货</NButton>
      </NSpace>
    </template>
  </NModal>
</template>
```

**Step 2: Commit**

```bash
git add src/views/online-order/modules/online-order-ship.vue
git commit -m "feat(online-order): 添加在线订单发货弹窗组件"
```

---

### Task 5: 创建在线订单详情抽屉组件

**文件:**
- 创建: `E:\moxton-lotadmin\src\views\online-order\modules\online-order-detail.vue`

**Step 1: 创建详情抽屉组件**

```vue
<!-- E:\moxton-lotadmin\src\views\online-order\modules\online-order-detail.vue -->
<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import {
  NButton,
  NCard,
  NDescriptions,
  NDescriptionsItem,
  NDrawer,
  NDrawerContent,
  NEmpty,
  NIcon,
  NImage,
  NSpace,
  NTag,
  NTooltip
} from 'naive-ui';
import { Package, Truck, CheckCircle, XCircle } from '@vicons/tabler';
import { onlineOrderService } from '@/service/api/order';
import type { OnlineOrder } from '@/service/api/order';
import OnlineOrderShip from './online-order-ship.vue';

interface Props {
  visible: boolean;
  orderId: string | null;
}

interface Emits {
  (e: 'update:visible', value: boolean): void;
  (e: 'success'): void;
}

const props = defineProps<Props>();
const emit = defineEmits<Emits>();

const loading = ref(false);
const order = ref<OnlineOrder | null>(null);
const shipModalVisible = ref(false);

// 状态映射
const statusMap = {
  PENDING: { text: '待付款', type: 'warning' },
  PAID: { text: '已付款', type: 'info' },
  CONFIRMED: { text: '已确认', type: 'primary' },
  SHIPPED: { text: '已发货', type: 'info' },
  DELIVERED: { text: '已完成', type: 'success' },
  CANCELLED: { text: '已取消', type: 'error' }
};

// 支付状态映射
const paymentStatusMap = {
  PENDING: { text: '待支付', type: 'warning' },
  COMPLETED: { text: '已支付', type: 'success' },
  FAILED: { text: '支付失败', type: 'error' },
  REFUNDED: { text: '已退款', type: 'info' }
};

// 获取订单详情
const fetchOrderDetail = async () => {
  if (!props.orderId) return;

  try {
    loading.value = true;
    const result = await onlineOrderService.fetchGetOnlineOrder(props.orderId);
    order.value = result.data;
  } catch (error) {
    // API 错误由 axios 层统一处理
  } finally {
    loading.value = false;
  }
};

// 监听 visible 变化
watch(
  () => props.visible,
  (val) => {
    if (val && props.orderId) {
      fetchOrderDetail();
    } else {
      order.value = null;
    }
  }
);

// 处理发货
const handleShip = () => {
  shipModalVisible.value = true;
};

// 处理确认收货
const handleConfirmDelivery = async () => {
  if (!props.orderId) return;

  try {
    await onlineOrderService.fetchConfirmDelivery(props.orderId);
    emit('success');
    fetchOrderDetail();
  } catch (error) {
    // API 错误由 axios 层统一处理
  }
};

// 处理取消订单
const handleCancelOrder = async () => {
  if (!props.orderId) return;

  try {
    await onlineOrderService.fetchCancelOrder(props.orderId, '管理员取消');
    emit('success');
    fetchOrderDetail();
  } catch (error) {
    // API 错误由 axios 层统一处理
  }
};

// 发货成功回调
const handleShipSuccess = () => {
  emit('success');
  fetchOrderDetail();
};

// 关闭抽屉
const handleClose = () => {
  emit('update:visible', false);
};

// 计算是否可以发货
const canShip = computed(() => {
  return order.value && (order.value.status === 'PAID' || order.value.status === 'CONFIRMED');
});

// 计算是否可以确认收货
const canConfirmDelivery = computed(() => {
  return order.value && order.value.status === 'SHIPPED';
});

// 计算是否可以取消
const canCancel = computed(() => {
  return order.value && (order.value.status === 'PENDING' || order.value.status === 'PAID');
});
</script>

<template>
  <NDrawer :show="visible" :width="800" placement="right" @update:show="handleClose">
    <NDrawerContent :native-scrollbar="false" closable>
      <template #header>
        <div class="drawer-header">
          <span>订单详情</span>
          <NTag v-if="order" :type="statusMap[order.status].type as any" size="small">
            {{ statusMap[order.status].text }}
          </NTag>
        </div>
      </template>

      <div v-if="loading" class="loading-container">
        <NSpin size="large" />
      </div>

      <div v-else-if="!order" class="empty-container">
        <NEmpty description="订单信息不存在" />
      </div>

      <div v-else class="order-detail-container">
        <!-- 订单基本信息 -->
        <NCard title="订单信息" size="small" :bordered="false">
          <NDescriptions label-placement="left" :column="2">
            <NDescriptionsItem label="订单号">{{ order.orderNumber }}</NDescriptionsItem>
            <NDescriptionsItem label="订单状态">
              <NTag :type="statusMap[order.status].type as any" size="small">
                {{ statusMap[order.status].text }}
              </NTag>
            </NDescriptionsItem>
            <NDescriptionsItem label="支付状态">
              <NTag :type="paymentStatusMap[order.paymentStatus].type as any" size="small">
                {{ paymentStatusMap[order.paymentStatus].text }}
              </NTag>
            </NDescriptionsItem>
            <NDescriptionsItem label="支付方式">{{ order.paymentMethod || '-' }}</NDescriptionsItem>
            <NDescriptionsItem label="商品总额">¥{{ order.totalAmount.toFixed(2) }}</NDescriptionsItem>
            <NDescriptionsItem label="优惠金额">¥{{ order.discountAmount.toFixed(2) }}</NDescriptionsItem>
            <NDescriptionsItem label="订单总额">
              <span class="text-lg font-bold text-primary">¥{{ order.finalAmount.toFixed(2) }}</span>
            </NDescriptionsItem>
            <NDescriptionsItem label="创建时间">
              {{ new Date(order.createdAt).toLocaleString('zh-CN') }}
            </NDescriptionsItem>
          </NDescriptions>
        </NCard>

        <!-- 客户信息 -->
        <NCard title="客户信息" size="small" :bordered="false">
          <NDescriptions label-placement="left" :column="2">
            <NDescriptionsItem label="客户类型">
              { order.user ? '注册用户' : '游客订单' }
            </NDescriptionsItem>
            <NDescriptionsItem v-if="order.user" label="用户ID">{{ order.user.id }}</NDescriptionsItem>
            <NDescriptionsItem v-if="order.user" label="用户名">{{ order.user.username }}</NDescriptionsItem>
            <NDescriptionsItem v-if="order.user" label="邮箱">{{ order.user.email }}</NDescriptionsItem>
          </NDescriptions>
        </NCard>

        <!-- 收货地址 -->
        <NCard title="收货地址" size="small" :bordered="false">
          <NDescriptions label-placement="left" :column="1">
            <NDescriptionsItem label="收货人">{{ order.shippingAddress.recipientName }}</NDescriptionsItem>
            <NDescriptionsItem label="联系电话">{{ order.shippingAddress.phone }}</NDescriptionsItem>
            <NDescriptionsItem label="详细地址">
              {{ order.shippingAddress.country }} {{ order.shippingAddress.state }}
              {{ order.shippingAddress.city }} {{ order.shippingAddress.street }}
              {{ order.shippingAddress.zipCode }}
            </NDescriptionsItem>
          </NDescriptions>
        </NCard>

        <!-- 商品信息 -->
        <NCard title="商品信息" size="small" :bordered="false">
          <div class="order-items">
            <div v-for="item in order.items" :key="item.id" class="order-item">
              <NImage
                v-if="item.product?.images?.[0]"
                :src="item.product.images[0]"
                :width="80"
                :height="80"
                object-fit="cover"
              />
              <div v-else class="no-image">
                <NIcon :component="Package" :size="40" />
              </div>
              <div class="item-info">
                <div class="item-name">{{ item.product?.name || '商品已删除' }}</div>
                <div class="item-specs">
                  单价: ¥{{ item.unitPrice.toFixed(2) }} × {{ item.quantity }}
                </div>
              </div>
              <div class="item-total">¥{{ item.totalPrice.toFixed(2) }}</div>
            </div>
          </div>
        </NCard>

        <!-- 物流信息 -->
        <NCard v-if="order.trackingNumber" title="物流信息" size="small" :bordered="false">
          <NDescriptions label-placement="left" :column="1">
            <NDescriptionsItem label="物流单号">{{ order.trackingNumber }}</NDescriptionsItem>
            <NDescriptionsItem v-if="order.shippedAt" label="发货时间">
              {{ new Date(order.shippedAt).toLocaleString('zh-CN') }}
            </NDescriptionsItem>
            <NDescriptionsItem v-if="order.deliveredAt" label="收货时间">
              {{ new Date(order.deliveredAt).toLocaleString('zh-CN') }}
            </NDescriptionsItem>
          </NDescriptions>
        </NCard>

        <!-- 备注 -->
        <NCard v-if="order.notes" title="备注" size="small" :bordered="false">
          <div class="notes">{{ order.notes }}</div>
        </NCard>
      </div>

      <!-- 操作按钮 -->
      <template #footer>
        <NSpace justify="end">
          <NButton v-if="canShip" type="primary" @click="handleShip">
            <template #icon>
              <NIcon :component="Truck" />
            </template>
            发货
          </NButton>
          <NButton v-if="canConfirmDelivery" type="success" @click="handleConfirmDelivery">
            <template #icon>
              <NIcon :component="CheckCircle" />
            </template>
            确认收货
          </NButton>
          <NButton v-if="canCancel" type="error" @click="handleCancelOrder">
            <template #icon>
              <NIcon :component="XCircle" />
            </template>
            取消订单
          </NButton>
        </NSpace>
      </template>
    </NDrawerContent>

    <!-- 发货弹窗 -->
    <OnlineOrderShip v-model:visible="shipModalVisible" :order-id="orderId" @success="handleShipSuccess" />
  </NDrawer>
</template>

<style scoped>
.drawer-header {
  display: flex;
  align-items: center;
  gap: 12px;
}

.loading-container,
.empty-container {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 400px;
}

.order-detail-container {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.order-items {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.order-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px;
  border-radius: 8px;
  background-color: var(--n-color-modal);
}

.no-image {
  width: 80px;
  height: 80px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 6px;
  background-color: var(--n-color-embedded);
  color: var(--n-color-embedded-modal);
}

.item-info {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.item-name {
  font-weight: 500;
}

.item-specs {
  font-size: 12px;
  color: var(--n-text-color-2);
}

.item-total {
  font-weight: 600;
  font-size: 16px;
}

.notes {
  white-space: pre-wrap;
  word-break: break-word;
}
</style>
```

**Step 2: Commit**

```bash
git add src/views/online-order/modules/online-order-detail.vue
git commit -m "feat(online-order): 添加在线订单详情抽屉组件"
```

---

### Task 6: 创建在线订单历史记录组件

**文件:**
- 创建: `E:\moxton-lotadmin\src\views\online-order\modules\online-order-history.vue`

**Step 1: 创建历史记录组件**

```vue
<!-- E:\moxton-lotadmin\src\views\online-order\modules\online-order-history.vue -->
<script setup lang="ts">
import { ref, watch } from 'vue';
import { NButton, NCard, NEmpty, NSpin, NTag, NTimeline, NTimelineItem } from 'naive-ui';
import { History } from '@vicons/tabler';

interface Props {
  visible: boolean;
  orderId: string | null;
}

interface Emits {
  (e: 'update:visible', value: boolean): void;
}

const props = defineProps<Props>();
const emit = defineEmits<Emits>();

const loading = ref(false);
const history = ref<any[]>([]);

// 监听 visible 变化
watch(
  () => props.visible,
  async (val) => {
    if (val && props.orderId) {
      // 暂时使用空数据，等待后端提供历史记录接口
      history.value = [];
    }
  }
);

// 关闭弹窗
const handleClose = () => {
  emit('update:visible', false);
};
</script>

<template>
  <NCard
    :bordered="false"
    style="width: 600px; max-height: 80vh; overflow-y: auto"
    @update:show="handleClose"
  >
    <template #header>
      <div class="history-header">
        <NIcon :component="History" />
        <span>操作历史</span>
      </div>
    </template>

    <div v-if="loading" class="loading-container">
      <NSpin size="large" />
    </div>

    <div v-else-if="history.length === 0" class="empty-container">
      <NEmpty description="暂无操作记录" />
    </div>

    <NTimeline v-else>
      <NTimelineItem
        v-for="item in history"
        :key="item.id"
        :type="item.type"
        :title="item.title"
        :time="new Date(item.createdAt).toLocaleString('zh-CN')"
      >
        <template #header>
          <div class="history-item-header">
            <span>{{ item.title }}</span>
            <NTag v-if="item.status" :type="item.statusType" size="small">
              {{ item.status }}
            </NTag>
          </div>
        </template>
        <div v-if="item.description" class="history-description">{{ item.description }}</div>
        <div v-if="item.adminName" class="history-admin">操作人: {{ item.adminName }}</div>
      </NTimelineItem>
    </NTimeline>

    <template #footer>
      <div class="history-footer">
        <NButton @click="handleClose">关闭</NButton>
      </div>
    </template>
  </NCard>
</template>

<style scoped>
.history-header {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 16px;
  font-weight: 500;
}

.loading-container,
.empty-container {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 200px;
}

.history-item-header {
  display: flex;
  align-items: center;
  gap: 8px;
}

.history-description {
  margin-top: 4px;
  color: var(--n-text-color-2);
}

.history-admin {
  margin-top: 4px;
  font-size: 12px;
  color: var(--n-text-color-3);
}

.history-footer {
  display: flex;
  justify-content: flex-end;
}
</style>
```

**Step 2: Commit**

```bash
git add src/views/online-order/modules/online-order-history.vue
git commit -m "feat(online-order): 添加在线订单历史记录组件"
```

---

### Task 7: 创建在线订单主页面

**文件:**
- 创建: `E:\moxton-lotadmin\src\views\online-order\index.vue`

**Step 1: 创建主页面文件**

```vue
<!-- E:\moxton-lotadmin\src\views\online-order\index.vue -->
<script setup lang="ts">
import { computed, h, onMounted, ref } from 'vue';
import {
  NButton,
  NCard,
  NDataTable,
  NIcon,
  NPopconfirm,
  NSpace,
  NTag,
  NTooltip,
  useDialog,
  useMessage
} from 'naive-ui';
import { Eye, History, Refresh, Trash, Truck, XCircle } from '@vicons/tabler';
import { onlineOrderService } from '@/service/api/order';
import { useNaivePaginatedTable } from '@/hooks/common/table';
import TableHeaderOperation from '@/components/advanced/table-header-operation.vue';
import type { OnlineOrder } from '@/service/api/order';
import type { OnlineOrderListQuery } from './types';
import OnlineOrderSearch from './modules/online-order-search.vue';
import OnlineOrderDetail from './modules/online-order-detail.vue';
import OnlineOrderHistory from './modules/online-order-history.vue';

defineOptions({
  name: 'OnlineOrder'
});

const message = useMessage();
const dialog = useDialog();

// 批量操作选择
const checkedRowKeys = ref<string[]>([]);

// 状态管理
const formLoading = ref(false);

// 详情和历史弹窗状态
const detailDrawerVisible = ref(false);
const historyModalVisible = ref(false);
const selectedOrderId = ref<string | null>(null);

// 状态映射
const statusMap = {
  PENDING: { text: '待付款', type: 'warning' },
  PAID: { text: '已付款', type: 'info' },
  CONFIRMED: { text: '已确认', type: 'primary' },
  SHIPPED: { text: '已发货', type: 'info' },
  DELIVERED: { text: '已完成', type: 'success' },
  CANCELLED: { text: '已取消', type: 'error' }
} as const;

// 搜索处理
const handleSearch = async (params: Partial<OnlineOrderListQuery>) => {
  Object.assign(searchParams.value, params);
  searchParams.value.pageNum = 1;
  await getDataByPage();
};

// 重置搜索
const handleReset = async () => {
  searchParams.value = {
    pageNum: 1,
    pageSize: 10,
    status: undefined,
    keyword: '',
    userId: '',
    startDate: undefined,
    endDate: undefined
  };
  await getDataByPage();
};

// 表格列定义
const tableColumns = computed(() => [
  {
    type: 'selection',
    fixed: 'left' as const
  },
  {
    title: '订单号',
    key: 'orderNumber',
    width: 180,
    ellipsis: {
      tooltip: true
    }
  },
  {
    title: '商品信息',
    key: 'items',
    width: 280,
    render(row: OnlineOrder) {
      const firstItem = row.items?.[0];
      if (!firstItem) {
        return h('span', { class: 'text-gray-400' }, '无商品');
      }

      const itemCount = row.items.length;
      const product = firstItem.product;

      return h(
        'div',
        {
          class: 'flex items-center space-x-2'
        },
        [
          product?.images && product.images.length > 0
            ? h('img', {
                src: product.images[0],
                style: {
                  width: '60px',
                  height: '60px',
                  borderRadius: '4px',
                  objectFit: 'cover'
                }
              })
            : null,
          h(
            'div',
            {
              class: 'flex-1',
              style: { minWidth: 0 }
            },
            [
              h(
                'div',
                {
                  class: 'text-sm font-medium truncate'
                },
                product?.name || '商品已删除'
              ),
              h(
                'div',
                {
                  class: 'text-xs text-gray-500'
                },
                itemCount > 1 ? `共 ${itemCount} 件商品` : `¥${firstItem.unitPrice.toFixed(2)}`
              )
            ]
          )
        ]
      );
    }
  },
  {
    title: '收货人',
    key: 'recipientName',
    width: 120,
    render(row: OnlineOrder) {
      return h('span', { class: 'font-medium' }, row.shippingAddress.recipientName);
    }
  },
  {
    title: '联系电话',
    key: 'phone',
    width: 140,
    render(row: OnlineOrder) {
      return h('span', { class: 'text-sm' }, row.shippingAddress.phone);
    }
  },
  {
    title: '订单金额',
    key: 'finalAmount',
    width: 120,
    render(row: OnlineOrder) {
      return h(
        'span',
        { class: 'font-bold text-primary' },
        `¥${row.finalAmount.toFixed(2)}`
      );
    }
  },
  {
    title: '订单类型',
    key: 'userType',
    width: 100,
    render(row: OnlineOrder) {
      return row.user
        ? h(NTag, { type: 'success', size: 'small' }, { default: () => '注册用户' })
        : h(NTag, { type: 'info', size: 'small' }, { default: () => '游客订单' });
    }
  },
  {
    title: '订单状态',
    key: 'status',
    width: 100,
    render(row: OnlineOrder) {
      const status = statusMap[row.status];
      return h(NTag, { type: status.type as any, size: 'small' }, { default: () => status.text });
    }
  },
  {
    title: '物流单号',
    key: 'trackingNumber',
    width: 160,
    ellipsis: {
      tooltip: true
    },
    render(row: OnlineOrder) {
      return row.trackingNumber || '-';
    }
  },
  {
    title: '创建时间',
    key: 'createdAt',
    width: 160,
    render(row: OnlineOrder) {
      return new Date(row.createdAt).toLocaleString('zh-CN');
    }
  },
  {
    title: '操作',
    key: 'actions',
    width: 200,
    fixed: 'right' as const,
    render(row: OnlineOrder) {
      return h(
        NSpace,
        { size: 8 },
        {
          default: () => [
            // 查看详情按钮
            h(
              NTooltip,
              {},
              {
                trigger: () =>
                  h(
                    NButton,
                    {
                      size: 'small',
                      quaternary: true,
                      type: 'primary',
                      onClick: () => handleViewDetail(row.id)
                    },
                    () => h(NIcon, { component: Eye, size: 18 })
                  ),
                default: () => '查看订单详情'
              }
            ),
            // 查看历史按钮
            h(
              NTooltip,
              {},
              {
                trigger: () =>
                  h(
                    NButton,
                    {
                      size: 'small',
                      quaternary: true,
                      type: 'info',
                      onClick: () => handleViewHistory(row.id)
                    },
                    () => h(NIcon, { component: History, size: 18 })
                  ),
                default: () => '查看操作历史'
              }
            ),
            // 取消订单按钮
            ...(row.status === 'PENDING' || row.status === 'PAID'
              ? [
                  h(
                    NPopconfirm,
                    {
                      onPositiveClick: () => handleCancelOrder(row.id)
                    },
                    {
                      trigger: () =>
                        h(
                          NTooltip,
                          {},
                          {
                            trigger: () =>
                              h(
                                NButton,
                                {
                                  size: 'small',
                                  quaternary: true,
                                  type: 'warning'
                                },
                                () => h(NIcon, { component: XCircle, size: 18 })
                              ),
                            default: () => '取消订单'
                          }
                        ),
                      default: () => '确认取消此订单吗？'
                    }
                  )
                ]
              : [])
          ]
        }
      );
    }
  }
]);

// 搜索参数
const searchParams = ref<OnlineOrderListQuery>({
  pageNum: 1,
  pageSize: 10,
  status: undefined,
  keyword: '',
  userId: '',
  startDate: undefined,
  endDate: undefined
});

// 数据转换函数
const onlineOrderTransform = (response: any) => {
  const { data, error } = response;

  if (!error && data) {
    return {
      data: data.list || [],
      pageNum: data.pageNum || 1,
      pageSize: data.pageSize || 10,
      total: data.total || 0
    };
  }

  return {
    data: [],
    pageNum: 1,
    pageSize: 10,
    total: 0
  };
};

// 表格数据管理
const {
  loading,
  data: orders,
  columns,
  columnChecks,
  mobilePagination,
  getData,
  getDataByPage
} = useNaivePaginatedTable<any, OnlineOrder>({
  api: () => onlineOrderService.fetchGetOnlineOrders(searchParams.value),
  transform: onlineOrderTransform,
  columns: () => tableColumns.value as any,
  showTotal: true,
  paginationProps: {
    pageSizes: [10, 20, 50, 100]
  }
});

// 查看订单详情
const handleViewDetail = (orderId: string) => {
  selectedOrderId.value = orderId;
  detailDrawerVisible.value = true;
};

// 查看操作历史
const handleViewHistory = (orderId: string) => {
  selectedOrderId.value = orderId;
  historyModalVisible.value = true;
};

// 取消订单
const handleCancelOrder = async (id: string) => {
  try {
    await onlineOrderService.fetchCancelOrder(id, '管理员取消');
    getData();
  } catch (error) {
    // API 错误由 axios 层统一处理
  }
};

// 详情组件成功回调
const handleDetailSuccess = () => {
  getData();
};

// 初始化数据
onMounted(async () => {
  await getData();
});
</script>

<template>
  <div class="manage-online-order">
    <!-- 搜索区域 -->
    <OnlineOrderSearch @search="handleSearch" @reset="handleReset" />

    <!-- 主列表卡片 -->
    <NCard :bordered="false" class="main-card" title="在线订单管理" size="small">
      <!-- 卡片头部额外内容：工具栏 -->
      <template #header-extra>
        <TableHeaderOperation
          v-model:columns="columnChecks"
          :loading="loading"
          @refresh="getData"
        />
      </template>

      <!-- 表格 -->
      <NDataTable
        v-model:checked-row-keys="checkedRowKeys"
        :columns="tableColumns as any"
        :data="orders"
        :loading="loading"
        :scroll-x="2200"
        :flex-height="true"
        striped
        size="small"
        remote
        :row-key="(row: OnlineOrder) => row.id!"
        :pagination="mobilePagination"
      />
    </NCard>

    <!-- 订单详情抽屉 -->
    <OnlineOrderDetail
      v-model:visible="detailDrawerVisible"
      :order-id="selectedOrderId"
      @success="handleDetailSuccess"
    />

    <!-- 操作历史弹窗 -->
    <OnlineOrderHistory v-model:visible="historyModalVisible" :order-id="selectedOrderId" />
  </div>
</template>

<style scoped>
.manage-online-order {
  display: flex;
  flex-direction: column;
  height: 100%;
  padding: 16px;
  overflow: hidden;
}

.main-card {
  margin-top: 12px;
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

:deep(.main-card .n-card) {
  height: 100%;
  display: flex;
  flex-direction: column;
}

:deep(.main-card .n-card-header) {
  padding: 20px 20px 16px 20px;
}

:deep(.main-card .n-card__content) {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  padding: 20px;
}

:deep(.main-card .n-data-table) {
  flex: 1;
}

:deep(.n-data-table .n-data-table-th) {
  font-weight: 600;
}

:deep(.n-data-table .n-data-table-td) {
  vertical-align: middle;
}

:deep(.n-data-table-wrapper .n-pagination) {
  justify-content: center !important;
}

/* 移动端优化 */
@media (max-width: 768px) {
  .manage-online-order {
    padding: 8px;
  }

  .main-card {
    margin-top: 8px;
  }

  :deep(.n-data-table) {
    font-size: 12px;
  }

  :deep(.n-data-table .n-data-table-th) {
    padding: 8px 4px;
    font-size: 12px;
  }

  :deep(.n-data-table .n-data-table-td) {
    padding: 8px 4px;
    font-size: 12px;
  }

  :deep(.n-space) {
    flex-wrap: wrap;
  }
}

@media (max-width: 480px) {
  .manage-online-order {
    padding: 4px;
  }

  :deep(.n-data-table) {
    font-size: 11px;
  }

  :deep(.n-data-table .n-data-table-th) {
    padding: 6px 2px;
    font-size: 11px;
  }

  :deep(.n-data-table .n-data-table-td) {
    padding: 6px 2px;
    font-size: 11px;
  }

  :deep(.n-card-header) {
    padding: 12px 12px 8px 12px;
    flex-direction: column;
    align-items: flex-start;
    gap: 8px;
  }

  :deep(.n-card__content) {
    padding: 12px;
  }
}

@media (min-width: 769px) and (max-width: 1024px) {
  .manage-online-order {
    padding: 12px;
  }

  .main-card {
    margin-top: 10px;
  }
}
</style>
```

**Step 2: Commit**

```bash
git add src/views/online-order/index.vue
git commit -m "feat(online-order): 添加在线订单管理主页面"
```

---

### Task 8: 添加路由配置

**文件:**
- 修改: `E:\moxton-lotadmin\src\router\elegant\routes.ts`

**Step 1: 查看现有路由配置**

Run: `grep -n "consultation-order" E:\moxton-lotadmin\src\router\elegant\routes.ts`
Expected: 找到咨询订单的路由配置位置

**Step 2: 参考咨询订单路由，添加在线订单路由**

在 consultation-order 路由附近添加：

```typescript
// 在线订单管理
{
  key: 'online-order',
  name: '在线订单',
  route: 'OnlineOrder',
  path: '/online-order',
  component: 'self',
  i18nKey: 'route.online-order',
  icon: 'icon-park-outline:transaction-order',
  order: 2
},
```

**Step 3: 更新国际化文件（如果需要）**

Run: `find E:\moxton-lotadmin\src\locales -name "*.ts" -o -name "*.json"`
Expected: 找到国际化文件

**Step 4: 添加翻译文本**

在对应的国际化文件中添加：

```typescript
'route.online-order': '在线订单',
```

**Step 5: Commit**

```bash
git add src/router/elegant/routes.ts src/locales
git commit -m "feat(online-order): 添加在线订单路由配置"
```

---

### Task 9: 类型定义更新

**文件:**
- 修改: `E:\moxton-lotadmin\src\typings\api\index.d.ts`

**Step 1: 添加在线订单类型定义**

在文件中添加：

```typescript
declare namespace Api {
  namespace OnlineOrder {
    export type OnlineOrder = import('@/service/api/order').OnlineOrder;
    export type OrderStatus = import('@/service/api/order').OrderStatus;
  }
}
```

**Step 2: Commit**

```bash
git add src/typings/api/index.d.ts
git commit -m "feat(online-order): 添加在线订单类型定义"
```

---

### Task 10: 验证和测试

**Step 1: 运行类型检查**

Run: `cd E:\moxton-lotadmin && npm run type-check`
Expected: No TypeScript errors

**Step 2: 启动开发服务器**

Run: `cd E:\moxton-lotadmin && npm run dev`
Expected: 开发服务器正常启动

**Step 3: 手动测试功能**

访问在线订单管理页面，测试以下功能：
- [ ] 订单列表正常显示
- [ ] 搜索筛选功能正常
- [ ] 查看订单详情
- [ ] 发货功能
- [ ] 确认收货功能
- [ ] 取消订单功能
- [ ] 分页功能
- [ ] 移动端响应式布局

**Step 4: 测试 API 调用**

打开浏览器开发者工具，检查：
- [ ] API 请求路径正确 (`/orders/admin`)
- [ ] 请求参数正确传递
- [ ] 响应数据正确解析
- [ ] 错误处理正常工作

**Step 5: Commit 修复（如有）**

```bash
git add .
git commit -m "fix(online-order): 修复测试发现的问题"
```

---

## 验收标准

- [ ] 在线订单列表正常展示，支持分页
- [ ] 搜索功能正常（订单号、客户信息、状态、日期范围）
- [ ] 订单详情显示完整（客户信息、收货地址、商品列表、支付信息）
- [ ] 发货功能正常工作
- [ ] 确认收货功能正常工作
- [ ] 取消订单功能正常工作
- [ ] 订单状态正确显示和更新
- [ ] 响应式布局适配移动端
- [ ] 无 TypeScript 类型错误
- [ ] 代码风格与 consultation-order 页面一致

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 后端 API 响应格式与预期不符 | 先测试 API 端点，确认返回数据结构 |
| 现有 order.ts API 服务文件需要修复 | 按计划先修复 API 服务，确保端点路径正确 |
| 类型定义可能与后端不一致 | 参考后端 order-response.ts 类型定义 |
| 历史记录接口可能尚未实现 | 暂时使用空数据组件，后续补充 |

---

## 相关文档

- **API 文档:** `E:\moxton-docs\02-api\`
- **参考页面:** `E:\moxton-lotadmin\src\views\consultation-order\`
- **后端路由:** `E:\moxton-lotapi\src\routes\orders.ts`
- **项目状态:** `E:\moxton-docs\04-projects\moxton-lotadmin.md`
