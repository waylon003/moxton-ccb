# Tech-Spec: 登录注册认证 — UI 规范化 + API 修复

**创建时间:** 2026-02-26
**最后更新:** 2026-02-27
**状态:** 待修复
**角色:** 独立站前端工程师
**项目:** nuxt-moxton
**优先级:** P1
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia + Reka UI + UnoCSS
**前置依赖:** BACKEND-009（已完成）

---

## 概述

### 问题陈述

登录/注册/认证的核心功能已实现（auth store、登录页、注册页、Header 集成、路由守卫），但存在以下问题：
1. 登出只做本地清理，未调用后端 `POST /auth/logout`
2. 登录/注册页面 UI 使用原生 HTML input/button，未使用项目封装的 Reka UI 组件（`MaterialInput`、`GradientButton` 等）
3. auth composable 缺少 `changePassword` 方法（password.vue 直接调 apiClient）

### 解决方案

修复 API 调用问题，将登录/注册页面 UI 重构为使用 `components/ui/` 封装组件。

### 范围

**包含:**
- 登出流程调用后端 API
- 登录/注册页面 UI 重构（使用 MaterialInput + GradientButton）
- auth composable 补全 changePassword 方法

**不包含:**
- 个人中心页面（SHOP-FE-003）
- 第三方登录
- 忘记密码

---

## 当前进度

> **核心功能已实现，需要 UI 规范化和 API 修复。**

### 已完成功能

| 功能 | 文件 | 状态 |
|------|------|------|
| Auth Store（token 持久化、登录/登出/注册） | `stores/auth.ts` | ✅ |
| 登录页面 | `pages/login.vue` | ⚠️ UI 需重构 |
| 注册页面 | `pages/register.vue` | ⚠️ UI 需重构 |
| Header 用户菜单 | `components/layout/` | ✅ |
| 路由守卫 | `middleware/auth.ts` | ✅ |
| 登录后购物车合并 | `stores/auth.ts` → `cart.merge` | ✅ |
| Auth API composable | `composables/api/auth.ts` | ⚠️ 缺 changePassword |

---

## 开发上下文

### 可用 UI 组件（必须使用）

| 组件 | 路径 | 用途 |
|------|------|------|
| `MaterialInput` | `components/ui/MaterialInput.vue` | 浮动标签输入框，支持错误提示、图标 |
| `GradientButton` | `components/ui/GradientButton.vue` | 渐变按钮，支持 primary/secondary/outline/ghost + loading |
| `MaterialSelect` | `components/ui/MaterialSelect.vue` | 下拉选择器 |

### UnoCSS 主题色

```
primary: #FF6B35（橙色）
success: #2C8A4B  error: #D93A2F  warning: #C97A00  info: #3667D6
```

### API 端点（后端已确认）

| 方法 | 端点 | 用途 |
|------|------|------|
| POST | `/auth/login` | 登录（username/email + password） |
| POST | `/auth/register` | 注册（username + email + password） |
| GET | `/auth/profile` | 获取用户信息 |
| POST | `/auth/logout` | 登出（后端清理 session） |
| PUT | `/auth/password` | 修改密码（currentPassword + newPassword） |
| POST | `/cart/merge` | 合并游客购物车 |

---

## 实施步骤

### Step 1: 修复登出流程 — 调用后端 API

**目标**: 登出时调用 `POST /auth/logout`，而不是只做本地清理

**修改文件**: `stores/auth.ts`

**具体操作**:
1. 找到 `logout` action
2. 在清除本地 token/user 之前，先调用后端登出：
   ```typescript
   async function logout() {
     try {
       await apiClient.post('/auth/logout')
     } catch {
       // 登出失败不阻塞，继续清理本地状态
     }
     // 清除 localStorage
     localStorage.removeItem('auth_token')
     localStorage.removeItem('user_info')
     // 重置 state
     token.value = null
     user.value = null
   }
   ```
3. 后端登出失败时静默处理（不影响用户体验）

**验收**:
- 点击登出 → 后端收到 `POST /auth/logout` 请求
- 后端不可达时 → 登出仍然正常（本地清理完成）
- 登出后 Header 恢复为登录按钮

---

### Step 2: auth composable 补全 changePassword

**目标**: 在 auth API composable 中添加修改密码方法

**修改文件**: `composables/api/auth.ts`

**具体操作**:
1. 新增 `changePassword` 方法：
   ```typescript
   changePassword: async (currentPassword: string, newPassword: string) => {
     return await apiClient.put('/auth/password', {
       currentPassword,
       newPassword
     })
   }
   ```
2. 确认 `password.vue` 页面改为调用此方法（而非直接调 apiClient）

**验收**:
- `composables/api/auth.ts` 导出 `changePassword` 方法
- `pages/account/password.vue` 通过 auth composable 调用（不直接用 apiClient）

---

### Step 3: 登录页 UI 重构

**目标**: `pages/login.vue` 使用 MaterialInput + GradientButton 替换原生 HTML

