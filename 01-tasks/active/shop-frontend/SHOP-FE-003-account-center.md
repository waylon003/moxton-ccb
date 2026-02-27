# Tech-Spec: 个人中心

**创建时间:** 2026-02-26
**状态:** 准备开发
**角色:** 独立站前端工程师
**项目:** nuxt-moxton
**优先级:** P2
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia
**前置依赖:** SHOP-FE-002

---

## 概述

### 问题陈述

商城前端没有个人中心页面，用户登录后无法查看/编辑资料、查看订单历史、管理收货地址、查看咨询记录。

### 解决方案

新增 `/account` 页面框架（侧边导航 + 内容区），包含基础资料、改密码、订单历史、收货地址管理、咨询记录五个子模块。

### 范围 (包含/排除)

**包含:**
- 个人中心页面框架（侧边导航 + 内容区）
- 基础资料（查看/编辑昵称、手机号、头像）
- 修改密码
- 订单历史（列表 + 详情查看）
- 收货地址管理（CRUD + 设为默认）
- 咨询记录（查看已提交的咨询订单）

**不包含:**
- 通知中心（后续迭代）
- 订单取消/退款操作
- 头像上传裁剪

---

## 开发上下文

### 现有实现

| 文件 | 说明 |
|------|------|
| `composables/api/auth.ts` | updateProfile, getCurrentUser 等方法 |
| `stores/auth.ts` | SHOP-FE-002 创建的认证 store |
| `composables/api/` | 需确认是否已有 orders、addresses、offline-orders 的 API composable |

### 依赖项

- SHOP-FE-002 完成（登录/注册 + auth store）
- 后端 API 已就绪：
  - `GET/PUT /auth/profile` — 资料
  - `POST /auth/change-password` — 改密码
  - `GET /orders` — 订单列表
  - `GET /orders/:id` — 订单详情
  - `GET/POST/PUT/DELETE /addresses` — 地址 CRUD
  - `PUT /addresses/:id/default` — 默认地址
  - `POST /offline-orders` — 咨询订单（已有提交，需确认是否有用户查询接口）

---

## 技术方案

### 架构设计

```
pages/account/
├── index.vue           # 个人中心框架（侧边导航 + router-view）
├── profile.vue         # 基础资料
├── password.vue        # 修改密码
├── orders/
│   ├── index.vue       # 订单列表
│   └── [id].vue        # 订单详情
├── addresses.vue       # 收货地址管理
└── consultations.vue   # 咨询记录
```

### 页面功能

#### 基础资料 (profile.vue)
- 展示：用户名（只读）、邮箱（只读）、昵称、手机号、头像
- 编辑：昵称、手机号、头像 URL
- 调用：`GET /auth/profile` + `PUT /auth/profile`

#### 修改密码 (password.vue)
- 表单：当前密码、新密码、确认新密码
- 调用：`POST /auth/change-password`

#### 订单历史 (orders/)
- 列表：订单号、状态、金额、时间、商品缩略图
- 详情：完整订单信息（商品明细、收货地址、支付信息、物流信息）
- 调用：`GET /orders` + `GET /orders/:id`

#### 收货地址 (addresses.vue)
- 列表：地址卡片，默认地址标记
- 操作：新增、编辑、删除、设为默认
- 调用：`GET/POST/PUT/DELETE /addresses` + `PUT /addresses/:id/default`

#### 咨询记录 (consultations.vue)
- 列表：咨询的商品、提交时间、状态
- 需确认后端是否有用户查询自己咨询订单的接口

### API 调用

| 方法 | 端点 | 用途 |
|------|------|------|
| GET/PUT | `/auth/profile` | 资料查看/编辑 |
| POST | `/auth/change-password` | 修改密码 |
| GET | `/orders` | 订单列表 |
| GET | `/orders/:id` | 订单详情 |
| GET/POST/PUT/DELETE | `/addresses` | 地址 CRUD |
| PUT | `/addresses/:id/default` | 设为默认 |
| GET | `/offline-orders/user`（待确认） | 咨询记录 |

---

## 实施步骤

1. 创建 `/pages/account/index.vue` 框架（侧边导航 + 内容区）
2. 创建 profile.vue（资料查看/编辑）
3. 创建 password.vue（修改密码）
4. 创建 orders/index.vue（订单列表）
5. 创建 orders/[id].vue（订单详情）
6. 创建 addresses.vue（地址管理）
7. 确认咨询记录接口，创建 consultations.vue
8. 测试所有子页面功能

---

## 验收标准

- [ ] 个人中心侧边导航可切换各子页面
- [ ] 基础资料可查看和编辑
- [ ] 修改密码功能正常
- [ ] 订单列表正常加载，支持分页
- [ ] 订单详情展示完整信息
- [ ] 收货地址 CRUD 正常
- [ ] 默认地址设置正常
- [ ] 咨询记录可查看
- [ ] 未登录访问重定向到登录页

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 咨询记录缺少用户查询接口 | 开发时确认，如缺失则新增后端任务 |
| 页面较多，工作量大 | 按子页面拆分，逐步交付 |

---

**相关文档:**
- [Auth API 文档](../../02-api/auth.md)
- [Orders API 文档](../../02-api/orders.md)
- [Addresses API 文档](../../02-api/addresses.md)
- [项目状态](../../04-projects/nuxt-moxton.md)
- [前置任务: SHOP-FE-002](../active/shop-frontend/SHOP-FE-002-login-register-auth.md)
