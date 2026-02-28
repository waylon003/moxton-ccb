# Tech-Spec: 个人中心侧边栏切换报错修复 + 状态下拉优化

**创建时间:** 2026-02-28
**状态:** 准备开发
**角色:** 独立站前端工程师
**项目:** nuxt-moxton
**优先级:** P1
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia + Reka UI + UnoCSS
**前置依赖:** SHOP-FE-003

---

## 概述

### 问题陈述

个人中心页面存在五个问题：
1. **侧边栏切换报错** — 切换侧边栏菜单项时控制台出现 JavaScript 错误
2. **状态下拉选择体验不佳** — 订单列表和咨询列表的状态筛选下拉框需要参考 shop 页面排序方式的实现，提升用户体验
3. **订单状态选项与后端不对齐** — 前端状态选项需要与后端 API 定义的状态枚举完全一致，`CONFIRMED` 状态应显示为"待发货"
4. **导航栏显示冗余** — 导航栏同时显示头像和用户名，需要改为只显示头像
5. **MaterialInput 禁用状态无视觉反馈** — `components/ui/MaterialInput.vue` 组件在禁用状态下缺少视觉样式，用户无法感知输入框是否被禁用

### 解决方案

1. 定位并修复侧边栏切换时的控制台错误
2. 参考 shop 页面的排序下拉实现，优化个人中心的状态筛选下拉组件
3. 使用后端 API 定义的订单状态枚举值，`CONFIRMED` 状态显示为"待发货"
4. 修改导航栏只显示用户头像，隐藏用户名
5. 为 MaterialInput 组件添加禁用状态的视觉样式

### 范围

**包含:**
- 修复侧边栏切换时的控制台错误
- 优化订单列表页的状态下拉选择
- 优化咨询列表页的状态下拉选择
- 确保下拉组件样式和交互与 shop 页面一致
- 订单状态选项与后端 API 对齐（CONFIRMED = 待发货）
- 导航栏只显示头像
- MaterialInput 组件禁用状态样式优化

**不包含:**
- 其他个人中心功能的修改
- 新增筛选条件
- 侧边栏样式重构
- 导航栏其他元素的修改
- 其他 UI 组件的禁用状态优化

---

## 开发上下文

### 现有实现

**个人中心相关文件:**
- `pages/account/index.vue` — 个人中心主页面（包含侧边栏）
- `pages/account/orders.vue` — 订单列表页
- `pages/account/consultations.vue` — 咨询列表页

**参考实现:**
- `pages/shop/index.vue` 或类似页面 — 包含排序方式下拉选择的实现

### 依赖项

- Reka UI 组件库（MaterialSelect 或其他下拉组件）
- UnoCSS 样式系统
- Vue Router（侧边栏路由切换）

---

## 技术方案

### Step 1: 定位并修复侧边栏切换报错

**目标**: 消除控制台错误，确保侧边栏切换流畅

**排查方向:**
1. 检查 `pages/account/index.vue` 中的路由切换逻辑
2. 检查是否有未定义的变量或方法调用
3. 检查是否有组件生命周期问题（如在组件销毁后访问 DOM）
4. 检查是否有异步数据加载导致的 null/undefined 访问

**可能的错误类型:**
- `Cannot read property 'xxx' of undefined`
- `xxx is not a function`
- Vue Router 相关警告
- 组件 ref 访问错误

**修复策略:**
- 添加必要的 null 检查
- 使用可选链操作符 `?.`
- 确保在正确的生命周期钩子中访问 DOM
- 添加 v-if 条件渲染保护

### Step 2: 参考 shop 页面实现状态下拉

**目标**: 找到 shop 页面的排序下拉实现，作为优化参考

**操作:**
1. 在 `E:\nuxt-moxton` 中搜索 shop 页面的排序下拉实现
2. 分析其使用的组件、样式和交互逻辑
3. 记录关键实现细节：
   - 使用的组件（MaterialSelect / MaterialDropdown / 自定义组件）
   - 样式类名和布局
   - 选项数据结构
   - 事件处理方式

### Step 3: 优化订单列表状态下拉（与后端对齐）

