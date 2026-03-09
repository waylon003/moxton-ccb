# SHOP-FE-008: 订单详情页图片显示与箭头符号修复

## 任务概述
修复 SHOP-FE-007 遗漏的问题：订单详情页商品图片显示异常，以及页面中出现的 `<-` `->` 文本箭头符号。

## 问题描述

### 1. 订单详情页商品图片未正常显示
**文件**: `pages/account/orders/[id].vue` (或订单详情页文件)

- **问题**: 订单列表页图片已修复（使用 `images[0]`），但订单详情页图片仍使用旧的 `image` 字段
- **修复**: 将详情页中的 `item.product.image` 改为 `item.product.images?.[0]`
- **同时更新类型定义**: 将 `image?: string` 改为 `images?: string[]`

### 2. 箭头符号替换为 Icon 组件
**文件**: 需全局搜索订单相关页面

- **问题**: 页面中出现 `<-` 和 `->` 文本箭头符号
- **修复**: 替换为 Icon 组件
  - `<-` → `<Icon name="heroicons:arrow-left" />`
  - `->` → `<Icon name="heroicons:arrow-right" />`
- **搜索范围**:
  - `pages/account/orders/` 目录下所有文件
  - `components/order/` (如有订单相关组件)

## 修改清单

### 订单详情页图片修复
```vue
<!-- 修改前 -->
<img :src="item.product.image" />

<!-- 修改后 -->
<img :src="item.product.images?.[0]" />
```

### 箭头符号替换
```vue
<!-- 修改前 -->
<button><- 返回</button>
<button>进入 -></button>

<!-- 修改后 -->
<button>
  <Icon name="heroicons:arrow-left" />
  返回
</button>
<button>
  进入
  <Icon name="heroicons:arrow-right" />
</button>
```

## 技术要求

1. **禁止使用的符号**:
   - 禁止使用 `->`、`<-` 等文本箭头符号
   - 必须使用 Icon 组件

2. **组件规范**:
   - 使用 `@nuxt/icon` 模块的 Icon 组件
   - 图标名称使用 `heroicons:arrow-left` 和 `heroicons:arrow-right`

## 验收标准

- [ ] 订单详情页商品图片正确显示（使用 `images[0]`）
- [ ] 订单详情页类型定义已更新（`images?: string[]`）
- [ ] 页面中无 `<-` 文本箭头符号
- [ ] 页面中无 `->` 文本箭头符号
- [ ] 所有箭头已替换为 Icon 组件

## 前置依赖
- BACKEND-013: 订单接口图片格式已修复为数组

## 关联任务
- SHOP-FE-007: 商城前端 UI 修复合集（订单列表图片已修复）
