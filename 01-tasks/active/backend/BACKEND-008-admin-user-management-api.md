# Tech-Spec: Admin 用户管理 API 重构与补全

**创建时间:** 2026-02-26
**最后更新:** 2026-02-27
**状态:** QA FAIL — 待修复回归
**角色:** 后端工程师
**项目:** moxton-lotapi
**优先级:** P1
**技术栈:** Node.js + Koa + TypeScript + Prisma + MongoDB

---

## 概述

### 问题陈述

当前 `src/routes/users.ts` 存在以下问题：
1. 路由路径 `/users` 与项目其他 admin 端点风格不一致（orders/admin、offline-orders/admin）
2. 路由仅使用 `authMiddleware`，未使用 `adminMiddleware`，任何登录用户都能调用管理接口
3. 缺少角色变更接口

### 解决方案

将用户管理路由迁移到 `/auth/admin/users` 前缀下，加上 `adminMiddleware`，补全缺失接口。

### 范围 (包含/排除)

**包含:**
- 路由路径重构：`/users` → `/auth/admin/users`
- 所有 admin 用户路由加上 `adminMiddleware`
- 新增 `PUT /auth/admin/users/:id/role` 角色变更接口
- 确认 `getUsers` 分页/筛选逻辑完整性

**不包含:**
- 批量操作（暂不需要）
- 管理员创建用户（暂不需要）
- 用户统计接口（暂不需要）

---

## 当前进度

> **功能开发已完成，QA run2 功能全部 PASS。唯一阻塞项是 TS 编译回归错误。**

### QA run2 结果（2026-02-26）

| 验收项 | 结果 |
|--------|------|
| 所有端点使用 `/auth/admin/users` 前缀 | ✅ PASS |
| 所有端点 auth + admin 中间件保护 | ✅ PASS |
| GET 分页 + keyword + status/role 筛选 | ✅ PASS |
| PUT role 角色切换 | ✅ PASS |
| 自我保护逻辑（状态/角色/删除） | ✅ PASS |
| 旧 /users 路由已移除 | ✅ PASS |
| **npm run build** | **❌ FAIL — TS6133 回归** |

### 阻塞问题

```
src/controllers/Cart.ts(3,1): error TS6133: 'CartModel' is declared but its value is never read
```

这是开发过程中引入的回归错误，不是 BACKEND-008 功能本身的问题，但阻塞了构建。

---

## 开发上下文

### 涉及文件（当前状态）

| 文件 | 状态 | 说明 |
|------|------|------|
| `src/routes/auth.ts` | ✅ 已修改 | 新增 admin/users 路由组（L30-34） |
| `src/controllers/User.ts` | ✅ 已修改 | 新增 updateUserRole（L229-245），完善 getUsers 筛选（L183-216） |
| `src/routes/users.ts` | ✅ 已删除 | 旧路由已移除 |
| `src/middleware/admin.ts` | ✅ 无需变更 | adminMiddleware 已存在 |
| `src/controllers/Cart.ts` | ❌ 需修复 | L3 未使用的 CartModel import |

### 依赖项

- Prisma User 模型（无需变更，role 字段已支持 user/admin）
- adminMiddleware（已存在）

---

## 技术方案

### API 设计

| 方法 | 端点 | 说明 | 中间件 |
|------|------|------|--------|
| GET | `/auth/admin/users` | 用户列表（分页、搜索、状态筛选） | auth + admin |
| GET | `/auth/admin/users/:id` | 用户详情 | auth + admin |
| PUT | `/auth/admin/users/:id/status` | 启用/停用 | auth + admin |
| PUT | `/auth/admin/users/:id/role` | 角色变更（user/admin） | auth + admin |
| DELETE | `/auth/admin/users/:id` | 删除用户 | auth + admin |

#### GET /auth/admin/users 查询参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| pageNum | number | 1 | 页码 |
| pageSize | number | 20 | 每页条数 |
| keyword | string | - | 搜索关键词（匹配 username/email/nickname） |
| status | number | - | 状态筛选（1=active, 0=inactive） |
| role | string | - | 角色筛选（user/admin） |

> **注意**: 分页参数使用 `pageNum`（与 auth.md API 文档一致），响应中也返回 `pageNum`。

#### GET /auth/admin/users 响应格式

