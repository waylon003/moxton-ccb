# Tech-Spec: 登录注册页面 + 认证状态管理

**创建时间:** 2026-02-26
**状态:** 准备开发
**角色:** 独立站前端工程师
**项目:** nuxt-moxton
**优先级:** P1
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia
**前置依赖:** BACKEND-009

---

## 概述

### 问题陈述

商城前端目前没有登录/注册页面，没有 auth store，用户无法登录。`composables/api/auth.ts` 已有基础 API 方法，但缺少状态管理和 UI 层。

### 解决方案

新增 auth store、登录/注册独立页面、Header 登录状态集成、路由守卫。

### 范围 (包含/排除)

**包含:**
- `stores/auth.ts` — token 持久化、用户状态、登录/登出 action
- `/pages/login.vue` — 登录页面（用户名或邮箱 + 密码）
- `/pages/register.vue` — 注册页面（用户名 + 邮箱 + 密码）
- Header 组件集成（游客→登录按钮，已登录→用户头像/下拉菜单）
- 登录后自动合并游客购物车（调 `/cart/merge`）
- 路由中间件（个人中心页需登录）

**不包含:**
- 个人中心页面（SHOP-FE-003）
- 第三方登录
- 忘记密码

---

## 开发上下文

### 现有实现

| 文件 | 说明 |
|------|------|
| `composables/api/auth.ts` | login, getCurrentUser, updateProfile, logout, isAuthenticated 等方法 |
| `stores/cart.ts` | 购物车 store，含游客 ID 管理 |
| `stores/` | 无 auth.ts |
| `pages/` | 无 login/register 页面 |

### 依赖项

- Pinia 3.0.4（已安装）
- `composables/api/auth.ts`（已有 API 方法）
- `stores/cart.ts`（登录后需调用购物车合并）
- BACKEND-009（auth 接口规范化）

---

## 技术方案

### 架构设计

```
stores/auth.ts          # 认证状态管理
├── state: user, token, isLoggedIn
├── actions: login, register, logout, fetchUser
└── 持久化: localStorage (token)

middleware/auth.ts       # 路由守卫
└── 未登录访问 /account → 重定向 /login

pages/
├── login.vue           # 登录页
└── register.vue        # 注册页

components/
└── layout/UserMenu.vue # Header 用户菜单（登录按钮 / 用户头像下拉）
```

### 数据流

```
登录流程:
用户输入 → auth.login(credentials) → API /auth/login → 存 token → fetchUser → cart.merge → 跳转首页

注册流程:
用户输入 → API /auth/register → 存 token → fetchUser → 跳转首页

页面刷新:
读 localStorage token → fetchUser → 恢复登录状态

登出:
清除 token + user → 跳转首页
```

### API 调用

| 方法 | 端点 | 用途 |
|------|------|------|
| POST | `/auth/login` | 登录 |
| POST | `/auth/register` | 注册 |
| GET | `/auth/profile` | 获取用户信息 |
| POST | `/auth/logout` | 登出 |
| POST | `/cart/merge` | 合并游客购物车 |

---

## 实施步骤

1. 创建 `stores/auth.ts`（state、actions、localStorage 持久化）
2. 创建 `middleware/auth.ts` 路由守卫
3. 创建 `/pages/login.vue` 登录页面
4. 创建 `/pages/register.vue` 注册页面
5. 修改 Header 组件，集成 UserMenu（登录状态切换）
6. 在 login action 中集成购物车合并逻辑
7. 测试完整登录/注册/登出流程

---

## 验收标准

- [ ] 登录页面可正常登录（用户名或邮箱 + 密码）
- [ ] 注册页面可正常注册
- [ ] 注册重复用户名/邮箱显示友好错误提示（对接 409）
- [ ] 登录后 Header 显示用户信息/头像
- [ ] 登出后 Header 恢复为登录按钮
- [ ] 页面刷新后登录状态保持
- [ ] 登录后游客购物车自动合并
- [ ] 未登录访问 /account 重定向到 /login

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| auth.ts composable 已有部分逻辑 | store 复用 composable 中的 API 方法，不重复实现 |
| 购物车合并失败 | merge 失败不阻塞登录流程，静默处理 |

---

**相关文档:**
- [Auth API 文档](../../02-api/auth.md)
- [Cart API 文档](../../02-api/cart.md)
- [项目状态](../../04-projects/nuxt-moxton.md)
- [前置任务: BACKEND-009](../active/backend/BACKEND-009-auth-api-normalization.md)
