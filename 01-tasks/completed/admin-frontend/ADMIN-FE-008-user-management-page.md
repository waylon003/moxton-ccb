# Tech-Spec: 用户管理页面 — 功能验证 + 遗留修复

**创建时间:** 2026-02-26
**最后更新:** 2026-02-27
**状态:** 待验证
**角色:** 管理后台前端工程师
**项目:** moxton-lotadmin
**优先级:** P1
**技术栈:** Vue 3 + TypeScript + Soybean Admin + Naive UI
**前置依赖:** BACKEND-008

---

## 概述

### 问题陈述

用户管理页面代码已基本完成（API 服务、列表页、详情抽屉、路由注册），但上一轮 QA 因以下原因 FAIL：
1. **QA 误判**：QA 认为分页参数应为 `page`，但后端实际使用 `pageNum` — 前端是正确的
2. **QA 误判**：QA 认为详情抽屉缺少关联订单数，但代码已实现 `relatedOrderCount` 逻辑
3. **环境问题**：`pnpm build:test` 和 `pnpm test:e2e` 报 `spawn EPERM`，非代码问题

需要重新验证功能完整性，修复可能存在的遗留问题。

### 解决方案

逐项验证现有实现，确认功能正常后标记完成。如发现实际问题则修复。

### 范围

**包含:**
- 验证 API 路径与后端 BACKEND-008 一致
- 验证列表页功能（搜索、筛选、分页、状态切换、角色切换、删除）
- 验证详情抽屉（用户信息 + 关联订单数）
- 验证路由和菜单入口
- 修复验证中发现的实际问题

**不包含:**
- operator 角色支持（ADMIN-FE-009 负责）
- 角色门禁（ADMIN-FE-009 负责）
- 批量操作
- 用户统计仪表盘

---

## 当前进度

> **代码已基本完成，需要功能验证。**

### QA 历史

| 轮次 | 时间 | 结果 | 问题 | 实际情况 |
|------|------|------|------|----------|
| Run 1 | 2026-02-26 | ❌ FAIL | 分页参数 `pageNum` 应为 `page` | ❌ QA 误判，后端用 `pageNum` |
| Run 1 | 2026-02-26 | ❌ FAIL | 详情抽屉缺少关联订单数 | ❌ QA 误判，代码已实现 |
| Run 1 | 2026-02-26 | ⚠️ 阻塞 | `pnpm build:test` spawn EPERM | 环境问题，非代码问题 |

### 已完成功能

| 功能 | 文件 | 状态 |
|------|------|------|
| API 服务（5 个方法） | `src/service/api/user.ts` | ✅ 端点正确 |
| 用户列表页 | `src/views/user/index.vue` | ✅ 待验证 |
| 用户详情抽屉 | `src/views/user/modules/user-detail-drawer.vue` | ✅ 待验证 |
| 路由注册 | `src/router/elegant/routes.ts` | ✅ 已注册 |
| 分页参数 | `pageNum` / `pageSize` | ✅ 与后端一致 |

---

## 开发上下文

### 现有文件清单

| 文件 | 说明 | 行数 |
|------|------|------|
| `src/service/api/user.ts` | API 服务：fetchGetUsers, fetchGetUser, fetchUpdateUserStatus, fetchUpdateUserRole, fetchDeleteUser | ~60 |
| `src/views/user/index.vue` | 列表页：搜索栏 + NDataTable + 分页 + 状态/角色操作 | ~350 |
| `src/views/user/modules/user-detail-drawer.vue` | 详情抽屉：NDescriptions + 关联订单数 | ~120 |
| `src/router/elegant/routes.ts` | 路由配置：`/user` 已注册，icon: `i-carbon-user-multiple` | — |

### API 端点（已确认与 BACKEND-008 一致）

| 方法 | 端点 | 分页参数 | 用途 |
|------|------|---------|------|
| GET | `/auth/admin/users` | `pageNum`, `pageSize`, `keyword`, `status`, `role` | 用户列表 |
| GET | `/auth/admin/users/:id` | — | 用户详情 |
| PUT | `/auth/admin/users/:id/status` | — | 状态切换（body: `{ status }`) |
| PUT | `/auth/admin/users/:id/role` | — | 角色切换（body: `{ role }`） |
| DELETE | `/auth/admin/users/:id` | — | 删除用户 |

### 关键实现细节

**分页 Hook**: 使用 `useNaivePaginatedTable`，通过 `onPaginationParamsChange` 回调更新 `searchParams.value.pageNum`

**角色切换**: `NPopselect` 组件，当前选项为 `[{ label: '管理员', value: 'admin' }, { label: '普通用户', value: 'user' }]`

**关联订单数**: 详情抽屉中优先读 `user.orderCount`，若无则调用 `fetchGetOnlineOrders({ pageNum: 1, pageSize: 1, userId })` 取 `total`

