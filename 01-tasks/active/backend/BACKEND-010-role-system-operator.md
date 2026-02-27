# Tech-Spec: 角色系统扩展 — 新增 operator 角色

**创建时间:** 2026-02-27
**状态:** 待开发
**角色:** 后端工程师
**项目:** moxton-lotapi
**优先级:** P0
**技术栈:** Node.js + Koa + TypeScript + Prisma + MongoDB
**前置依赖:** 无
**下游依赖:** ADMIN-FE-009

---

## 概述

### 问题陈述

当前系统只有 `user` 和 `admin` 两个角色。管理后台（moxton-lotadmin）没有角色门禁，任何持有合法 token 的 `user` 理论上都能访问管理接口。需要新增 `operator`（运营人员）角色，实现三级权限体系。

### 目标权限模型

```
guest    → nuxt 独立站（浏览器指纹标识，无 token）
user     → nuxt 独立站（顾客，禁止登录管理后台）
operator → vue 管理后台（商品+分类+订单管理，受限权限）
admin    → vue 管理后台（全部功能，含用户管理）
```

### 范围

**包含:**
- Prisma User 模型 role 字段扩展，支持 `operator`
- 新增 `requireRole(...roles)` 中间件工厂函数
- 所有 admin 路由按角色白名单重新挂载中间件
- `/auth/getUserInfo` 正确返回 operator 角色
- 用户管理 API 支持创建/编辑 operator 角色

**不包含:**
- 前端路由/菜单过滤（ADMIN-FE-009 负责）
- 按钮级权限控制（后续迭代）
- 角色继承/组合（保持扁平角色模型）

---

## 开发上下文

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `prisma/schema.prisma` | 修改 | User 模型 role 字段扩展 |
| `src/middleware/role.ts` | 新增 | `requireRole()` 中间件工厂 |
| `src/middleware/admin.ts` | 保留 | 保持向后兼容，内部改为调用 requireRole('admin') |
| `src/routes/auth.ts` | 修改 | admin/users 路由使用 requireRole('admin') |
| `src/routes/products.ts` | 修改 | admin 路由使用 requireRole('admin', 'operator') |
| `src/routes/categories.ts` | 修改 | admin 路由使用 requireRole('admin', 'operator') |
| `src/routes/orders.ts` | 修改 | admin 路由使用 requireRole('admin', 'operator') |
| `src/routes/offlineOrders.ts` | 修改 | admin 路由使用 requireRole('admin', 'operator') |
| `src/routes/upload.ts` | 修改 | 使用 requireRole('admin', 'operator') |
| `src/controllers/User.ts` | 修改 | updateUserRole 支持 operator |
| `src/controllers/Auth.ts` | 修改 | getUserInfo 支持 operator 角色映射 |

### 依赖项

- Prisma Client（需要 regenerate）
- 现有 authMiddleware（不变，仅验证 token 有效性）

---

## 技术方案

### 角色定义

| 角色 | 值 | 可登录管理后台 | 说明 |
|------|---|--------------|------|
| user | `"user"` | ❌ | 顾客，仅 nuxt 独立站 |
| operator | `"operator"` | ✅ | 运营人员，受限管理权限 |
| admin | `"admin"` | ✅ | 管理员，全部权限 |

### 路由权限矩阵

| 路由前缀 | 当前中间件 | 改为 | operator | admin |
|---------|-----------|------|----------|-------|
| `POST/GET /products` (公开) | 无/auth | 不变 | — | — |
| `POST/PUT/DELETE /products` (管理) | auth+admin | auth+requireRole('admin','operator') | ✅ | ✅ |
| `POST/PUT/DELETE /products/batch/*` | auth+admin | auth+requireRole('admin','operator') | ✅ | ✅ |
| `GET/POST/PUT/DELETE /categories` (管理) | auth+admin | auth+requireRole('admin','operator') | ✅ | ✅ |
| `/orders/admin/*` | auth+admin | auth+requireRole('admin','operator') | ✅ | ✅ |
| `/offline-orders/admin/*` | auth+admin | auth+requireRole('admin','operator') | ✅ | ✅ |
| `/auth/admin/users/*` | auth+admin | auth+requireRole('admin') | ❌ | ✅ |
| `/upload/image` | auth | auth+requireRole('admin','operator') | ✅ | ✅ |
| `/notifications` (管理) | auth+admin | auth+requireRole('admin') | ❌ | ✅ |

