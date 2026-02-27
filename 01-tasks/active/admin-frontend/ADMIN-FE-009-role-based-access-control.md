# Tech-Spec: 角色门禁 + 菜单权限过滤

**创建时间:** 2026-02-27
**状态:** 待开发
**角色:** 管理后台前端工程师
**项目:** moxton-lotadmin
**优先级:** P0
**技术栈:** Vue 3 + TypeScript + Soybean Admin + Naive UI
**前置依赖:** BACKEND-010（后端角色系统扩展）

---

## 概述

### 问题陈述

管理后台当前没有角色门禁。任何持有合法 token 的用户（包括 `user` 角色的顾客）都能登录管理后台并看到所有菜单。需要：
1. 登录时拦截 `user` 角色，禁止顾客进入管理后台
2. `operator` 角色只能看到商品+分类+订单相关菜单
3. `admin` 角色看到所有菜单

### 解决方案

利用 Soybean Admin 内置的角色过滤机制：
- 登录后检查 `getUserInfo` 返回的 roles，`user` 角色直接拒绝
- 在路由 `meta.roles` 中声明每个路由允许的角色
- Soybean Admin 的 `filterAuthRoutesByRoles` 自动过滤菜单

### 范围

**包含:**
- 登录流程增加角色门禁（拒绝 user 角色）
- 所有路由配置 `meta.roles`
- 用户管理页面角色选择器增加 `operator` 选项

**不包含:**
- 按钮级权限控制（后续迭代）
- 动态路由模式（保持 static 模式）
- 后端权限控制（BACKEND-010 负责）

---

## 开发上下文

### Soybean Admin 角色机制（已内置）

**关键配置** (`.env`):
```
VITE_AUTH_ROUTE_MODE=static
VITE_STATIC_SUPER_ROLE=admin
```

**角色过滤流程**:
```
登录 → getUserInfo → roles: ["operator"]
  ↓
initStaticAuthRoute()
  ↓
filterAuthRoutesByRoles(routes, ["operator"])
  ↓
只保留 meta.roles 包含 "operator" 或 meta.roles 为空的路由
  ↓
生成菜单（自动只显示有权限的项）
```

**超级角色**: `admin` 绕过所有 roles 检查，看到全部路由。

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/store/modules/auth/index.ts` | 修改 | 登录流程增加角色门禁 |
| `src/router/routes/index.ts` 或 `src/router/elegant/routes.ts` | 修改 | 路由 meta.roles 配置 |
| `src/views/user/index.vue` | 修改 | 角色选择器增加 operator |
| `src/views/user/modules/user-detail-drawer.vue` | 修改 | 详情抽屉显示 operator |
| `src/typings/api.d.ts` | 检查 | 确认 roles 类型定义兼容 operator |

---

## 技术方案

### 角色 → 可见菜单矩阵

| 菜单项 | 路由 | user | operator | admin |
|--------|------|------|----------|-------|
| 首页 | `/home` | ❌ 禁止登录 | ✅ | ✅ |
| 商品管理 | `/product` | — | ✅ | ✅ |
| 分类管理 | `/category` | — | ✅ | ✅ |
| 在线订单 | `/online-order` | — | ✅ | ✅ |
| 咨询订单 | `/consultation-order` | — | ✅ | ✅ |
| 用户管理 | `/user` | — | ❌ | ✅ |

### 登录门禁逻辑

```typescript
// src/store/modules/auth/index.ts — loginByToken() 中
const userInfo = await fetchGetUserInfo();

// 角色门禁：user 角色禁止登录管理后台
if (userInfo.roles.includes('user')) {
  // 清除 token
  clearAuthStorage();
  // 显示错误提示
  window.$message?.error('该账户无管理后台访问权限');
  return false;
}
```

### 路由 roles 配置

```typescript
// 方案：只需要给 admin 专属路由加 roles: ['admin']
// 其他路由不设 roles（operator 和 admin 都能看到）
// 因为 admin 是 VITE_STATIC_SUPER_ROLE，自动绕过 roles 检查

{
  name: 'user',
  path: '/user',
  meta: {
    title: '用户管理',
    roles: ['admin']  // 只有 admin 可见
  }
}

