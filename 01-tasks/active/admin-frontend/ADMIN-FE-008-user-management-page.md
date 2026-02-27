# Tech-Spec: 用户管理页面

**创建时间:** 2026-02-26
**状态:** 准备开发
**角色:** CRUD前端工程师
**项目:** moxton-lotadmin
**优先级:** P1
**技术栈:** Vue 3 + TypeScript + SoybeanAdmin + Naive UI
**前置依赖:** BACKEND-008

---

## 概述

### 问题陈述

管理后台缺少用户管理模块。`src/service/api/user.ts` 已定义 API 方法，但端点路径与后端不匹配（前端调 `/admin/users`，后端将改为 `/auth/admin/users`），且没有对应的页面和路由。

### 解决方案

修正 API 路径，新增用户管理页面（列表 + 详情抽屉），注册路由。

### 范围 (包含/排除)

**包含:**
- 修正 `src/service/api/user.ts` 端点路径
- 用户列表页（表格 + 搜索 + 状态筛选 + 分页）
- 用户详情抽屉（查看资料 + 关联订单数）
- 状态开关（启用/停用）
- 角色切换（user/admin）
- 路由注册

**不包含:**
- 管理员创建用户
- 批量操作
- 用户统计仪表盘

---

## 开发上下文

### 现有实现

| 文件 | 说明 |
|------|------|
| `src/service/api/user.ts` | 已定义 9 个 API 方法，路径需修正 |
| `src/service/api/auth.ts` | 认证 API（登录、获取用户信息） |
| `src/views/online-order/` | 可参考的列表页实现模式 |
| `src/router/elegant/routes.ts` | 路由配置 |

### 依赖项

- BACKEND-008 完成后端 API 重构
- Naive UI 组件：NDataTable, NInput, NSelect, NSwitch, NDrawer, NTag, NPagination

---

## 技术方案

### 页面结构

```
src/views/user/
├── index.vue              # 用户列表页
└── modules/
    └── user-detail-drawer.vue  # 用户详情抽屉
```

### 用户列表页功能

- 搜索栏：keyword 输入框 + status 下拉 + role 下拉 + 搜索/重置按钮
- 表格列：用户名、邮箱、昵称、角色（Tag）、状态（Switch）、注册时间、操作
- 操作列：查看详情、角色切换、删除（二次确认）
- 分页：底部分页器

### 数据流

```
页面加载 → fetchGetUsers(params) → 渲染表格
状态切换 → fetchUpdateUserStatus(id, status) → 刷新列表
角色切换 → fetchUpdateUserRole(id, role) → 刷新列表
查看详情 → fetchGetUser(id) → 打开抽屉
删除 → NPopconfirm 确认 → fetchDeleteUser(id) → 刷新列表
```

### API 调用

修正后的端点路径：

| 方法 | 端点 | 用途 |
|------|------|------|
| GET | `/auth/admin/users` | 用户列表 |
| GET | `/auth/admin/users/:id` | 用户详情 |
| PUT | `/auth/admin/users/:id/status` | 状态切换 |
| PUT | `/auth/admin/users/:id/role` | 角色切换 |
| DELETE | `/auth/admin/users/:id` | 删除用户 |

---

## 实施步骤

1. 修正 `src/service/api/user.ts` 中所有端点路径为 `/auth/admin/users` 前缀
2. 移除不需要的 API 方法（createUser、resetPassword、batchUpdateStatus、statistics）
3. 新增 `fetchUpdateUserRole` 方法
4. 创建 `src/views/user/index.vue` 列表页
5. 创建 `src/views/user/modules/user-detail-drawer.vue` 详情抽屉
6. 在路由配置中注册 `/user` 路由
7. 在侧边栏菜单中添加"用户管理"入口

---

## 验收标准

- [ ] API 路径与后端 BACKEND-008 一致
- [ ] 用户列表正常加载，支持分页
- [ ] keyword 搜索、status 筛选、role 筛选正常工作
- [ ] 状态开关可切换用户启用/停用
- [ ] 角色可在 user/admin 之间切换
- [ ] 详情抽屉展示用户完整信息
- [ ] 删除操作有二次确认弹窗
- [ ] 侧边栏菜单可见"用户管理"入口

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 后端 API 未就绪 | 等待 BACKEND-008 完成后再开发 |
| Soybean Admin 路由注册方式特殊 | 参考现有 online-order 模块的注册方式 |

---

**相关文档:**
- [API 文档](../../02-api/auth.md)
- [项目状态](../../04-projects/moxton-lotadmin.md)
- [前置任务: BACKEND-008](../active/backend/BACKEND-008-admin-user-management-api.md)