### requireRole 中间件设计

```typescript
// src/middleware/role.ts
export function requireRole(...allowedRoles: string[]) {
  return async (ctx: Context, next: Next) => {
    const user = ctx.state.user;
    if (!user) {
      ctx.status = 200;
      ctx.body = { code: 401, message: 'No token provided', data: null, success: false };
      return;
    }
    if (!allowedRoles.includes(user.role)) {
      ctx.status = 200;
      ctx.body = {
        code: 403,
        message: `Access denied. Required role: ${allowedRoles.join(' or ')}`,
        data: null,
        success: false
      };
      return;
    }
    await next();
  };
}
```

### getUserInfo 角色映射

```typescript
// 当前
"roles": [user.role]  // ["user"] 或 ["admin"]

// 改为
"roles": [user.role]  // ["user"] 或 ["operator"] 或 ["admin"]
```

无需特殊映射，直接返回数据库中的 role 值即可。

### updateUserRole 扩展

```typescript
// 当前：只允许 "user" | "admin"
const validRoles = ['user', 'admin'];

// 改为：
const validRoles = ['user', 'operator', 'admin'];
```

---

## 实施步骤

### Step 1: 新增 requireRole 中间件

**目标**: 创建可复用的角色检查中间件工厂函数

**新增文件**: `src/middleware/role.ts`

**具体操作**:
1. 创建 `src/middleware/role.ts`
2. 导出 `requireRole(...allowedRoles: string[])` 函数
3. 逻辑：
   - 读取 `ctx.state.user`（由 authMiddleware 注入）
   - 如果 `user` 不存在 → 返回 401
   - 如果 `user.role` 不在 `allowedRoles` 中 → 返回 403
   - 否则 → `await next()`
4. 响应格式与现有 adminMiddleware 保持一致（HTTP 200 + body.code）

**验收**:
- 文件存在且可被其他模块 import
- 中间件签名：`(ctx, next) => Promise<void>`
- 401/403 响应格式与现有一致

**Checkpoint**: 单独测试中间件逻辑（可用单元测试或手动挂载到测试路由）

---

### Step 2: 改造 adminMiddleware 为 requireRole 的包装

**目标**: 保持 adminMiddleware 向后兼容，内部委托给 requireRole

**修改文件**: `src/middleware/admin.ts`

**具体操作**:
1. 导入 `requireRole` from `./role`
2. 将 `adminMiddleware` 改为：
   ```typescript
   export const adminMiddleware = requireRole('admin');
   ```
3. 或者保留原有导出名，内部调用 requireRole

**验收**:
- 现有使用 `adminMiddleware` 的代码无需修改即可正常工作
- admin 用户通过，非 admin 用户被拒绝（行为不变）

**Checkpoint**: 现有所有 admin 接口行为不变（回归验证）

---

### Step 3: Prisma schema 扩展

**目标**: User 模型 role 字段支持 `operator` 值

**修改文件**: `prisma/schema.prisma`

**具体操作**:
1. 找到 User 模型的 `role` 字段
2. 如果是 enum 类型：新增 `operator` 枚举值
3. 如果是 String 类型：无需改 schema，只需在业务层接受 `operator`
4. 运行 `npx prisma generate` 重新生成 Prisma Client
5. **不需要数据迁移** — 现有 admin 账户保持不变

**验收**:
- `npx prisma generate` 成功
- 可以通过 Prisma Client 创建 `role: 'operator'` 的用户
- 现有 user/admin 数据不受影响

**Checkpoint**: `npx prisma generate` 退出码 0

---