// 商品、分类、订单等路由不设 roles → operator 和 admin 都可见
{
  name: 'product',
  path: '/product',
  meta: {
    title: '商品管理'
    // 无 roles → 所有已登录用户可见（user 已被登录门禁拦截）
  }
}
```

**为什么这样设计**：
- `admin` 是 `VITE_STATIC_SUPER_ROLE`，自动绕过所有 roles 检查
- `user` 已被登录门禁拦截，不会进入路由系统
- 所以只需要区分 `operator` 和 `admin`
- 只给 admin 专属页面（用户管理）加 `roles: ['admin']`
- 其他页面不设 roles，operator 和 admin 都能看到
- 最小改动，最大效果

---

## 实施步骤

### Step 1: 登录门禁 — 拒绝 user 角色

**目标**: user 角色登录管理后台时，显示错误提示并阻止进入

**修改文件**: `src/store/modules/auth/index.ts`

**具体操作**:
1. 找到 `loginByToken` 方法（或登录成功后获取 userInfo 的位置）
2. 在 `fetchGetUserInfo()` 成功返回后，检查 `userInfo.roles`
3. 如果 roles 包含 `'user'`（且不包含 `'admin'` 或 `'operator'`）：
   - 清除已保存的 token（调用 `clearAuthStorage()` 或等效方法）
   - 显示错误提示：`window.$message?.error('该账户无管理后台访问权限')`
   - 返回 false / 跳转回登录页
4. 否则正常继续

**验收**:
- user 账户登录 → 看到"该账户无管理后台访问权限"提示，停留在登录页
- operator 账户登录 → 正常进入首页
- admin 账户登录 → 正常进入首页

**Checkpoint**: 用 user/operator/admin 三个账户分别测试登录

---

### Step 2: 路由 roles 配置 — 用户管理设为 admin 专属

**目标**: 用户管理页面只有 admin 可见，operator 看不到

**修改文件**: 路由配置文件（需确认实际位置）

Soybean Admin 的路由配置可能在以下位置之一：
- `src/router/routes/index.ts`
- `src/router/elegant/routes.ts`（自动生成）
- `src/router/elegant/transform.ts`
- 或通过页面文件的 `definePage` 宏定义

**具体操作**:
1. 先确认路由配置方式：
   - 如果使用 elegant-router 自动生成：在页面文件中用 `definePage({ meta: { roles: ['admin'] } })`
   - 如果手动配置：在路由文件中添加 `meta.roles`
2. 给用户管理路由添加 `roles: ['admin']`：
   ```typescript
   {
     name: 'user',
     path: '/user',
     meta: {
       title: '用户管理',
       roles: ['admin']
     }
   }
   ```
3. 其他路由（product, category, online-order, consultation-order, home）不设 roles

**验收**:
- operator 登录 → 侧边菜单不显示"用户管理"
- admin 登录 → 侧边菜单显示所有项（含"用户管理"）
- operator 直接访问 `/user` URL → 跳转 403 页面

**Checkpoint**: 分别用 operator 和 admin 登录，截图对比菜单

---

### Step 3: 用户管理 — 角色选择器增加 operator

**目标**: 管理员在用户管理页面可以将用户角色设为 operator

**修改文件**:
- `src/views/user/index.vue`（角色筛选下拉 + 角色切换组件）
- `src/views/user/modules/user-detail-drawer.vue`（详情抽屉角色显示）

**具体操作**:
1. 找到角色筛选下拉框的选项列表，添加 `{ label: '运营人员', value: 'operator' }`
2. 找到角色切换组件（NPopselect 或类似），添加 operator 选项
3. 找到角色显示的映射/格式化函数，添加 operator 的中文映射：
   ```typescript
   const roleMap = {
     user: '普通用户',
     operator: '运营人员',
     admin: '管理员'
   };
   ```
4. 详情抽屉中角色显示也需要支持 operator
5. 角色标签颜色（如有）：为 operator 分配一个区分色（如蓝色）

**验收**:
- 用户列表角色筛选下拉有三个选项：普通用户 / 运营人员 / 管理员
- 可以将用户角色切换为"运营人员"
- 用户详情抽屉正确显示"运营人员"角色
- 角色标签颜色区分正确

---

### Step 4: 登录页测试账号更新

**目标**: 登录页的预设测试账号反映新角色体系

**修改文件**: `src/views/_builtin/login/modules/pwd-login.vue`

**具体操作**:
1. 找到硬编码的测试账号区域
2. 更新或添加说明文字：
   - 管理员：admin / admin123
   - 运营人员：（需要先通过 admin 创建一个 operator 账户）
   - 普通用户：demouser / demo123（会被拒绝登录）
3. 如果有账号快捷切换按钮，确保 user 账号按钮点击后能看到拒绝提示

**验收**:
- 登录页信息准确
- 点击 demouser 快捷登录 → 显示权限不足提示

---

### Step 5: 全量验证

**目标**: 三种角色的完整登录 + 菜单 + 操作验证

**操作**:

1. **user 角色测试**:
   - 登录 → 被拒绝，提示"无管理后台访问权限"
   - 不能进入任何管理页面

2. **operator 角色测试**:
   - 登录 → 成功进入首页
   - 侧边菜单：✅ 首页、商品管理、分类管理、在线订单、咨询订单
   - 侧边菜单：❌ 用户管理不可见
   - 直接访问 `/user` → 403 页面
   - 商品 CRUD 操作正常
   - 订单管理操作正常

3. **admin 角色测试**:
   - 登录 → 成功进入首页
   - 侧边菜单：所有项可见（含用户管理）
   - 用户管理：可以看到 operator 角色选项
   - 可以将用户角色切换为 operator
   - 所有功能正常

**验收**:
- 三种角色行为完全符合权限矩阵
- 无 console 错误
- 无 UI 异常

---

## 验收标准

| # | 标准 | 对应 Step |
|---|------|-----------|
| 1 | user 角色登录被拒绝，显示友好提示 | Step 1 |
| 2 | operator 登录成功，看不到用户管理菜单 | Step 2 |
| 3 | admin 登录成功，看到所有菜单 | Step 2 |
| 4 | operator 直接访问 /user → 403 | Step 2 |
| 5 | 用户管理支持 operator 角色选项 | Step 3 |
| 6 | 角色显示正确（中文映射 + 标签颜色） | Step 3 |
| 7 | 三种角色全量验证通过 | Step 5 |

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| Soybean Admin 路由配置方式不确定 | Step 2 要求先确认配置方式再修改 |
| elegant-router 自动生成覆盖手动修改 | 优先使用 definePage 宏或配置文件，不直接改生成文件 |
| operator 角色在后端未就绪 | 前置依赖 BACKEND-010，需先完成后端 |
| 登录门禁逻辑位置不确定 | Worker 需先读取 auth store 完整代码确认 |

---

## 前置条件

在开始此任务前，必须确认：
1. BACKEND-010 已完成 — 后端支持 operator 角色
2. 数据库中已有至少一个 operator 角色的测试账户
3. `GET /auth/getUserInfo` 对 operator 返回 `roles: ["operator"]`

---

**相关文档:**
- [Auth API 文档](../../02-api/auth.md)
- [项目状态](../../04-projects/moxton-lotadmin.md)
- [前置任务: BACKEND-010](../active/backend/BACKEND-010-role-system-operator.md)