**目标**: 将订单列表的状态筛选下拉改为与 shop 页面一致的实现，并使用后端 API 定义的状态枚举

**修改文件**: `pages/account/orders.vue`

**后端订单状态枚举**（来自 `02-api/orders.md`）:
- `PENDING` - 待支付
- `PAID` - 已支付
- `CONFIRMED` - 待发货（已确认）
- `SHIPPED` - 已发货
- `DELIVERED` - 已送达
- `CANCELLED` - 已取消

**具体操作:**
1. 替换现有的状态下拉组件为 shop 页面使用的组件
2. 调整样式使其与 shop 页面一致
3. **使用后端定义的状态枚举值，CONFIRMED 显示为"待发货"**：
   ```typescript
   const statusOptions = [
     { label: '全部订单', value: '' },
     { label: '待支付', value: 'PENDING' },
     { label: '已支付', value: 'PAID' },
     { label: '待发货', value: 'CONFIRMED' },  // 注意：CONFIRMED = 待发货
     { label: '已发货', value: 'SHIPPED' },
     { label: '已送达', value: 'DELIVERED' },
     { label: '已取消', value: 'CANCELLED' }
   ]
   ```
4. 确保选择状态后触发数据重新加载（pageNum 重置为 1）

**注意**: `CONFIRMED` 状态在用户端应显示为"待发货"，因为订单已确认但尚未发货。

**注意**: 状态值必须使用大写（`PENDING`、`PAID` 等），与后端 API 完全一致。

### Step 4: 优化咨询列表状态下拉

**目标**: 将咨询列表的状态筛选下拉改为与 shop 页面一致的实现

**修改文件**: `pages/account/consultations.vue`

**具体操作:**
1. 与订单列表相同的优化策略
2. 咨询订单状态选项（需确认后端实际状态枚举）：
   ```typescript
   const statusOptions = [
     { label: '全部咨询', value: '' },
     { label: '待处理', value: 'pending' },
     { label: '处理中', value: 'processing' },
     { label: '已完成', value: 'completed' },
     { label: '已取消', value: 'cancelled' }
   ]
   ```

**注意**: 咨询订单的状态枚举需要与后端 `/offline-orders` API 对齐，如果后端使用大写，前端也需要改为大写。

### Step 5: 修改导航栏只显示头像

**目标**: 导航栏用户信息区域只显示头像，隐藏用户名

**修改文件**: 导航栏组件（可能是 `components/Header.vue` 或 `layouts/default.vue`）

**具体操作:**
1. 找到导航栏中显示用户信息的部分
2. 保留头像显示
3. 移除或隐藏用户名显示
4. 确保头像可点击，打开用户菜单（如果有下拉菜单）
5. 调整样式，确保只显示头像时布局美观

**代码示例**:
```vue
<!-- 修改前 -->
<div class="user-info">
  <img :src="user.avatar" alt="avatar" class="avatar" />
  <span class="username">{{ user.username }}</span>
</div>

<!-- 修改后 -->
<div class="user-info">
  <img :src="user.avatar" alt="avatar" class="avatar" />
  <!-- 移除用户名显示 -->
</div>
```

**验收:**
- 导航栏只显示用户头像
- 用户名不再显示
- 头像点击交互正常（如果有下拉菜单）
- 响应式布局正常

---

## 实施步骤

### Step 1: 修复侧边栏切换报错

1. 在 `E:\nuxt-moxton` 中打开开发服务器
2. 打开浏览器控制台，访问个人中心页面
3. 逐个点击侧边栏菜单项，复现控制台错误
4. 记录完整的错误信息（错误类型、堆栈跟踪、触发条件）
5. 定位错误源码位置
6. 修复错误（添加保护性检查、修正逻辑）
7. 验证修复后侧边栏切换无错误

**验收:**
- 切换所有侧边栏菜单项（个人资料、订单列表、咨询列表、地址管理、修改密码）
- 控制台无任何错误或警告
- 页面切换流畅，无闪烁或卡顿

---

### Step 2: 查找 shop 页面排序下拉实现

1. 在 `E:\nuxt-moxton` 中搜索 shop 相关页面
2. 找到包含排序下拉的页面（可能是 `pages/shop/index.vue` 或 `pages/products/index.vue`）
3. 分析排序下拉的实现：
   - 使用的组件名称
   - 组件 props 和 events
   - 样式类名
   - 选项数据结构
