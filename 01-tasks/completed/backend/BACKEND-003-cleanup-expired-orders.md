# BACKEND-003: 清理过期未支付订单

**创建时间**: 2025-02-09
**优先级**: 中
**任务类型**: 后端
**关联项目**: moxton-lotapi

---

## 需求描述

实现定期清理超过 15 天未支付的订单，保持数据库清洁。

---

## 功能要求

### 1. 定义过期规则

**过期条件**:
- 订单状态为 `PENDING` (待付款)
- 订单创建时间超过 15 天

---

### 2. 实现清理方法

**文件**: `E:\moxton-lotapi\src\controllers\Order.ts` 或新建清理服务

**方法建议**:
```typescript
cleanupExpiredOrders = asyncHandler(async (ctx: Context) => {
  const fifteenDaysAgo = new Date();
  fifteenDaysAgo.setDate(fifteenDaysAgo.getDate() - 15);

  // 查找过期订单
  const expiredOrders = await prisma.order.findMany({
    where: {
      status: 'PENDING',
      createdAt: { lt: fifteenDaysAgo }
    },
    select: { id: true }
  });

  // 批量删除（或标记为已取消）
  if (expiredOrders.length > 0) {
    await prisma.order.deleteMany({
      where: {
        id: { in: expiredOrders.map(o => o.id) }
      }
    });
  }

  return ctx.ok({
    cleaned: expiredOrders.length,
    message: `Cleaned up ${expiredOrders.length} expired orders`
  });
});
```

---

### 3. 添加定时任务

**方案一**: 使用 node-cron
```bash
npm install node-cron @types/node-cron
```

**文件**: 新建 `E:\moxton-lotapi\src\jobs\cleanup.ts`
```typescript
import cron from 'node-cron';
import { prisma } from '../lib/prisma';

export const cleanupJob = cron.schedule('0 2 * * *', async () => {
  // 每天凌晨 2 点执行
  const fifteenDaysAgo = new Date();
  fifteenDaysAgo.setDate(fifteenDaysAgo.getDate() - 15);

  const result = await prisma.order.deleteMany({
    where: {
      status: 'PENDING',
      createdAt: { lt: fifteenDaysAgo }
    }
  });

  console.log(`[Cleanup] Removed ${result.count} expired orders`);
}, {
  scheduled: false // 需要手动启动
});
```

**在 app.ts 中启动**:
```typescript
import { cleanupJob } from './jobs/cleanup';

// 启动定时任务
cleanupJob.start();
```

---

### 4. 添加管理接口（可选）

**路由**: `POST /orders/admin/cleanup-expired`

允许管理员手动触发清理，用于测试或紧急清理。

---

## 验收标准

1. ✅ 能正确识别超过 15 天未支付的订单
2. ✅ 定时任务每天自动执行清理
3. ✅ 清理操作有日志记录
4. ✅ 不影响其他状态的订单

---

## 测试用例

```bash
# 手动触发清理接口
curl -X POST "http://localhost:3000/orders/admin/cleanup-expired" \
  -H "Authorization: Bearer {token}"

# 预期返回
{
  "cleaned": 5,
  "message": "Cleaned up 5 expired orders"
}
```

---

## 注意事项

1. **软删除 vs 硬删除**: 考虑是否需要保留订单记录（软删除），目前建议直接删除
2. **关联数据**: 删除订单时确保关联的 OrderItems 也会被删除（通过 `onDelete: Cascade` 实现）
3. **日志记录**: 记录每次清理的数量和详情
