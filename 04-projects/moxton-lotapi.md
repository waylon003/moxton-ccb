---
last_verified: 2026-03-24
verified_against: [BACKEND-016, BACKEND-014, BACKEND-012, BACKEND-011, BACKEND-007, BUG-004, BACKEND-006]
---

# moxton-lotapi 项目状态

> **项目**: Moxton 后端 API
> **路径**: `E:\moxton-lotapi`
> **类型**: Koa API
> **语言**: TypeScript
> **端口**: 3033
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
| 支付 (Payments) | `/payments` | Stripe 支付意图、订单支付查询、Webhook、支付历史 | ✅ 完成 |
| 地址 (Addresses) | `/addresses` | 用户收货地址 CRUD | ✅ 完成 |
| 通知 (Notifications) | `/notifications` | 用户通知管理 | ✅ 完成 |
| 上传 (Upload) | `/upload` | 图片上传 | ✅ 完成 |
| 咨询订单 (Offline Orders) | `/offline-orders` | 线下咨询订单管理 | ✅ 完成 |
| 系统与诊断 (System) | `根路由` | 运行健康检查、版本信息 | ✅ 完成 |

## 数据模型清单

| 模型 | 说明 | 关键字段 |
|------|------|----------|
| User | 用户 | username, email, password, role(user/admin), status |
| Product | 商品 | name, price, hasPrice, categoryId, status, images |
| Category | 分类 | name, parentId, level, sort, status |
| Cart / CartItem | 购物车 | userId/guestId, items(productId, quantity) |
| Order | 在线订单 | orderNo, status, items, shippingAddress, paymentId |
| OnlineOrderHistory | 订单操作历史 | orderId, action, operator, metadata |
| Payment | 支付记录 | orderId, paymentNo, paymentIntentId, amount, status, expiresAt |
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

### 系统 `/`
- `GET /health` — 服务健康检查（返回 `status`、`uptime`、`environment`）
- `GET /version` — 版本与环境信息

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
- `GET /orders/user` — 用户订单列表
- `GET /orders/:id` — 用户订单详情
- `GET /orders/admin` — 管理员订单列表（支持 keyword 多字段搜索）(admin)
- `GET /orders/admin/:id` — 管理员订单详情（含用户/地址/商品/支付/物流 metadata）(admin)
- `PUT /orders/admin/:id/status` — 更新订单状态 (admin)
- `PUT /orders/admin/:id/ship` — 发货（物流单号/公司/备注均可选）(admin)
- `PATCH /orders/admin/:id/shipping-info` — 补充/修改物流信息（仅 SHIPPED 状态）(admin)
- `PUT /orders/admin/:id/deliver` — 确认收货 (admin)
- `GET /orders/admin/:id/history` — 订单操作历史 (admin)

### 支付 `/payments`
- `POST /payments/stripe/create-intent` — 创建 Stripe 支付意图
- `GET /payments/order/:orderId` — 查询订单支付记录
- `GET /payments/stripe/status/:paymentIntentId` — 查询支付状态
- `POST /payments/stripe/webhook` — Stripe Webhook 回调
- `GET /payments/history` — 支付历史 (auth)

### 地址 `/addresses`
- `GET /addresses` — 用户地址列表 (auth)
- `POST /addresses` — 创建地址 (auth)
- `PUT /addresses/:id` — 更新地址 (auth)
- `DELETE /addresses/:id` — 删除地址 (auth)
- `PUT /addresses/:id/default` — 设为默认地址 (auth)

### 通知 `/notifications`
- `GET /notifications/user` — 通知列表 (auth)
- `GET /notifications/:id` — 通知详情 (auth)
- `PUT /notifications/:id/read` — 标记已读 (auth)
- `PUT /notifications/batch/read` — 批量标记已读 (auth)
- `PUT /notifications/all/read` — 全部已读 (auth)
- `GET /notifications/unread/count` — 未读数量 (auth)
- `GET /notifications/user/stats` — 通知统计 (auth)
- `GET /notifications/user/latest` — 最新通知 (auth)
- `DELETE /notifications/:id` — 删除通知 (auth)

