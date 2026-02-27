# Tech-Spec: 个人中心 — API 联调修复 + UI 规范化

**创建时间:** 2026-02-26
**最后更新:** 2026-02-27
**状态:** 待修复
**角色:** 独立站前端工程师
**项目:** nuxt-moxton
**优先级:** P1
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia + Reka UI + UnoCSS
**前置依赖:** SHOP-FE-002

---

## 概述

### 问题陈述

个人中心页面框架和子页面已存在，但存在严重问题：
1. **API 端点全部错误** — 订单列表调 `GET /orders`（应为 `/orders/user`），咨询列表调 `GET /offline-orders`（应为 `/offline-orders/user`）
2. **分页参数名错误** — 前端发送 `page`，后端期望 `pageNum`
3. **头像上传未实现** — 后端已有 `POST /upload/single`，前端 profile 页面只能手动输入 URL
4. **UI 全部原生 HTML** — 所有页面使用 `<input>`/`<button>`/`<select>`，未使用 `components/ui/` 封装的 Reka UI 组件
5. ~~**咨询订单响应格式不匹配**~~ — 已确认后端分页格式与订单一致（扁平结构），无需特殊处理

### 解决方案

逐页修复 API 调用 + UI 重构为 Reka UI 组件。按子页面拆分为独立 Step，每个 Step 可独立验收。

### 范围

**包含:**
- 修复所有 API 端点和参数名
- 所有页面 UI 重构为 MaterialInput + GradientButton + UnoCSS
- 实现头像上传（使用 /upload/single）
- ~~修复咨询订单响应解析~~ — 已确认格式与订单一致，无需特殊处理

**不包含:**
- 通知中心（后续迭代）
- 订单取消/退款操作
- 头像裁剪（直接上传原图）

---

## 当前进度

> **页面框架已存在，但 API 联调全部失败，UI 不符合规范。**

### 已知问题清单

| # | 问题 | 严重度 | 涉及文件 |
|---|------|--------|---------|
| 1 | 订单列表端点错误：`GET /orders` → 应为 `GET /orders/user` | 🔴 致命 | `composables/api/orders.ts` |
| 2 | 订单列表参数错误：`page` → 应为 `pageNum` | 🔴 致命 | `composables/api/orders.ts` |
| 3 | 咨询列表端点错误：`GET /offline-orders` → 应为 `GET /offline-orders/user` | 🔴 致命 | `composables/api/offline-orders.ts` |
| 4 | 咨询列表参数错误：`page` → 应为 `pageNum` | 🔴 致命 | `composables/api/offline-orders.ts` |
| 5 | ~~咨询列表响应格式不匹配~~ — 已确认与订单格式一致，无此问题 | ~~🟡 中等~~ 已排除 | `pages/account/consultations.vue` |
| 6 | 头像上传未实现 | 🟡 中等 | `pages/account/profile.vue` |
| 7 | 所有页面使用原生 HTML，未用 Reka UI 组件 | 🟡 中等 | 所有 account 页面 |

---

## 开发上下文

### 可用 UI 组件（强制使用）

| 组件 | 路径 | 用途 |
|------|------|------|
| `MaterialInput` | `components/ui/MaterialInput.vue` | 浮动标签输入框（文本、密码、邮箱） |
| `GradientButton` | `components/ui/GradientButton.vue` | 按钮（primary/secondary/outline/ghost + loading） |
| `MaterialSelect` | `components/ui/MaterialSelect.vue` | 下拉选择器 |
| `MaterialTextarea` | `components/ui/MaterialTextarea.vue` | 多行文本框 |
| `MaterialDropdown` | `components/ui/MaterialDropdown.vue` | 弹出菜单 |
| `CartCheckbox` | `components/ui/CartCheckbox.vue` | 复选框 |

### 后端 API 端点（已确认）

