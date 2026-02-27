---
last_verified: 2026-02-26
verified_against: [BACKEND-007, BUG-004, BACKEND-006]
---

# moxton-lotapi 项目状态

> **项目**: Moxton 后端 API
> **路径**: `E:\moxton-lotapi`
> **类型**: Koa API
> **语言**: TypeScript
> **端口**: 3006
> **状态**: 🟢 活跃

## 项目概述

Moxton 后端 API 服务，为商城前端和管理后台提供数据接口。基于 Koa 框架构建的 RESTful API，集成 Stripe 支付、JWT 认证、定时任务等能力。

## 技术栈

- **框架**: Koa
- **语言**: TypeScript
- **数据库**: MongoDB (Prisma ORM)
- **支付**: Stripe (Payment Intents + Webhooks)
- **认证**: JWT (Bearer Token)
- **定时任务**: node-cron（过期订单清理）

## 功能模块清单

| 模块 | 路由前缀 | 说明 | 状态 |
|------|----------|------|------|
| 认证 (Auth) | `/auth` | 注册、登录、用户信息管理 | ✅ 完成 |
| 商品 (Products) | `/products` | 商品 CRUD、搜索、批量操作 | ✅ 完成 |
| 分类 (Categories) | `/categories` | 分类树、CRUD、排序、移动 | ✅ 完成 |
| 购物车 (Cart) | `/cart` | 购物车增删改查、合并 | ✅ 完成 |
| 在线订单 (Orders) | `/orders` | 结账、订单管理、状态流转、操作历史 | ✅ 完成 |
| 支付 (Payments) | `/payments` | Stripe 支付意图、Webhook、退款 | ✅ 完成 |
| 地址 (Addresses) | `/addresses` | 用户收货地址 CRUD | ✅ 完成 |
| 通知 (Notifications) | `/notifications` | 用户通知管理 | ✅ 完成 |
| 上传 (Upload) | `/upload` | 图片上传 | ✅ 完成 |
| 咨询订单 (Offline Orders) | `/offline-orders` | 线下咨询订单管理 | ✅ 完成 |

## 数据模型清单

| 模型 | 说明 | 关键字段 |
|------|------|----------|
| User | 用户 | username, email, password, role(user/admin), status |
| Product | 商品 | name, price, hasPrice, categoryId, status, images |
| Category | 分类 | name, parentId, level, sort, status |
| Cart / CartItem | 购物车 | userId/guestId, items(productId, quantity) |
| Order | 在线订单 | orderNo, status, items, shippingAddress, paymentId |
| OnlineOrderHistory | 订单操作历史 | orderId, action, operator, metadata |
| Payment | 支付记录 | orderId, stripePaymentIntentId, amount, status |
| OfflineOrder | 咨询订单 | productId, name, phone, email, status |
| Address | 收货地址 | userId, street, city, state, postcode, isDefault |
| Notification | 通知 | userId, title, content, read |

## 中间件

| 中间件 | 说明 |
|--------|------|
| authMiddleware | JWT 认证，解析 Bearer Token |
| adminMiddleware | 管理员权限校验 (role === 'admin') |
| guestMiddleware | 游客标识，读取 X-Guest-ID |

## API 端点总览

### 认证 `/auth`
- `POST /auth/register` — 用户注册
- `POST /auth/login` — 用户登录
- `GET /auth/profile` — 获取用户信息 (auth)
- `PUT /auth/profile` — 更新用户信息 (auth)
- `POST /auth/change-password` — 修改密码 (auth)

### 商品 `/products`
- `GET /products` — 商品列表（支持分页、筛选、keyword 搜索）
- `GET /products/:id` — 商品详情
- `POST /products` — 创建商品 (admin)
- `PUT /products/:id` — 更新商品 (admin)
- `DELETE /products/:id` — 删除商品 (admin)
- `POST /products/batch/delete` — 批量删除 (admin)
- `PUT /products/batch/status` — 批量更新状态 (admin)
- `PUT /products/batch/stock` — 批量更新库存 (admin)