### Step 4: 路由中间件替换 — 商品管理

**目标**: 商品管理 admin 路由允许 operator 访问

**修改文件**: `src/routes/products.ts`（或商品路由所在文件）

**具体操作**:
1. 导入 `requireRole` from `../middleware/role`
2. 找到所有使用 `adminMiddleware` 的商品管理路由：
   - `POST /products`（创建商品）
   - `PUT /products/:id`（更新商品）
   - `DELETE /products/:id`（删除商品）
   - `POST /products/batch/delete`（批量删除）
   - `PUT /products/batch/status`（批量状态）
   - `PUT /products/batch/stock`（批量库存）
3. 将 `adminMiddleware` 替换为 `requireRole('admin', 'operator')`

**验收**:
- operator token 调用 `POST /products` → 200
- operator token 调用 `PUT /products/:id` → 200
- user token 调用 `POST /products` → 403
- admin token 行为不变

**Checkpoint**: 用 operator token 和 user token 分别测试一个商品管理端点

---

### Step 5: 路由中间件替换 — 分类管理

**目标**: 分类管理 admin 路由允许 operator 访问

**修改文件**: `src/routes/categories.ts`（或分类路由所在文件）

**具体操作**:
1. 导入 `requireRole`
2. 找到所有使用 `adminMiddleware` 的分类管理路由：
   - `POST /categories`
   - `PUT /categories/:id`
   - `DELETE /categories/:id`
   - `DELETE /categories/batch`
   - `PUT /categories/batch/status`
   - `PUT /categories/:id/move`
3. 替换为 `requireRole('admin', 'operator')`

**验收**:
- operator token 调用分类 CRUD → 200
- user token 调用分类 CRUD → 403

---

### Step 6: 路由中间件替换 — 订单管理

**目标**: 在线订单和咨询订单的 admin 路由允许 operator 访问

**修改文件**:
- `src/routes/orders.ts`
- `src/routes/offlineOrders.ts`（或对应文件名）

**具体操作**:
1. 在线订单 — 所有 `/orders/admin/*` 路由替换为 `requireRole('admin', 'operator')`：
   - `GET /orders/admin`
   - `GET /orders/admin/:id`
   - `PUT /orders/admin/:id/status`
   - `POST /orders/admin/:id/ship`
   - `PATCH /orders/admin/:id/shipping-info`
   - `GET /orders/admin/:id/history`
   - `POST /orders/admin/cleanup-expired`
   - `PUT /orders/admin/:id/deliver`
   - `GET /orders/admin/stats/all`
2. 咨询订单 — 所有 `/offline-orders/admin/*` 路由替换为 `requireRole('admin', 'operator')`：
   - `GET /offline-orders/admin`
   - `PUT /offline-orders/admin/:id/status`
   - `POST /offline-orders/admin/batch/delete`

**验收**:
- operator token 调用 `GET /orders/admin` → 200
- operator token 调用 `GET /offline-orders/admin` → 200
- user token 调用以上接口 → 403

---

### Step 7: 路由中间件替换 — 上传 + 用户管理保持 admin only

**目标**: 上传允许 operator，用户管理保持 admin 专属

**修改文件**:
- `src/routes/upload.ts`（或上传路由所在文件）
- `src/routes/auth.ts`（确认用户管理路由保持 admin only）

**具体操作**:
1. 上传路由 `POST /upload/image`：替换为 `requireRole('admin', 'operator')`
2. 用户管理路由 `/auth/admin/users/*`：确认使用 `requireRole('admin')`（或保持 adminMiddleware）
3. 通知管理路由（如有 admin 端点）：保持 `requireRole('admin')`

**验收**:
- operator token 上传图片 → 200
- operator token 调用 `GET /auth/admin/users` → 403
- admin token 调用 `GET /auth/admin/users` → 200

---

### Step 8: updateUserRole 支持 operator

**目标**: 管理员可以将用户角色设为 operator

**修改文件**: `src/controllers/User.ts`