| 功能 | 方法 | 端点 | 分页参数 | 响应分页格式 |
|------|------|------|---------|-------------|
| 用户资料 | GET | `/auth/profile` | — | 单对象 |
| 更新资料 | PUT | `/auth/profile` | — | 单对象 |
| 修改密码 | PUT | `/auth/password` | — | — |
| 订单列表 | GET | `/orders/user` | `pageNum`, `pageSize`, `status` | `{ list, total, pageNum, pageSize, totalPages }` |
| 订单详情 | GET | `/orders/:id` | — | 单对象（OrderResponseDTO） |
| 地址列表 | GET | `/addresses` | — | 数组 |
| 创建地址 | POST | `/addresses` | — | 单对象 |
| 更新地址 | PUT | `/addresses/:id` | — | 单对象 |
| 删除地址 | DELETE | `/addresses/:id` | — | — |
| 默认地址 | PUT | `/addresses/:id/default` | — | 单对象 |
| 咨询列表 | GET | `/offline-orders/user` | `pageNum`, `pageSize`, `status` | `{ list, total, pageNum, pageSize, totalPages }` |
| 文件上传 | POST | `/upload/single` | — | `{ url, fileName, originalName, size, mimeType }` |

### UnoCSS 主题色

```
primary: #FF6B35  success: #2C8A4B  error: #D93A2F  warning: #C97A00  info: #3667D6
```

---

## 实施步骤

### Step 1: 修复订单 API composable — 端点 + 分页参数

**目标**: 订单列表能正确获取当前用户的订单数据

**修改文件**: `composables/api/orders.ts`

**具体操作**:
1. 找到获取订单列表的函数（如 `getOrders` / `fetchOrders`）
2. 修复端点：`/orders` → `/orders/user`
3. 修复分页参数名：`page` → `pageNum`
4. 确认 `pageSize` 参数名正确（后端也叫 `pageSize`）
5. 确认 `status` 筛选参数传递正确
6. 确认响应解析匹配后端格式：`{ list, total, pageNum, pageSize, totalPages }`

**代码示例**:
```typescript
// 修复前
const getOrders = (params: { page: number; pageSize: number; status?: string }) => {
  return apiClient.get('/orders', { params })
}

// 修复后
const getOrders = (params: { pageNum: number; pageSize: number; status?: string }) => {
  return apiClient.get('/orders/user', { params })
}
```

**验收**:
- 登录用户访问订单列表 → 网络请求为 `GET /orders/user?pageNum=1&pageSize=10`
- 返回数据正确渲染（非空列表或空状态）
- 翻页正常工作

**Checkpoint**: 浏览器 DevTools Network 面板确认请求 URL 和参数

---

### Step 2: 修复咨询订单 API composable — 端点 + 分页参数

**目标**: 咨询订单列表能正确获取数据

**修改文件**: `composables/api/offline-orders.ts`

**具体操作**:
1. 修复端点：`/offline-orders` → `/offline-orders/user`
2. 修复分页参数名：`page` → `pageNum`
3. 响应格式与订单列表一致（扁平结构）：`{ list, total, pageNum, pageSize, totalPages }`，无需特殊处理

**代码示例**:
```typescript
// 修复前
const getOfflineOrders = (params: { page: number; pageSize: number; status?: string }) => {
  return apiClient.get('/offline-orders', { params })
}

// 修复后
const getOfflineOrders = (params: { pageNum: number; pageSize: number; status?: string }) => {
  return apiClient.get('/offline-orders/user', { params })
}
```

**验收**:
- 网络请求为 `GET /offline-orders/user?pageNum=1&pageSize=10`
- 咨询列表正确渲染
- 分页组件显示正确的总页数
- 翻页正常

**Checkpoint**: 对比订单列表和咨询列表的网络请求，确认两者都正确

---

### Step 3: 个人资料页 — 头像上传 + UI 重构

**目标**: 实现头像上传功能，所有表单元素替换为 Reka UI 组件

**修改文件**: `pages/account/profile.vue`