**角色类型**: `fetchUpdateUserRole` 参数类型为 `'user' | 'admin'`（ADMIN-FE-009 会扩展为 `'user' | 'operator' | 'admin'`）

---

## 实施步骤

### Step 1: API 服务验证 — 确认端点和参数

**目标**: 确认 `src/service/api/user.ts` 的 5 个方法端点路径和参数与后端一致

**检查文件**: `src/service/api/user.ts`

**具体操作**:
1. 逐个检查 5 个 API 方法的 URL：
   - `fetchGetUsers` → `GET /auth/admin/users` ✅
   - `fetchGetUser` → `GET /auth/admin/users/:id` ✅
   - `fetchUpdateUserStatus` → `PUT /auth/admin/users/:id/status` ✅
   - `fetchUpdateUserRole` → `PUT /auth/admin/users/:id/role` ✅
   - `fetchDeleteUser` → `DELETE /auth/admin/users/:id` ✅
2. 确认 `UserListParams` 接口包含 `pageNum`、`pageSize`、`keyword`、`status`、`role`
3. 确认 `fetchUpdateUserStatus` 的 body 格式为 `{ status: number }`（0=禁用, 1=启用）
4. 确认 `fetchUpdateUserRole` 的 body 格式为 `{ role: string }`
5. 确认无多余的未使用方法（如 createUser、resetPassword 等应已删除）

**验收**:
- 5 个方法端点全部正确
- 无多余未使用的 API 方法
- TypeScript 类型定义完整

**Checkpoint**: `pnpm typecheck` 通过

---

### Step 2: 列表页功能验证 — 搜索 + 筛选 + 分页

**目标**: 确认列表页数据加载、搜索、筛选、分页全部正常

**检查文件**: `src/views/user/index.vue`

**具体操作**:
1. 确认 `getQueryParams()` 正确组装查询参数：
   - `keyword` 为空时传 `undefined`（不传空字符串）
   - `status` 为空时传 `undefined`
   - `role` 为空时传 `undefined`
2. 确认 `userTableTransform` 正确解析响应：
   ```typescript
   // 后端响应格式
   { list: [...], pageNum: 1, pageSize: 10, total: 100 }
   // transform 后
   { data: list, pageNum, pageSize, total }
   ```
3. 确认分页回调正确更新 `searchParams`：
   ```typescript
   onPaginationParamsChange: ({ page, pageSize }) => {
     searchParams.value.pageNum = page ?? 1;
     searchParams.value.pageSize = pageSize ?? 10;
   }
   ```
4. 确认搜索/重置按钮行为：
   - 搜索：用当前筛选条件 + `pageNum=1` 重新请求
   - 重置：清空所有筛选条件 + `pageNum=1` 重新请求

**验收**:
- 页面加载时自动请求 `GET /auth/admin/users?pageNum=1&pageSize=10`
- keyword 搜索后 pageNum 重置为 1
- status/role 筛选正常
- 翻页正常（pageNum 递增）
- 重置后所有筛选清空

---

### Step 3: 列表页操作验证 — 状态切换 + 角色切换 + 删除

**目标**: 确认表格行内操作全部正常

**检查文件**: `src/views/user/index.vue`

**具体操作**:

**3a. 状态切换（NSwitch）**:
1. 确认 `NSwitch` 的 `value` 绑定为 `row.status === 1`
2. 确认切换时调用 `fetchUpdateUserStatus(row.id, newStatus)`
3. 确认切换成功后刷新列表（调用 `getData()`）
4. 确认切换过程中有 loading 状态（防止重复点击）

**3b. 角色切换（NPopselect）**:
1. 确认 `NPopselect` 的 `value` 绑定为 `row.role`
2. 确认选项为 `[{ label: '管理员', value: 'admin' }, { label: '普通用户', value: 'user' }]`
3. 确认切换时调用 `fetchUpdateUserRole(row.id, newRole)`
4. 确认切换成功后刷新列表
5. 确认有 `roleLoadingIds` 防止重复操作

**3c. 删除（NPopconfirm）**:
1. 确认删除按钮有二次确认弹窗
2. 确认确认后调用 `fetchDeleteUser(row.id)`
3. 确认删除成功后刷新列表
4. 确认不能删除自己（当前登录用户）

**验收**:
- 状态开关切换后，用户状态实际变更（刷新后保持）
- 角色切换后，角色标签更新
- 删除有二次确认，确认后用户从列表消失
- 所有操作有 loading 状态

---

### Step 4: 详情抽屉验证 — 用户信息 + 关联订单数

**目标**: 确认详情抽屉展示完整信息

**检查文件**: `src/views/user/modules/user-detail-drawer.vue`

**具体操作**:
1. 确认抽屉打开时调用 `fetchGetUser(userId)` 获取用户详情
2. 确认展示以下字段（NDescriptions 组件）：
   - 用户名、邮箱、昵称、手机号、头像（NImage）
   - 角色（NTag，admin=success / user=default）
   - 状态（NTag，启用=success / 禁用=error）
   - 关联订单数
   - 注册时间、更新时间（格式化显示）