**具体操作**:
1. 找到 `updateUserRole` 方法中的角色校验逻辑
2. 将 `validRoles` 从 `['user', 'admin']` 改为 `['user', 'operator', 'admin']`
3. 错误消息更新：`"Invalid role. Must be 'user', 'operator' or 'admin'"`

**验收**:
- `PUT /auth/admin/users/:id/role { "role": "operator" }` → 200，角色变为 operator
- `PUT /auth/admin/users/:id/role { "role": "invalid" }` → 400
- operator 用户登录后 `GET /auth/getUserInfo` 返回 `roles: ["operator"]`

---

### Step 9: getUserInfo 验证

**目标**: 确认 getUserInfo 正确返回 operator 角色

**修改文件**: `src/controllers/Auth.ts`（如需修改）

**具体操作**:
1. 检查 `getUserInfo` 的实现
2. 确认 roles 数组直接使用 `[user.role]`，无硬编码的 role 映射
3. 如果有硬编码映射（如 `role === 'admin' ? ['admin'] : ['user']`），需要改为直接返回 `[user.role]`

**验收**:
- user 登录 → `roles: ["user"]`
- operator 登录 → `roles: ["operator"]`
- admin 登录 → `roles: ["admin"]`

---

### Step 10: 全量回归验证

**目标**: 确认所有角色的权限边界正确

**操作**:
1. `npm run build` — 编译通过
2. 准备三个测试账户：user / operator / admin
3. 用 curl 验证以下矩阵：

| 接口 | user | operator | admin |
|------|------|----------|-------|
| `GET /products`（公开） | 200 | 200 | 200 |
| `POST /products`（管理） | 403 | 200 | 200 |
| `POST /categories`（管理） | 403 | 200 | 200 |
| `GET /orders/admin` | 403 | 200 | 200 |
| `GET /offline-orders/admin` | 403 | 200 | 200 |
| `POST /upload/image` | 403 | 200 | 200 |
| `GET /auth/admin/users` | 403 | 403 | 200 |
| `GET /auth/getUserInfo` | roles:["user"] | roles:["operator"] | roles:["admin"] |

4. 输出每个请求的完整 curl 命令和响应

**验收**:
- 编译通过
- 权限矩阵全部符合预期
- 无回归错误

---

## 验收标准

| # | 标准 | 对应 Step |
|---|------|-----------|
| 1 | requireRole 中间件可用且响应格式一致 | Step 1 |
| 2 | adminMiddleware 行为不变（向后兼容） | Step 2 |
| 3 | Prisma 支持 operator 角色 | Step 3 |
| 4 | 商品管理：operator ✅ user ❌ | Step 4 |
| 5 | 分类管理：operator ✅ user ❌ | Step 5 |
| 6 | 订单管理（含咨询）：operator ✅ user ❌ | Step 6 |
| 7 | 上传：operator ✅；用户管理：operator ❌ | Step 7 |
| 8 | 可将用户角色设为 operator | Step 8 |
| 9 | getUserInfo 正确返回 operator 角色 | Step 9 |
| 10 | 全量权限矩阵验证通过 | Step 10 |

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 现有 adminMiddleware 调用方被遗漏 | Step 2 保持向后兼容，不改导出签名 |
| Prisma schema 变更导致数据问题 | 仅扩展 role 可选值，不改字段类型，不需要数据迁移 |
| 路由文件名/路径与文档不一致 | Worker 需先 `ls src/routes/` 确认实际文件名 |
| operator 权限边界遗漏 | Step 10 全量矩阵验证覆盖所有端点 |

---

## 数据迁移

**不需要数据迁移。** 现有 admin 账户保持 `role: "admin"` 不变。operator 角色通过管理后台用户管理页面手动分配。

---

**相关文档:**
- [Auth API 文档](../../02-api/auth.md)
- [项目状态](../../04-projects/moxton-lotapi.md)
- [下游任务: ADMIN-FE-009](../active/admin-frontend/ADMIN-FE-009-role-based-access-control.md)