**具体操作**:

**3a. 头像上传实现**:
1. 添加隐藏的 `<input type="file" accept="image/*">` 用于选择文件
2. 点击头像区域触发文件选择
3. 选择文件后调用 `POST /upload/single`（FormData 格式，字段名 `file`）：
   ```typescript
   const uploadAvatar = async (file: File) => {
     const formData = new FormData()
     formData.append('file', file)
     const res = await apiClient.post('/upload/single', formData, {
       headers: { 'Content-Type': 'multipart/form-data' }
     })
     // res.data: { url, fileName, originalName, size, mimeType }
     form.avatar = res.data.url
   }
   ```
4. 上传成功后将返回的 `url` 设置到 `form.avatar`
5. 显示上传中状态（loading 遮罩或 spinner）
6. 头像预览：使用 `<img :src="form.avatar">` 显示当前头像

**3b. UI 重构**:
1. 用户名输入：`<MaterialInput v-model="form.username" label="用户名" :error="errors.username" />`
2. 邮箱输入：`<MaterialInput v-model="form.email" label="邮箱" type="email" :error="errors.email" />`
3. 头像 URL 输入框删除（改为上传组件）
4. 保存按钮：`<GradientButton variant="primary" :loading="saving" @click="handleSave">保存</GradientButton>`
5. 布局使用 UnoCSS：`max-w-2xl mx-auto space-y-6`

**验收**:
- 点击头像 → 弹出文件选择 → 选择图片 → 上传成功 → 头像预览更新
- 上传过程中显示 loading 状态
- 保存资料后头像 URL 正确提交到 `PUT /auth/profile`
- 所有输入框为 MaterialInput，按钮为 GradientButton
- 无原生 `<input>` 或 `<button>` 标签

**Checkpoint**: 上传一张图片，确认 Network 面板有 `POST /upload/single` 请求且返回 url

---

### Step 4: 修改密码页 — UI 重构 + 使用 auth composable

**目标**: 密码修改使用 auth composable 的 changePassword 方法，UI 替换为 Reka UI

**修改文件**: `pages/account/password.vue`

**前置依赖**: SHOP-FE-002 Step 2（auth composable 已有 changePassword 方法）

**具体操作**:
1. 导入 auth composable 的 `changePassword` 方法（而非直接用 apiClient）
2. 替换表单元素：
   - 当前密码：`<MaterialInput v-model="form.currentPassword" label="当前密码" type="password" :error="errors.currentPassword" />`
   - 新密码：`<MaterialInput v-model="form.newPassword" label="新密码" type="password" :error="errors.newPassword" />`
   - 确认新密码：`<MaterialInput v-model="form.confirmPassword" label="确认新密码" type="password" :error="errors.confirmPassword" />`
3. 提交按钮：`<GradientButton variant="primary" :loading="saving">修改密码</GradientButton>`
4. 表单验证保持：当前密码必填、新密码长度 ≥ 6、确认密码一致
5. 成功后清空表单 + 显示成功提示

**验收**:
- 修改密码调用 auth composable（不直接用 apiClient）
- 所有输入框为 MaterialInput（浮动标签 + 密码切换）
- 按钮为 GradientButton（loading 状态）
- 验证错误显示在对应输入框下方

---

### Step 5: 订单列表页 — UI 重构

**目标**: 订单列表页使用 Reka UI 组件，正确渲染后端数据

**修改文件**: `pages/account/orders.vue`

**前置依赖**: Step 1（API 已修复）

**具体操作**:
1. 状态筛选：将原生 `<select>` 替换为 `<MaterialSelect>`
   ```vue
   <MaterialSelect v-model="filters.status" label="订单状态" :options="statusOptions" />
   ```