**修改文件**: `pages/login.vue`

**具体操作**:
1. 将所有 `<input>` 替换为 `<MaterialInput>`：
   - 用户名/邮箱输入框：`<MaterialInput v-model="form.username" label="用户名或邮箱" :error="errors.username" />`
   - 密码输入框：`<MaterialInput v-model="form.password" label="密码" type="password" :error="errors.password" />`
2. 将提交按钮替换为 `<GradientButton>`：
   - `<GradientButton variant="primary" :loading="isLoading" @click="handleLogin">登录</GradientButton>`
3. 将"去注册"链接按钮替换为 `<GradientButton variant="ghost">`
4. 保持现有表单验证逻辑不变
5. 使用 UnoCSS 原子类做布局（flex、spacing、typography）

**UI 规范**:
- 表单容器：`max-w-md mx-auto mt-20`
- 输入框间距：`space-y-4`
- 按钮宽度：`w-full`
- 错误提示：MaterialInput 内置 `:error` prop

**验收**:
- 登录页使用 MaterialInput（浮动标签效果）
- 登录按钮使用 GradientButton（渐变 + loading 状态）
- 表单验证错误显示在输入框下方
- 视觉风格与项目主题一致（primary: #FF6B35）
- 登录功能正常（不引入回归）

---

### Step 4: 注册页 UI 重构

**目标**: `pages/register.vue` 使用 MaterialInput + GradientButton

**修改文件**: `pages/register.vue`

**具体操作**:
1. 将所有 `<input>` 替换为 `<MaterialInput>`：
   - 用户名：`<MaterialInput v-model="form.username" label="用户名" :error="errors.username" />`
   - 邮箱：`<MaterialInput v-model="form.email" label="邮箱" type="email" :error="errors.email" />`
   - 密码：`<MaterialInput v-model="form.password" label="密码" type="password" :error="errors.password" />`
   - 确认密码：`<MaterialInput v-model="form.confirmPassword" label="确认密码" type="password" :error="errors.confirmPassword" />`
2. 提交按钮：`<GradientButton variant="primary" :loading="isLoading">注册</GradientButton>`
3. "去登录"链接：`<GradientButton variant="ghost">`
4. 保持现有验证逻辑

**验收**:
- 注册页使用 MaterialInput + GradientButton
- 表单验证正常（用户名必填、邮箱格式、密码长度、确认密码一致）
- 注册成功后跳转正常
- 409 重复用户名/邮箱显示友好错误

---

### Step 5: 回归验证

**目标**: 确认所有认证流程正常

**操作**:
1. 登录流程：输入用户名+密码 → 登录成功 → Header 显示用户信息 → 购物车合并
2. 注册流程：填写表单 → 注册成功 → 自动登录 → 跳转首页
3. 登出流程：点击登出 → 后端收到请求 → 本地清理 → Header 恢复
4. 路由守卫：未登录访问 /account → 重定向 /login
5. 页面刷新：登录状态保持
6. 表单验证：空字段、格式错误、重复注册

**验收**:
- 6 个场景全部通过
- 无 console 错误
- UI 风格统一（MaterialInput + GradientButton + UnoCSS）

---

## 验收标准

| # | 标准 | 对应 Step |
|---|------|-----------|
| 1 | 登出调用后端 API，失败时静默处理 | Step 1 |
| 2 | auth composable 导出 changePassword 方法 | Step 2 |
| 3 | 登录页使用 MaterialInput + GradientButton | Step 3 |
| 4 | 注册页使用 MaterialInput + GradientButton | Step 4 |
| 5 | 所有认证流程回归通过 | Step 5 |

---

## UI 组件使用规范（强制）

**本任务及所有后续 SHOP-FE 任务必须遵守：**

| 场景 | 必须使用 | 禁止使用 |
|------|---------|---------|
| 文本输入 | `<MaterialInput>` | `<input type="text">` |
| 密码输入 | `<MaterialInput type="password">` | `<input type="password">` |
| 下拉选择 | `<MaterialSelect>` | `<select>` |
| 多行文本 | `<MaterialTextarea>` | `<textarea>` |
| 按钮 | `<GradientButton>` | `<button>` |
| 复选框 | `<CartCheckbox>` | `<input type="checkbox">` |
| 弹出菜单 | `<MaterialDropdown>` | 自定义 dropdown |
| 样式 | UnoCSS 原子类 | 内联 style / scoped CSS |

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| MaterialInput 的 v-model 行为与原生 input 不同 | 先读取组件源码确认 props/events |
| GradientButton 的 loading 状态实现 | 确认 :loading prop 是否存在 |
| UI 重构可能破坏表单验证 | 保持验证逻辑不变，只替换模板层 |

---

**相关文档:**
- [Auth API 文档](../../02-api/auth.md)
- [Cart API 文档](../../02-api/cart.md)
- [项目状态](../../04-projects/nuxt-moxton.md)
- [前置任务: BACKEND-009](../../01-tasks/completed/backend/BACKEND-009-auth-api-normalization.md)