```json
{
  "code": 200,
  "message": "Success",
  "data": {
    "list": [
      {
        "id": "clt1234567890",
        "username": "testuser",
        "email": "test@example.com",
        "nickname": "Test",
        "phone": "+86-13800138000",
        "avatar": null,
        "role": "user",
        "status": 1,
        "createdAt": "2025-12-18T10:00:00.000Z",
        "updatedAt": "2025-12-18T10:00:00.000Z"
      }
    ],
    "total": 50,
    "pageNum": 1,
    "pageSize": 20
  },
  "success": true
}
```

#### PUT /auth/admin/users/:id/role 请求体

```json
{
  "role": "admin"  // "user" | "admin"
}
```

#### PUT /auth/admin/users/:id/role 响应

成功（200）：返回更新后的用户对象。

失败 — 自我修改（403）：
```json
{
  "code": 403,
  "message": "Cannot change your own role",
  "data": null,
  "success": false
}
```

失败 — 无效角色值（400）：
```json
{
  "code": 400,
  "message": "Invalid role. Must be 'user' or 'admin'",
  "data": null,
  "success": false
}
```

### 业务逻辑

- 角色变更：不允许管理员修改自己的角色（防止唯一管理员降级）
- 状态变更：不允许管理员停用自己的账户
- 删除用户：不允许删除自己
- 以上三种自我操作均返回 403

---

## 实施步骤

### Step 1: 路由迁移 ✅ 已完成

**目标**: 将用户管理路由从 `/users` 迁移到 `/auth/admin/users`

**修改文件**: `src/routes/auth.ts`

**具体操作**:
1. 在 `src/routes/auth.ts` 中，在现有 auth 路由之后，新增 admin/users 路由组
2. 所有路由挂载 `authMiddleware` + `adminMiddleware`
3. 路由映射：
   - `GET /auth/admin/users` → `UserController.getUsers`
   - `GET /auth/admin/users/:id` → `UserController.getUser`
   - `PUT /auth/admin/users/:id/status` → `UserController.updateUserStatus`
   - `PUT /auth/admin/users/:id/role` → `UserController.updateUserRole`
   - `DELETE /auth/admin/users/:id` → `UserController.deleteUser`

**验收**: 路由注册正确，中间件链完整（auth → admin → controller）

**当前状态**: ✅ 已实现，位于 `src/routes/auth.ts:30-34`

---

### Step 2: 新增角色变更接口 ✅ 已完成

**目标**: 实现 `PUT /auth/admin/users/:id/role`

**修改文件**: `src/controllers/User.ts`

**具体操作**:
1. 新增 `updateUserRole` 方法
2. 参数校验：`role` 必须是 `"user"` 或 `"admin"`，否则返回 400
3. 自我保护：`ctx.state.user.id === id` 时返回 403
4. 调用 Prisma `user.update({ where: { id }, data: { role } })`
5. 返回更新后的用户对象（排除 password 字段）

**验收**:
- `PUT /auth/admin/users/:id/role { "role": "admin" }` → 200，用户角色变为 admin
- `PUT /auth/admin/users/:id/role { "role": "invalid" }` → 400
- 管理员修改自己角色 → 403

**当前状态**: ✅ 已实现，位于 `src/controllers/User.ts:229-245`

---

### Step 3: 完善分页与筛选 ✅ 已完成

**目标**: 确保 `getUsers` 支持完整的分页和筛选

**修改文件**: `src/controllers/User.ts`

**具体操作**:
1. 解析查询参数：`pageNum`（默认 1）、`pageSize`（默认 20）、`keyword`、`status`、`role`
2. keyword 搜索：对 `username`、`email`、`nickname` 三个字段做 `contains`（不区分大小写）模糊匹配
3. status 筛选：精确匹配 `status` 字段（0 或 1）
4. role 筛选：精确匹配 `role` 字段（"user" 或 "admin"）
5. 响应格式：`{ list, total, pageNum, pageSize }`

**验收**:
- 无参数请求返回第一页 20 条 + total
- `?keyword=test` 返回 username/email/nickname 包含 "test" 的用户
- `?status=0` 只返回停用用户
- `?role=admin` 只返回管理员
- 多条件组合筛选正常

**当前状态**: ✅ 已实现，位于 `src/controllers/User.ts:183-216`

---