2. 搜索按钮（如有）：替换为 `<GradientButton variant="outline">`
3. 订单卡片/列表项中的操作按钮：替换为 `<GradientButton variant="ghost" size="sm">`
4. 分页组件：确认使用后端返回的 `total`、`pageNum`、`totalPages` 驱动
5. 空状态：使用 UnoCSS 样式（`text-center text-gray-400 py-12`）
6. 订单状态标签：使用 UnoCSS 原子类着色（如 `text-success` / `text-warning` / `text-error`）

**验收**:
- 无原生 `<select>` 或 `<button>` 标签
- 状态筛选切换后重新请求数据（`pageNum` 重置为 1）
- 分页切换正常
- 订单数据正确显示（订单号、金额、状态、时间）

---

### Step 6: 咨询订单页 — UI 重构

**目标**: 咨询订单页使用 Reka UI 组件

**修改文件**: `pages/account/consultations.vue`

**前置依赖**: Step 2（API 已修复）

**具体操作**:
1. 状态筛选：`<MaterialSelect>` 替换原生 `<select>`
2. 操作按钮：`<GradientButton>` 替换原生 `<button>`
3. 分页数据直接使用（与订单列表格式一致）：
   ```typescript
   const { list, total, pageNum, pageSize, totalPages } = response.data
   ```
4. 确认分页组件使用正确的 total / totalPages 值
5. 空状态样式与订单列表一致

**验收**:
- 咨询列表正确渲染（非空数据或空状态）
- 分页显示正确的总页数
- 翻页正常，无 JS 错误
- 无原生 HTML 表单元素

---

### Step 7: 地址管理页 — UI 重构

**目标**: 地址管理页使用 Reka UI 组件

**修改文件**: `pages/account/addresses.vue`

**具体操作**:
1. 地址表单输入框全部替换为 `<MaterialInput>`：
   - 收件人：`<MaterialInput v-model="form.name" label="收件人姓名" :error="errors.name" />`
   - 电话：`<MaterialInput v-model="form.phone" label="电话号码" :error="errors.phone" />`
   - 地址行1：`<MaterialInput v-model="form.addressLine1" label="详细地址" :error="errors.addressLine1" />`
   - 地址行2（可选）：`<MaterialInput v-model="form.addressLine2" label="补充地址（可选）" />`
   - 城市：`<MaterialInput v-model="form.city" label="城市" :error="errors.city" />`
   - 州/省：`<MaterialInput v-model="form.state" label="州/省" />`
   - 邮编：`<MaterialInput v-model="form.zipCode" label="邮编" />`
   - 国家：`<MaterialInput v-model="form.country" label="国家" :error="errors.country" />`
2. 默认地址复选框：`<CartCheckbox v-model="form.isDefault" label="设为默认地址" />`
3. 操作按钮：
   - 保存：`<GradientButton variant="primary" :loading="saving">保存</GradientButton>`
   - 取消：`<GradientButton variant="ghost">取消</GradientButton>`
   - 删除：`<GradientButton variant="outline" class="text-error">删除</GradientButton>`
   - 新增地址：`<GradientButton variant="primary">新增地址</GradientButton>`
   - 设为默认：`<GradientButton variant="ghost" size="sm">设为默认</GradientButton>`
4. 地址卡片布局使用 UnoCSS grid/flex

**验收**:
- 地址 CRUD 全部正常（新增、编辑、删除、设为默认）
- 所有输入框为 MaterialInput，按钮为 GradientButton，复选框为 CartCheckbox
- 无原生 HTML 表单元素
- 设为默认调用 `PUT /addresses/:id/default`

---

### Step 8: 全量回归验证

**目标**: 确认所有个人中心子页面功能正常、UI 规范统一

**操作**:

1. **API 联调验证**（DevTools Network 面板）:
   - 订单列表：`GET /orders/user?pageNum=1&pageSize=10` → 200
   - 咨询列表：`GET /offline-orders/user?pageNum=1&pageSize=10` → 200
   - 个人资料：`GET /auth/profile` → 200
   - 更新资料：`PUT /auth/profile` → 200
   - 修改密码：`PUT /auth/password` → 200
   - 地址列表：`GET /addresses` → 200
   - 头像上传：`POST /upload/single` → 200