4. 截图或记录关键代码片段

**验收:**
- 找到 shop 页面排序下拉的实现文件
- 明确使用的组件和样式

---

### Step 3: 优化订单列表状态下拉

1. 打开 `pages/account/orders.vue`
2. 找到当前的状态筛选下拉实现
3. 参考 shop 页面的实现，替换为相同的组件和样式
4. **使用后端定义的状态枚举值**（大写）：
   ```typescript
   const statusOptions = [
     { label: '全部订单', value: '' },
     { label: '待支付', value: 'PENDING' },
     { label: '已支付', value: 'PAID' },
     { label: '待发货', value: 'CONFIRMED' },
     { label: '已发货', value: 'SHIPPED' },
     { label: '已送达', value: 'DELIVERED' },
     { label: '已取消', value: 'CANCELLED' }
   ]
   ```
5. 确保选择状态后触发 API 请求：
   ```typescript
   const onStatusChange = () => {
     filters.pageNum = 1 // 重置页码
     fetchOrders()
   }
   ```
6. 测试所有状态选项的筛选功能

**验收:**
- 状态下拉样式与 shop 页面一致
- 选择不同状态后正确筛选订单
- 状态值使用大写（与后端 API 一致）
- 切换状态后页码重置为 1
- 下拉交互流畅（打开、选择、关闭）

---

### Step 4: 优化咨询列表状态下拉

1. 打开 `pages/account/consultations.vue`
2. 应用与订单列表相同的优化
3. 调整咨询订单的状态选项（需确认后端实际枚举）
4. 测试筛选功能

**验收:**
- 状态下拉样式与 shop 页面和订单列表一致
- 选择不同状态后正确筛选咨询订单
- 切换状态后页码重置为 1

---

### Step 5: 修改导航栏只显示头像

1. 找到导航栏组件（可能是 `components/Header.vue`、`components/Navbar.vue` 或 `layouts/default.vue`）
2. 定位用户信息显示区域
3. 保留头像 `<img>` 元素
4. 移除或隐藏用户名 `<span>` 元素
5. 调整样式确保布局美观
6. 测试头像点击交互（如果有下拉菜单）

**验收:**
- 导航栏只显示用户头像
- 用户名不再显示
- 头像点击交互正常
- 响应式布局正常（桌面、平板、移动端）

---

### Step 6: 优化 MaterialInput 禁用状态样式

**目标**: 为 MaterialInput 组件添加禁用状态的视觉反馈，让用户能够清晰感知输入框是否被禁用

**修改文件**: `components/ui/MaterialInput.vue`

**具体操作:**
1. 打开 `components/ui/MaterialInput.vue` 组件
2. 检查组件是否已支持 `disabled` prop
3. 添加禁用状态的样式：
   ```vue
   <template>
     <input
       :disabled="disabled"
       :class="[
         'base-input-class',
         disabled && 'opacity-60 cursor-not-allowed bg-gray-100'
       ]"
     />
   </template>
   ```
4. 推荐的禁用状态样式：
   - 降低透明度：`opacity-60` 或 `opacity-50`
   - 改变背景色：`bg-gray-100` 或 `bg-gray-50`
   - 改变光标：`cursor-not-allowed`
   - 改变文字颜色：`text-gray-400`
   - 可选：添加边框样式变化

**代码示例**:
```vue
<script setup lang="ts">
defineProps<{
  disabled?: boolean
  // ... 其他 props
}>()
</script>

<template>
  <div class="material-input-wrapper">
    <input
      :disabled="disabled"
      :class="[
        'material-input',
        disabled && 'opacity-60 cursor-not-allowed bg-gray-100 text-gray-500'
      ]"
    />
    <label
      :class="[
        'material-label',
        disabled && 'text-gray-400'
      ]"
    >
      {{ label }}
    </label>
  </div>
</template>
```

**验收:**
- MaterialInput 组件支持 `disabled` prop
- 禁用状态下输入框有明显的视觉变化（透明度降低、背景色变化、光标变化）
- 禁用状态下标签文字颜色变浅
- 禁用状态下无法输入或编辑
- 样式与整体设计风格一致