3. 确认关联订单数获取逻辑：
   ```typescript
   // 优先使用 user.orderCount
   if (typeof user.orderCount === 'number') {
     relatedOrderCount.value = user.orderCount
   } else {
     // 备选：调用订单 API 获取 total
     const res = await fetchGetOnlineOrders({ pageNum: 1, pageSize: 1, userId })
     relatedOrderCount.value = res.data?.total ?? 0
   }
   ```
4. 确认 loading 状态（数据加载中显示 NSpin）
5. 确认头像为空时显示占位符

**验收**:
- 点击"查看详情" → 抽屉打开 → 显示完整用户信息
- 关联订单数正确显示（非 `--`）
- 头像正确显示或显示占位符
- 时间格式化正确

---

### Step 5: 路由和菜单验证

**目标**: 确认路由注册和侧边栏菜单入口正常

**检查文件**: `src/router/elegant/routes.ts`

**具体操作**:
1. 确认路由配置：
   ```typescript
   {
     name: 'user',
     path: '/user',
     component: 'layout.base$view.user',
     meta: {
       title: '用户管理',
       icon: 'i-carbon-user-multiple',
       order: 4
     }
   }
   ```
2. 确认侧边栏菜单显示"用户管理"入口
3. 确认点击菜单能正确导航到 `/user`
4. 确认页面刷新后路由保持

**验收**:
- 侧边栏显示"用户管理"菜单项（带图标）
- 点击菜单 → 导航到用户列表页
- 直接访问 `/user` URL → 正确加载页面
- 页面刷新后保持在用户管理页

---

### Step 6: 全量回归验证

**目标**: 端到端验证完整功能流程

**前置条件**: BACKEND-008 已完成（后端 API 可用）

**操作**:

1. **完整流程测试**:
   - 登录 admin 账户 → 侧边栏看到"用户管理" → 点击进入
   - 列表加载 → 确认有数据（Network: `GET /auth/admin/users?pageNum=1&pageSize=10` → 200）
   - keyword 搜索 → 结果过滤正确
   - status 筛选 → 结果过滤正确
   - role 筛选 → 结果过滤正确
   - 翻页 → 数据切换
   - 状态切换 → 成功（Network: `PUT /auth/admin/users/:id/status` → 200）
   - 角色切换 → 成功（Network: `PUT /auth/admin/users/:id/role` → 200）
   - 查看详情 → 抽屉打开，信息完整
   - 删除用户 → 二次确认 → 成功（Network: `DELETE /auth/admin/users/:id` → 200）

2. **TypeScript 检查**:
   - `pnpm typecheck` 通过

3. **边界场景**:
   - 空列表（无匹配结果）→ 显示空状态
   - 网络错误 → 错误提示
   - 快速连续操作 → loading 状态防止重复

**验收**:
- 完整流程无报错
- `pnpm typecheck` 通过
- 无 console 错误

---

## 验收标准

| # | 标准 | 对应 Step |
|---|------|-----------|
| 1 | API 端点路径全部为 `/auth/admin/users` 前缀 | Step 1 |
| 2 | 分页参数为 `pageNum`/`pageSize`（与后端一致） | Step 1 |
| 3 | 列表加载、搜索、筛选、分页正常 | Step 2 |
| 4 | 状态切换、角色切换、删除操作正常 | Step 3 |
| 5 | 详情抽屉展示完整信息（含关联订单数） | Step 4 |
| 6 | 路由和菜单入口正常 | Step 5 |
| 7 | `pnpm typecheck` 通过 | Step 6 |
| 8 | 端到端流程无报错 | Step 6 |

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| BACKEND-008 未完成导致 API 不可用 | 先完成 BACKEND-008（Cart.ts 修复）再验证 |
| 关联订单数 API 调用可能失败 | 已有 fallback 逻辑（try-catch + 默认值） |
| `pnpm build:test` spawn EPERM | 环境问题，不阻塞功能验证，可跳过 |
| 角色类型后续需扩展 operator | ADMIN-FE-009 负责，本任务保持 user/admin |

---

## 与 ADMIN-FE-009 的关系

本任务完成后，ADMIN-FE-009 会在此基础上：
1. 登录门禁 — 拒绝 user 角色登录管理后台
2. 路由 `meta.roles` — 用户管理设为 `roles: ['admin']`
3. 角色选择器 — 添加 `operator` 选项
4. `fetchUpdateUserRole` 类型扩展 — `'user' | 'operator' | 'admin'`

**本任务不需要处理 operator 相关内容。**

---

**相关文档:**
- [Auth API 文档](../../02-api/auth.md)
- [项目状态](../../04-projects/moxton-lotadmin.md)
- [前置任务: BACKEND-008](../active/backend/BACKEND-008-admin-user-management-api.md)
- [后续任务: ADMIN-FE-009](./ADMIN-FE-009-role-based-access-control.md)