2. **分页验证**:
   - 订单列表翻页：pageNum 递增，数据切换
   - 咨询列表翻页：pageNum 递增，数据切换（格式与订单一致）
   - 状态筛选后 pageNum 重置为 1

3. **头像上传验证**:
   - 选择图片 → 上传 → 预览更新 → 保存资料 → 刷新页面头像保持

4. **UI 规范验证**（逐页检查）:
   - `pages/account/profile.vue` — 无原生 input/button
   - `pages/account/password.vue` — 无原生 input/button
   - `pages/account/orders.vue` — 无原生 select/button
   - `pages/account/consultations.vue` — 无原生 select/button
   - `pages/account/addresses.vue` — 无原生 input/button/checkbox

5. **边界场景**:
   - 未登录访问 /account/* → 重定向 /login
   - 空订单列表 → 显示空状态
   - 上传非图片文件 → 错误提示
   - 修改密码输入错误的当前密码 → 后端返回错误，前端显示

**验收**:
- 7 个 API 端点全部返回 200
- 分页功能正常（两个列表页）
- 头像上传完整流程通过
- 5 个页面无原生 HTML 表单元素
- 无 console 错误

---

## 验收标准

| # | 标准 | 对应 Step |
|---|------|-----------|
| 1 | 订单列表端点 `/orders/user` + 参数 `pageNum` | Step 1 |
| 2 | 咨询列表端点 `/offline-orders/user` + 参数 `pageNum` | Step 2 |
| 3 | 咨询列表响应格式与订单一致（扁平结构） | Step 2 |
| 4 | 头像上传功能完整（选择→上传→预览→保存） | Step 3 |
| 5 | 个人资料页 UI 使用 MaterialInput + GradientButton | Step 3 |
| 6 | 修改密码页通过 auth composable 调用 | Step 4 |
| 7 | 订单列表页 UI 使用 MaterialSelect + GradientButton | Step 5 |
| 8 | 咨询订单页 UI 重构 | Step 6 |
| 9 | 地址管理页 UI 使用全套 Reka UI 组件 | Step 7 |
| 10 | 全量回归通过，无 console 错误 | Step 8 |

---

## UI 组件使用规范（强制）

| 场景 | 必须使用 | 禁止使用 |
|------|---------|---------|
| 文本输入 | `<MaterialInput>` | `<input type="text">` |
| 密码输入 | `<MaterialInput type="password">` | `<input type="password">` |
| 下拉选择 | `<MaterialSelect>` | `<select>` |
| 多行文本 | `<MaterialTextarea>` | `<textarea>` |
| 按钮 | `<GradientButton>` | `<button>` |
| 复选框 | `<CartCheckbox>` | `<input type="checkbox">` |
| 样式 | UnoCSS 原子类 | 内联 style / scoped CSS |

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 头像上传 FormData 字段名不确定 | 先读后端 upload 路由确认字段名（预期为 `file`） |
| MaterialInput v-model 行为差异 | 先读组件源码确认 props/events |
| 咨询订单分页格式与订单一致 | 已确认后端统一使用 paginatedSuccess，扁平结构 |
| 地址表单字段名与后端不匹配 | 参照 `02-api/addresses.md` 确认字段名 |
| UI 重构可能破坏现有逻辑 | 只替换模板层，保持 script 逻辑不变 |

---

**相关文档:**
- [Orders API 文档](../../02-api/orders.md)
- [Offline Orders API 文档](../../02-api/offline-orders.md)
- [Auth API 文档](../../02-api/auth.md)
- [Addresses API 文档](../../02-api/addresses.md)
- [项目状态](../../04-projects/nuxt-moxton.md)
- [前置任务: SHOP-FE-002](./SHOP-FE-002-login-register-auth.md)
