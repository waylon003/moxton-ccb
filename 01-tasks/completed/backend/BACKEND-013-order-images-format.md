# BACKEND-013: 修复订单接口商品图片返回格式

## 问题描述

`/orders/:id` 和 `/orders` 等订单接口返回的商品图片字段 `image` 使用逗号分割的字符串格式，而购物车接口 `/cart` 使用的是 `images` 字符串数组格式。需要统一订单接口的图片格式为数组类型。

## 当前状态

| 接口 | 字段名 | 类型 | 示例 |
|------|--------|------|------|
| `/cart` (购物车) | `images` | `string[]` | `["https://a.jpg", "https://b.jpg"]` |
| `/orders/:id`, `/orders` (订单) | `image` | `string` | `"https://a.jpg,https://b.jpg"` |

## 预期修改

将订单接口响应中的 `items.product.image?: string` 改为 `items.product.images: string[]`，与购物车接口保持一致。

## 影响范围

需要修改以下端点的响应格式：
1. `GET /orders/:id` - 获取订单详情
2. `POST /orders` - 创建订单
3. `POST /orders/checkout` - 购物车结算
4. `GET /orders/user` - 获取用户订单列表（items.product）
5. `GET /orders/guest/orders` - 游客订单列表
6. `GET /orders/guest/orders/:id` - 游客订单详情
7. `GET /orders/guest/query` - 游客订单查询
8. `GET /orders/admin` - 管理端订单列表
9. `GET /orders/admin/:id` - 管理端订单详情
10. `PUT /orders/admin/:id/ship` - 发货操作返回
11. `PATCH /orders/admin/:id/shipping-info` - 更新物流信息返回
12. `PUT /orders/admin/:id/deliver` - 确认收货返回
13. `PUT /orders/admin/:id/status` - 更新状态返回

## 技术实现要点

### 关键文件
- `src/services/order.service.ts` - OrderService 中处理订单数据转换
- `src/utils/transformer/order.transformer.ts` - OrderTransformer 统一响应格式转换
- `prisma/schema.prisma` - Product 模型中 images 字段存储格式

### 实现思路
1. 检查 `OrderTransformer.transform()` 方法中 product 图片字段的处理逻辑
2. 将 `image` 字符串按逗号分割转换为 `images` 数组
3. 或者修改 Prisma 查询时直接映射为数组格式
4. 更新 TypeScript DTO 类型定义
5. 同步更新 API 文档 `02-api/orders.md`

### 数据结构对比

**当前 OrderResponseDTO:**
```typescript
items: [{
  product: {
    id: string
    name: string
    image?: string   // ❌ 单个字符串，逗号分割
  }
}]
```

**目标 OrderResponseDTO:**
```typescript
items: [{
  product: {
    id: string
    name: string
    images: string[]  // ✅ 字符串数组，与购物车一致
  }
}]
```

## 验收标准

- [ ] 所有订单相关接口返回的 `items.product.images` 为字符串数组格式
- [ ] 不再返回 `image` 字段（或同时兼容两者，但推荐前者）
- [ ] 与购物车接口 `/cart` 的 `product.images` 格式完全一致
- [ ] API 文档已更新
- [ ] QA 验证通过：契约测试、网络测试、失败路径测试均通过

## 前置依赖
无

## 后置任务
- 前端如有使用 `item.product.image` 需同步修改为 `item.product.images[0]`