### Step 4: 删除旧路由 ✅ 已完成

**目标**: 移除旧的 `/users` 路由

**操作**:
1. 删除 `src/routes/users.ts` 文件
2. 从 `src/app.ts`（或路由注册入口）移除对 users 路由的引用

**验收**:
- `GET /users` 返回 404
- 项目中不再有 `src/routes/users.ts` 文件

**当前状态**: ✅ 已完成

---

### Step 5: 修复 TS 编译回归 ❌ 待修复

**目标**: 修复 `npm run build` 的 TS6133 错误

**修改文件**: `src/controllers/Cart.ts`

**具体操作**:
1. 打开 `src/controllers/Cart.ts`
2. 定位第 3 行的 `CartModel` import
3. 确认 `CartModel` 在文件中是否有实际使用
   - 如果没有使用：删除该 import 行
   - 如果有使用但 import 方式不对：修正 import
4. 运行 `npm run build` 确认编译通过
5. 检查是否有其他 TS 编译错误（全量扫描，不只修这一个）

**验收**:
- `npm run build` 退出码 0，无 error 输出
- 不引入新的编译错误

**当前状态**: ❌ 未修复

---

### Step 6: 全量回归验证 ❌ 待执行

**目标**: 确认所有功能正常 + 构建通过

**操作**:
1. `npm run build` — 必须退出码 0
2. 启动服务器，用 curl 验证以下端点：
   - `GET /auth/admin/users` — 无 token → 401
   - `GET /auth/admin/users` — 非 admin token → 403
   - `GET /auth/admin/users` — admin token → 200 + 分页数据
   - `GET /auth/admin/users?keyword=test&status=1&role=user` — 筛选正常
   - `GET /auth/admin/users/:id` — 200 用户详情
   - `PUT /auth/admin/users/:id/status` — 200 状态切换
   - `PUT /auth/admin/users/:id/role` — 200 角色切换
   - `PUT /auth/admin/users/:id/role`（自己）— 403
   - `DELETE /auth/admin/users/:id`（自己）— 403
   - `GET /users` — 404（旧路由已移除）
3. 输出每个请求的完整 curl 命令和响应

**验收**:
- 构建通过
- 所有 10 个测试场景 PASS
- 无回归错误

**当前状态**: ❌ 待执行（依赖 Step 5 完成）

---

## 验收标准

| # | 标准 | 对应 Step | 当前状态 |
|---|------|-----------|---------|
| 1 | 所有 admin 用户端点使用 `/auth/admin/users` 前缀 | Step 1 | ✅ |
| 2 | 所有端点均通过 authMiddleware + adminMiddleware | Step 1 | ✅ |
| 3 | GET /auth/admin/users 支持分页、keyword 搜索、status/role 筛选 | Step 3 | ✅ |
| 4 | PUT /auth/admin/users/:id/role 可正常切换角色 | Step 2 | ✅ |
| 5 | 自我保护逻辑生效（不能改自己角色/停用自己/删除自己） | Step 2 | ✅ |
| 6 | 旧 /users 路由已移除 | Step 4 | ✅ |
| 7 | `npm run build` 编译通过，无 TS 错误 | Step 5 | ❌ |
| 8 | 全量回归验证通过 | Step 6 | ❌ |

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 旧路由移除后管理后台调用失败 | 管理后台 API 路径同步更新（ADMIN-FE-008 任务） |
| 唯一管理员被降级 | 自我保护逻辑（已实现） |
| Cart.ts 修复可能影响购物车功能 | 仅删除未使用的 import，不改业务逻辑 |
| 可能存在其他隐藏的 TS 错误 | Step 5 要求全量 build 扫描，不只修单个文件 |

---

## QA 历史

| 轮次 | 日期 | 结果 | 报告 |
|------|------|------|------|
| run1 | 2026-02-26 | FAIL | `05-verification/ccb-runs/qa-backend-008-report.md` |
| run2 | 2026-02-26 | 功能 PASS / 构建 FAIL | `05-verification/ccb-runs/qa-backend-008-report-run2.md` |

---

**相关文档:**
- [Auth API 文档](../../02-api/auth.md)
- [项目状态](../../04-projects/moxton-lotapi.md)
- [依赖任务: ADMIN-FE-008](../active/admin-frontend/ADMIN-FE-008-user-management-page.md)