### 分类 `/categories`
- `GET /categories/tree` — 完整分类树
- `GET /categories/tree/active` — 启用分类树
- `GET /categories/with-count` — 分类及商品数量
- `GET /categories/:id` — 分类详情
- `POST /categories` — 创建分类 (admin)
- `PUT /categories/:id` — 更新分类 (admin)
- `DELETE /categories/:id` — 删除分类 (admin)
- `DELETE /categories/batch` — 批量删除 (admin)
- `PUT /categories/batch/status` — 批量更新状态 (admin)
- `GET /categories/:id/children` — 获取子分类
- `GET /categories/:id/path` — 获取分类路径
- `PUT /categories/:id/move` — 移动分类 (admin)

### 购物车 `/cart`
- `GET /cart` — 获取购物车
- `POST /cart/item` — 添加购物车项
- `PUT /cart/item/:id` — 更新数量
- `DELETE /cart/item/:id` — 删除购物车项
- `DELETE /cart/clear` — 清空购物车
- `POST /cart/merge` — 合并游客购物车

### 在线订单 `/orders`
- `POST /orders` — 创建订单（结账）
- `GET /orders` — 用户订单列表
- `GET /orders/:id` — 用户订单详情
- `GET /orders/admin` — 管理员订单列表（支持 keyword 多字段搜索）(admin)
- `GET /orders/admin/:id` — 管理员订单详情（含用户/地址/商品/支付/物流 metadata）(admin)
- `PUT /orders/admin/:id/status` — 更新订单状态 (admin)
- `POST /orders/admin/:id/ship` — 发货（物流单号/公司/备注均可选）(admin)
- `PATCH /orders/admin/:id/shipping-info` — 补充/修改物流信息（仅 SHIPPED 状态）(admin)
- `GET /orders/admin/:id/history` — 订单操作历史 (admin)

### 支付 `/payments`
- `POST /payments/stripe/create-intent` — 创建 Stripe 支付意图
- `POST /payments/stripe/webhook` — Stripe Webhook 回调
- `GET /payments/:orderId` — 查询支付状态
- `POST /payments/:paymentId/refund` — 发起退款 (admin)

### 地址 `/addresses`
- `GET /addresses` — 用户地址列表 (auth)
- `POST /addresses` — 创建地址 (auth)
- `PUT /addresses/:id` — 更新地址 (auth)
- `DELETE /addresses/:id` — 删除地址 (auth)
- `PUT /addresses/:id/default` — 设为默认地址 (auth)

### 通知 `/notifications`
- `GET /notifications` — 通知列表 (auth)
- `PUT /notifications/:id/read` — 标记已读 (auth)
- `PUT /notifications/read-all` — 全部已读 (auth)
- `DELETE /notifications/:id` — 删除通知 (auth)

### 上传 `/upload`
- `POST /upload/image` — 上传图片 (auth)

### 咨询订单 `/offline-orders`
- `POST /offline-orders` — 提交咨询订单
- `GET /offline-orders/admin` — 咨询订单列表 (admin)
- `PUT /offline-orders/admin/:id/status` — 更新咨询订单状态 (admin)
- `POST /offline-orders/admin/batch/delete` — 批量删除 (admin)

## Stripe 支付集成

- 使用 Payment Intents API + `automatic_payment_methods`
- 前端通过 Stripe Elements 收集卡片信息
- Webhook 监听 `payment_intent.succeeded` 自动更新订单状态为 PAID
- 支持游客支付（通过 X-Guest-ID 关联）
- metadata 中存储 orderId 用于回调关联

## 订单状态流转

```
PENDING → PAID → CONFIRMED → SHIPPED → DELIVERED → COMPLETED
                                                  ↘ CANCELLED
PENDING → CANCELLED（超时或手动取消）
PENDING → 自动清理（15天未支付，node-cron 定时任务）
```

## 订单操作历史

- 规范化 action 事件类型：`created`, `paid`, `confirmed`, `shipped`, `delivered`, `completed`, `cancelled`, `shipping_updated`, `refunded`
- 结构化 metadata 字段（物流信息、支付信息等）
- 兼容旧数据格式

## 已知质量问题

- TypeScript 编译存在 242 条错误（2026-02-25 QA 报告）
- 功能层面验证通过，基线构建质量待修复

## 相关文档

- [API 文档](../02-api/)
- [集成指南](../03-guides/)
- [项目协调](./COORDINATION.md)
- [依赖关系](./DEPENDENCIES.md)