---

### Step 7: 全量回归测试

1. **侧边栏切换测试:**
   - 依次点击所有侧边栏菜单项
   - 快速连续切换菜单项
   - 控制台无错误

2. **状态筛选测试:**
   - 订单列表：测试所有状态选项（PENDING、PAID、CONFIRMED、SHIPPED、DELIVERED、CANCELLED）
   - 咨询列表：测试所有状态选项
   - 验证筛选结果正确
   - 验证状态值与后端 API 一致

3. **导航栏测试:**
   - 验证只显示头像，不显示用户名
   - 测试头像点击交互
   - 测试响应式布局

4. **MaterialInput 禁用状态测试:**
   - 在个人中心页面找到使用 MaterialInput 的地方
   - 测试禁用状态的视觉效果（透明度、背景色、光标）
   - 验证禁用状态下无法输入

5. **样式一致性检查:**
   - 对比 shop 页面和个人中心的下拉样式
   - 确保视觉效果一致

6. **响应式测试:**
   - 桌面端、平板端、移动端测试
   - 下拉组件在不同屏幕尺寸下正常工作
   - 导航栏头像在不同屏幕尺寸下正常显示

**验收:**
- 侧边栏切换无错误
- 状态筛选功能正常，状态值与后端对齐（CONFIRMED = 待发货）
- 导航栏只显示头像
- MaterialInput 禁用状态有明显视觉反馈
- 样式与 shop 页面一致
- 响应式布局正常

---

## 验收标准

- [ ] 侧边栏切换时控制台无任何错误或警告
- [ ] 订单列表状态下拉样式与 shop 页面一致
- [ ] 订单列表状态值使用后端定义的枚举（PENDING、PAID、CONFIRMED、SHIPPED、DELIVERED、CANCELLED）
- [ ] CONFIRMED 状态显示为"待发货"（不是"已确认"）
- [ ] 咨询列表状态下拉样式与 shop 页面一致
- [ ] 状态筛选功能正常，切换状态后正确加载数据
- [ ] 切换状态后页码重置为 1
- [ ] 下拉交互流畅（打开、选择、关闭）
- [ ] 导航栏只显示用户头像，不显示用户名
- [ ] 头像点击交互正常
- [ ] MaterialInput 组件支持 disabled prop
- [ ] MaterialInput 禁用状态有明显视觉反馈（透明度、背景色、光标）
- [ ] MaterialInput 禁用状态下无法输入或编辑
- [ ] 响应式布局正常（桌面、平板、移动端）
- [ ] 无新增的控制台错误或警告

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 侧边栏错误难以复现 | 在不同浏览器和设备上测试，记录详细的复现步骤 |
| shop 页面排序下拉实现难以找到 | 搜索关键词：sort、order、filter、dropdown、select |
| 状态选项值与后端不匹配 | 参考 API 文档确认状态枚举值（必须使用大写：PENDING、PAID 等） |
| CONFIRMED 状态标签不明确 | 使用"待发货"而非"已确认"，更符合用户理解 |
| 咨询订单状态枚举未确认 | 先查看后端 offline-orders API 文档，确认实际状态枚举值 |
| 修改后破坏现有筛选逻辑 | 保持数据处理逻辑不变，只替换 UI 组件 |
| 导航栏组件位置不确定 | 搜索关键词：Header、Navbar、avatar、username |
| 移除用户名后布局错位 | 调整 CSS，确保头像居中或对齐正确 |
| MaterialInput 组件未支持 disabled prop | 检查组件源码，如未支持则添加 prop 定义 |
| 禁用样式与现有设计风格不一致 | 参考其他 UI 组件的禁用状态样式，保持一致性 |
| 样式冲突 | 使用 UnoCSS 原子类，避免自定义样式 |

---

**相关文档:**
- [Orders API 文档](../../02-api/orders.md)
- [Offline Orders API 文档](../../02-api/offline-orders.md)
- [项目状态](../../04-projects/nuxt-moxton.md)
- [前置任务: SHOP-FE-003](../completed/shop-frontend/SHOP-FE-003-account-center.md)