### 上传 `/upload`
- `POST /upload/image` — 上传图片 (auth)

### 咨询订单 `/offline-orders`
- `POST /offline-orders` — 提交咨询订单
- `GET /offline-orders/guest` — 游客咨询订单列表
- `GET /offline-orders/user` — 用户咨询订单列表 (auth)
- `GET /offline-orders/user/:id` — 用户咨询订单详情 (auth)
- `GET /offline-orders/admin` — 咨询订单列表 (admin)
- `GET /offline-orders/admin/:id` — 咨询订单详情 (admin)
- `PUT /offline-orders/admin/:id` — 更新咨询订单状态/备注 (admin)
- `GET /offline-orders/admin/:id/history` — 咨询订单操作历史 (admin)
- `GET /offline-orders/admin/history/stats` — 咨询订单历史统计 (admin)
- `GET /offline-orders/admin/stats/all` — 咨询订单统计 (admin)
- `DELETE /offline-orders/admin/:id` — 删除咨询订单 (admin)
- `POST /offline-orders/admin/batch/delete` — 批量删除 (admin)
- `POST /offline-orders/admin/:id/restore` — 恢复咨询订单 (admin)
- `POST /offline-orders/admin/batch/restore` — 批量恢复咨询订单 (admin)
- `GET /offline-orders/admin/deleted` — 已删除咨询订单列表 (admin)

## Stripe 支付集成

- 使用 Payment Intents API + `automatic_payment_methods`
- 前端通过 Stripe Elements 收集卡片信息
- 支付页先通过 `GET /payments/order/:orderId` 查询最近 5 条支付记录，并优先复用 `activePayment`
- 若历史支付已过期，`POST /payments/stripe/create-intent` 会先将旧记录标记为 `CANCELLED`，再创建新的支付意图
- Webhook 监听 `payment_intent.succeeded` 自动更新订单状态为 PAID
- 支持游客支付（通过 X-Guest-ID 关联）
- metadata 中存储 orderId 用于回调关联

## 订单状态流转

```
PENDING → PAID → CONFIRMED → SHIPPED → DELIVERED
PENDING → CANCELLED（超时或手动取消）
PENDING → 自动清理（15天未支付，node-cron 定时任务）
```

## 订单操作历史

- 规范化主 action 事件类型：`CREATED`、`PAID`、`CONFIRMED`、`SHIPPED`、`DELIVERED`、`CANCELLED`
- 结构化 metadata 字段（物流信息、支付信息等）
- 兼容旧数据格式

## 运行验证基线

- `BACKEND-016`（2026-03-24）QA 摘要再次确认：`http://localhost:3033/health`、`http://localhost:3033/version` 仍可访问，3033 端口开发服务持续监听
- `BACKEND-016`（2026-03-24）文档同步 spot check：`http://localhost:3033/health-not-found` 仍返回标准 `404` JSON 错误包，字段顺序为 `code/message/data/timestamp/success`
- `BACKEND-016` 现存构建/契约/探活证据位于 `05-verification/BACKEND-016/`；最新 `contract-check.json`、`failure-path.json` 更新时间为 2026-03-24 14:48 +08:00，原始 `curl-*`/`automated-test.json` 探活证据时间为 2026-03-19
- `BACKEND-014`（2026-03-20）QA `PASS`：`GET /payments/order/:orderId` 与 `POST /payments/stripe/create-intent` 的“先查询后创建”闭环通过验证
- 历史遗漏已修正：`05-verification/BACKEND-016/contract-check.json` 的 `api_doc` 已回正为 `02-api/system.md`，与当前权威文档一致

## 已知质量问题

- BACKEND-012（2026-03-02）QA 未通过：`GET /orders/user`、`GET /offline-orders/user` 在非法分页参数场景仍返回 `200`，未达到预期 `400`
- 构建与探活基线已在 `BACKEND-016` 重新验证通过，后续如有回归需以 `05-verification/BACKEND-016/` 证据为准

## 相关文档

- [API 文档](../02-api/)
- [集成指南](../03-guides/)
- [项目协调](./COORDINATION.md)
- [依赖关系](./DEPENDENCIES.md)

