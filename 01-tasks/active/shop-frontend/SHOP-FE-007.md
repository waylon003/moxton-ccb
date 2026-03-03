# SHOP-FE-007: 商城前端 UI 修复合集

## 任务概述
修复商城前端多个 UI 问题，包括地址自动完成组件、导航栏、购物车、订单记录和个人中心等。

## 修改清单

### 1. AddressAutocompleteInput.vue 样式修复
**文件**: `components/AddressAutocompleteInput.vue`

- **第164行**: 清除按钮定位修复
  - 当前: `class="absolute right-3 top-1/2 -translate-y-1/2 ..."`
  - 修改: 去除 `-translate-y-1/2`，只保留 `top-1/8`，实现垂直居中

- **空状态提示**: 当搜索不到地址时，在建议列表中显示空状态提示
  - 当前: 无结果时不显示建议列表
  - 修改: 在 `isOpen && suggestions.length === 0 && searchQuery.length >= 2 && !loading` 条件下显示空状态提示
  - 使用 Icon 组件显示 `heroicons:magnifying-glass` 图标和提示文字 "No addresses found"

### 2. 导航栏头像简化
**文件**: `components/layout/Navigation.vue`

- **第189-203行**: 登录后头像下拉菜单
  - 去除边框 (`border border-[#E5E5E5]`)
  - 去除下拉箭头图标 (`<Icon name="lucide:chevron-down" />`)
  - 只保留头像显示（有头像显示头像，无头像显示首字母）
  - 保留悬停下拉功能

### 3. 购物车按钮简化
**文件**: `components/layout/Navigation.vue`

- **第161-169行**: PC 端购物车按钮
  - 去除文字 "{{ t('nav.cart') }}"
  - 只保留购物车图标
  - 保留悬停效果和点击事件

### 4. 订单记录商品图片修复
**文件**: `pages/account/orders/index.vue`

- **第233行**: 商品图片路径修复
  - 当前: `order.items?.[0]?.product?.image`
  - 修改: `order.items?.[0]?.product?.images?.[0]`（images 是字符串数组，取第一个）
  - 同时修改接口定义 `AccountOrderItem` 中的类型：`image?: string` 改为 `images?: string[]`

- **订单状态标签样式**: 第221-226行
  - 当前: 纯文字，只有颜色（`text-warning`, `text-success` 等）
  - 修改: 使用标签组件样式，有背景色和边框
  - 参考颜色:
    - PENDING: 橙色背景 + 橙色边框
    - PAID/CONFIRMED: 绿色背景 + 绿色边框
    - SHIPPED/DELIVERED: 蓝色背景 + 蓝色边框
    - CANCELLED: 灰色背景 + 灰色边框

### 5. 地址管理表单默认地址组件替换
**文件**: `pages/account/addresses.vue`

- **第385-390行**: "设为默认地址" 复选框
  - 当前: 使用 `CartCheckbox` 组件
  - 修改: 使用 reka-ui 的 `CheckboxRoot` + `CheckboxIndicator` + unocss 样式
  - 参考 `CartSidebar.vue` 第304-310行的实现方式
  - 样式保持一致：橙色主题色

### 6. 个人中心字体风格统一
**文件**: `pages/account/profile.vue`

- 检查并统一字体风格，与其他账户页面（orders、addresses）保持一致
- 确保标题、按钮、表单的字体样式统一

## 技术要求

1. **禁止使用的符号**:
   - 禁止使用 `->`、`<-` 等箭头符号
   - 必须使用 Icon 组件（如 `heroicons:arrow-right`）
   - 禁止使用 emoji 或文本图标

2. **组件规范**:
   - 使用 reka-ui 组件（已安装 `reka-ui: ^2.6.1`）
   - 使用 unocss 进行样式设置
   - 图标使用 `@nuxt/icon` 模块的 Icon 组件

3. **样式规范**:
   - 使用项目已有的颜色变量（如 `#FF6B35` 橙色主题色）
   - 保持与现有 UI 风格一致

## 验收标准

- [ ] AddressAutocompleteInput 清除按钮垂直居中
- [ ] AddressAutocompleteInput 搜索无结果时显示空状态提示
- [ ] 导航栏头像去除边框和箭头，只保留头像
- [ ] 购物车按钮只保留图标
- [ ] 订单记录商品图片正确渲染（使用 images[0]）
- [ ] 订单状态显示为标签样式（有背景边框）
- [ ] 地址管理默认地址使用 reka-ui Checkbox + unocss
- [ ] 个人中心字体风格与其他页面一致
- [ ] 未使用任何 `->`、`<-` 箭头符号

## 前置依赖
无

## 关联任务
无
