---
last_verified: 2026-03-10
verified_against: [BACKEND-007, ADMIN-FE-007, SHOP-FE-001]
---

# 项目协调状态

> **用途**: Team Lead 通过此文件感知三个项目的协调状态
> **更新频率**: 每次修改跨项目接口时更新
> **最后更新**: 2026-03-10

## 📊 项目概览

| 项目 | 路径 | 类型 | 端口 | 状态 |
|------|------|------|------|------|
| 后端 API | `E:\moxton-lotapi` | Koa/TypeScript | 3006 | 🟢 活跃 |
| 管理后台 | `E:\moxton-lotadmin` | Vue3/Soybean | 3002 | 🟢 活跃 |
| 前端商城 | `E:\nuxt-moxton` | Nuxt3 | 3666 | 🟢 活跃 |

---

## 🔥 功能完成总览 (截至 2026-02-26)

### 已完成的核心功能链路

#### 在线购物完整流程
```
用户注册/登录 (auth) → 浏览商品 (products) → 加入购物车 (cart)
→ 选择收货地址 (addresses) → 创建订单 (orders) → Stripe 支付 (payments)
→ Webhook 回调更新状态 → 管理员发货 (ship) → 确认收货 → 完成
```

#### 咨询订单流程
```
浏览无价格商品 → 提交咨询表单 (offline-orders) → 管理员处理/报价
```

#### 管理后台功能
```
产品管理 + 分类管理 + 在线订单管理（含发货/物流/操作历史）+ 咨询订单管理
```

### 已完成任务统计

| 仓库 | 任务数 | Bug 修复 | 功能开发 |
|------|--------|---------|----------|
| 后端 (moxton-lotapi) | 12 | 4 | 8 |
| 管理后台 (moxton-lotadmin) | 8 | 0 | 8 |
| 商城前端 (nuxt-moxton) | 1 | 0 | 1 |
| **总计** | **21** | **4** | **17** |

---

## 📡 API 接口契约

### 认证
```typescript
POST /auth/register    // 用户注册
POST /auth/login       // 用户登录 → 返回 JWT Token
GET  /auth/profile     // 获取用户信息 (Bearer Token)
PUT  /auth/profile     // 更新用户信息
POST /auth/change-password // 修改密码
```

### 商品与分类
```typescript
GET  /products              // 商品列表（分页、筛选、keyword 搜索）
GET  /products/:id          // 商品详情
GET  /categories/tree/active // 启用分类树
```

### 购物车
```typescript
GET    /cart           // 获取购物车（支持游客 X-Guest-ID）
POST   /cart/item      // 添加购物车项
PUT    /cart/item/:id  // 更新数量
DELETE /cart/item/:id  // 删除购物车项
DELETE /cart/clear     // 清空购物车
POST   /cart/merge     // 合并游客购物车（登录后）
```

### 在线订单
```typescript
POST /orders                        // 创建订单（结账）
GET  /orders                        // 用户订单列表
GET  /orders/:id                    // 用户订单详情
GET  /orders/admin                  // 管理员订单列表（keyword 多字段搜索）
GET  /orders/admin/:id              // 管理员订单详情（含 metadata）
PUT  /orders/admin/:id/status       // 更新订单状态
POST /orders/admin/:id/ship         // 发货（物流信息可选）
PATCH /orders/admin/:id/shipping-info // 补充物流信息（仅 SHIPPED）
GET  /orders/admin/:id/history      // 操作历史
```

### 支付 (Stripe)
```typescript
POST /payments/stripe/create-intent // 创建支付意图
POST /payments/stripe/webhook       // Stripe Webhook 回调
GET  /payments/:orderId             // 查询支付状态
POST /payments/:paymentId/refund    // 退款 (admin)
```

### 收货地址
```typescript
GET    /addresses              // 地址列表
POST   /addresses              // 创建地址
PUT    /addresses/:id          // 更新地址
DELETE /addresses/:id          // 删除地址
PUT    /addresses/:id/default  // 设为默认
```

### 通知
```typescript
GET    /notifications           // 通知列表
PUT    /notifications/:id/read  // 标记已读
PUT    /notifications/read-all  // 全部已读
DELETE /notifications/:id       // 删除通知
```

### 咨询订单
```typescript
POST /offline-orders                      // 提交咨询订单
GET  /offline-orders/admin                // 咨询订单列表 (admin)
PUT  /offline-orders/admin/:id/status     // 更新状态 (admin)
POST /offline-orders/admin/batch/delete   // 批量删除 (admin)
```

### 上传
```typescript
POST /upload/image  // 图片上传
```

---

## 🔗 项目依赖关系

```
┌─────────────────┐
│  nuxt-moxton    │ ── auth, products, categories, cart, orders,
│  (前端商城)      │    payments, addresses, notifications,
│    :3666        │    offline-orders, upload
└────────┬────────┘
         │
         │ HTTP API
         │
┌────────┴────────┐
│  moxton-lotapi  │
│  (后端 API)      │
│    :3006        │
└────────┬────────┘
         │
         │ HTTP API
         │
┌────────┴────────┐
│ moxton-lotadmin │ ── products, categories, orders (admin),
│  (管理后台)      │    offline-orders (admin), upload
│    :3002        │
└─────────────────┘
```

---

## 🚨 待同步事项

### 已知质量问题
- 后端 TypeScript 编译 242 条错误（功能不受影响，需系统性修复）
- 管理后台 lint 102 errors / 76 warnings
- 构建环境 spawn EPERM 权限问题

### 缺失功能
- 管理后台：用户管理模块未实现
- 管理后台：数据统计/仪表盘未实现

---

## 📝 使用指南

### 当后端修改 API 时
1. 后端任务先完成开发与 QA 验收
2. QA `success` 后由 `route-monitor` 实时触发 `doc-updater` 同步 `02-api/`
3. 开发任务归档（`active -> completed`）后再次触发 `doc-updater` 做一致性补漏
4. 更新本文件的 "API 接口契约" 部分
5. 再派遣相关前端任务（避免读取过期 API 文档）

### 当前端需要调用新 API 时
1. 先确认后端依赖任务已 `completed/qa_passed`
2. 再确认 API 文档同步状态为最新（由 doc-updater 回传 `synced`）
3. 查看本文件的 "API 接口契约" 部分
4. 参考 `02-api/*.md` 中的详细文档
5. 更新对应项目文档

### 当管理后台需要调用新 API 时
1. 查看本文件的 "API 接口契约" 部分
2. 更新调用代码
3. 更新对应项目文档
