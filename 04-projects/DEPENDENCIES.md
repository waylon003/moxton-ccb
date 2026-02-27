---
last_verified: 2026-02-26
verified_against: [BACKEND-007, ADMIN-FE-007, SHOP-FE-001]
---

# 跨项目依赖关系

> **更新时间**: 2026-02-26
> **用途**: 清晰展示三个项目之间的 API 依赖和数据流向

## 依赖关系图

```
┌─────────────────────────────────────────────────────────┐
│                    用户访问                              │
└───────────────────────┬─────────────────────────────────┘
                        │
        ┌───────────────┴───────────────┐
        │                               │
        ▼                               ▼
┌──────────────┐              ┌──────────────┐
│ nuxt-moxton  │              │moxton-lotadmin│
│  (商城前端)   │              │  (管理后台)   │
│    :3000     │              │    :3002     │
└──────┬───────┘              └──────┬───────┘
       │                             │
       │ HTTP API                    │ HTTP API
       │                             │
       └─────────────┬───────────────┘
                     │
                     ▼
            ┌──────────────┐
            │ moxton-lotapi│
            │  (后端 API)   │
            │    :3006      │
            └──────┬───────┘
                   │
                   ▼
            ┌──────────────┐
            │   MongoDB    │
            │  (数据库)     │
            └──────────────┘
```

## API 依赖详情

### nuxt-moxton → moxton-lotapi

| API 端点 | 方法 | 用途 | 状态 |
|---------|------|------|------|
| `/auth/register` | POST | 用户注册 | ✅ 同步 |
| `/auth/login` | POST | 用户登录 | ✅ 同步 |
| `/auth/profile` | GET/PUT | 用户信息管理 | ✅ 同步 |
| `/auth/change-password` | POST | 修改密码 | ✅ 同步 |
| `/products` | GET | 商品列表 | ✅ 同步 |
| `/products/:id` | GET | 商品详情 | ✅ 同步 |
| `/categories/tree/active` | GET | 获取分类树 | ✅ 同步 |
| `/cart/*` | GET/POST/PUT/DELETE | 购物车操作 | ✅ 同步 |
| `/cart/merge` | POST | 合并游客购物车 | ✅ 同步 |
| `/orders` | POST/GET | 创建订单 / 订单列表 | ✅ 同步 |
| `/orders/:id` | GET | 订单详情 | ✅ 同步 |
| `/payments/stripe/create-intent` | POST | 创建 Stripe 支付意图 | ✅ 同步 |
| `/payments/:orderId` | GET | 查询支付状态 | ✅ 同步 |
| `/addresses` | GET/POST/PUT/DELETE | 收货地址管理 | ✅ 同步 |
| `/addresses/:id/default` | PUT | 设为默认地址 | ✅ 同步 |
| `/notifications` | GET/PUT/DELETE | 通知管理 | ✅ 同步 |
| `/offline-orders` | POST | 提交咨询订单 | ✅ 同步 |
| `/upload/image` | POST | 图片上传 | ✅ 同步 |

### moxton-lotadmin → moxton-lotapi

| API 端点 | 方法 | 用途 | 状态 |
|---------|------|------|------|
| `/products` | GET/POST/PUT/DELETE | 产品管理 | ✅ 同步 |
| `/products/batch/*` | POST/PUT | 批量操作 | ✅ 同步 |
| `/categories/*` | GET/POST/PUT/DELETE | 分类管理 | ✅ 同步 |
| `/orders/admin` | GET | 订单列表（keyword 搜索） | ✅ 同步 |
| `/orders/admin/:id` | GET | 订单详情（含 metadata） | ✅ 同步 |
| `/orders/admin/:id/status` | PUT | 更新订单状态 | ✅ 同步 |
| `/orders/admin/:id/ship` | POST | 发货 | ✅ 同步 |
| `/orders/admin/:id/shipping-info` | PATCH | 补充物流信息 | ✅ 同步 |
| `/orders/admin/:id/history` | GET | 操作历史 | ✅ 同步 |
| `/offline-orders/admin` | GET | 咨询订单列表 | ✅ 同步 |
| `/offline-orders/admin/:id/status` | PUT | 更新咨询订单状态 | ✅ 同步 |
| `/offline-orders/admin/batch/delete` | POST | 批量删除咨询订单 | ✅ 同步 |
| `/upload/image` | POST | 图片上传 | ✅ 同步 |

### Stripe → moxton-lotapi (Webhook)

| 事件 | 端点 | 用途 | 状态 |
|------|------|------|------|
| `payment_intent.succeeded` | `POST /payments/stripe/webhook` | 支付成功回调，更新订单为 PAID | ✅ 同步 |

## 数据模型依赖

### 共享数据实体

| 实体 | 存储位置 | 访问项目 | 说明 |
|------|----------|----------|------|
| User | MongoDB | frontend, admin, backend | 用户账户，role 区分普通/管理员 |
| Product | MongoDB | frontend, admin, backend | 商品信息，hasPrice 区分定价/咨询 |
| Category | MongoDB | frontend, admin, backend | 分类树，支持多级嵌套 |
| Cart / CartItem | MongoDB | frontend, backend | 购物车，支持游客 (guestId) |
| Order | MongoDB | frontend, admin, backend | 在线订单，含状态流转 |
| OnlineOrderHistory | MongoDB | admin, backend | 订单操作历史记录 |
| Payment | MongoDB | frontend, admin, backend | Stripe 支付记录 |
| OfflineOrder | MongoDB | frontend, admin, backend | 咨询订单 |
| Address | MongoDB | frontend, backend | 用户收货地址 |
| Notification | MongoDB | frontend, backend | 用户通知 |

## 接口契约变更流程

当需要修改 API 接口时，按以下顺序执行：

1. **后端优先** - moxton-lotapi 先实现新接口
2. **文档更新** - 更新 `02-api/` 中的 API 文档
3. **前端同步** - nuxt-moxton 实现调用
4. **后台同步** - moxton-lotadmin 实现调用（如需要）
5. **状态更新** - 更新 `COORDINATION.md` 和本文件

## 版本兼容性

| 组件 | 版本要求 | 说明 |
|------|----------|------|
| nuxt-moxton | Node.js 18+ | Nuxt 3 要求 |
| moxton-lotadmin | Node.js 18+ | Vue 3 要求 |
| moxton-lotapi | Node.js 18+ | Koa 要求 |
| MongoDB | 6.0+ | 数据存储 |

## 待解决依赖

- 管理后台缺少用户管理模块（后端 auth API 已就绪，前端未对接）
- 管理后台缺少数据统计模块（后端无对应 API）
