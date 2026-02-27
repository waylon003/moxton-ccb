# Tech-Spec: Admin 用户管理 API 重构与补全

**创建时间:** 2026-02-26
**状态:** 准备开发
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

## 开发上下文

### 现有实现

| 文件 | 说明 |
|------|------|
| `src/routes/users.ts` | 现有用户管理路由（GET /, GET /:id, PUT /:id/status, DELETE /:id） |
| `src/routes/auth.ts` | 认证路由（register, login, profile, password） |
| `src/controllers/User.ts` | 用户控制器（getUsers, updateUserStatus, deleteUser） |
| `src/models/User.ts` | 用户模型层 |
| `src/middleware/admin.ts` | adminMiddleware（验证 role === 'admin'） |
| `src/middleware/auth.ts` | authMiddleware（JWT 验证） |

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

| 参数 | 类型 | 说明 |
|------|------|------|
| page | number | 页码，默认 1 |
| pageSize | number | 每页条数，默认 20 |
| keyword | string | 搜索关键词（匹配 username/email/nickname） |
| status | number | 状态筛选（1=active, 0=inactive） |
| role | string | 角色筛选（user/admin） |

#### PUT /auth/admin/users/:id/role 请求体

```json
{
  "role": "admin"  // "user" | "admin"
}
```

### 业务逻辑

- 角色变更：不允许管理员修改自己的角色（防止唯一管理员降级）
- 状态变更：不允许管理员停用自己的账户
- 删除用户：不允许删除自己

---

## 实施步骤

1. 在 `src/routes/auth.ts` 中新增 admin/users 路由组，挂载 authMiddleware + adminMiddleware
2. 在 `src/controllers/User.ts` 中新增 `updateUserRole` 方法
3. 检查并完善 `getUsers` 的分页和筛选逻辑（keyword 多字段模糊搜索、status/role 筛选）
4. 删除或废弃旧的 `src/routes/users.ts`
5. 手动测试所有端点

---

## 验收标准

- [ ] 所有 admin 用户端点使用 `/auth/admin/users` 前缀
- [ ] 所有端点均通过 authMiddleware + adminMiddleware
- [ ] GET /auth/admin/users 支持分页、keyword 搜索、status/role 筛选
- [ ] PUT /auth/admin/users/:id/role 可正常切换角色
- [ ] 自我保护逻辑生效（不能改自己角色/停用自己/删除自己）
- [ ] 旧 /users 路由已移除

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 旧路由移除后管理后台调用失败 | 管理后台 API 路径同步更新（ADMIN-FE-008 任务） |
| 唯一管理员被降级 | 自我保护逻辑 |

---

**相关文档:**
- [Auth API 文档](../../02-api/auth.md)
- [项目状态](../../04-projects/moxton-lotapi.md)
- [依赖任务: ADMIN-FE-008](../active/admin-frontend/ADMIN-FE-008-user-management-page.md)
