# Tech-Spec: 官网购买模式展示与预售预约入口

**任务ID:** SHOP-FE-016
**创建时间:** 2026-06-17
**最后更新:** 2026-06-27
**状态:** 已完成
**角色:** 独立站前端工程师
**项目:** nuxt-moxton
**优先级:** P0
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia
**QA_LEVEL:** smoke

---


## 概述

> 2026-06-27 业务口径调整：预售产品在商品列表和商品详情页不再显示可点击的“立即预约”，而是显示灰色禁用按钮“即将上线”。固定预约页入口放在首页，把原“联系我们”入口改为“立即预约”，跳转 `/preorder-discount?source=home_preorder`。本文件保留历史任务背景，实际后续开发以本备注和 `SHOP-FE-017` 为准。

### 问题陈述

官网商品卡片和详情页当前通过 `product.hasPrice` 区分购买与咨询。新增预售产品后，需要第三种展示。最初方案是显示“立即预约”并跳转预约表单页；当前最新方案已调整为商品列表和详情页显示灰色禁用按钮“即将上线”。同时官网登录/注册入口本阶段需要隐藏。

### 解决方案

增加购买模式兼容判断，优先使用后端 `purchaseMode`，缺失时回退 `hasPrice`。在商品卡片、桌面详情、移动详情中按模式展示不同按钮。当前 `PREORDER` 分支应显示不可点击的“即将上线”，不从商品入口跳转预约页。

### 范围

**包含:**
- 类型增加 `purchaseMode`。
- 新增统一购买模式判断 helper。
- 商品卡片支持 `ONLINE` / `INQUIRY_ONLY` / `PREORDER`。
- 商品详情桌面和移动端支持预售状态展示。
- 预售产品显示灰色禁用按钮“即将上线”。
- 首页预约入口跳转 `/preorder-discount?source=home_preorder`。
- 隐藏官网登录/注册入口。

**不包含:**
- 预约表单页实现。
- 预约提交 API。
- 后端改动。
- 删除登录系统。

---

## 开发上下文

重点文件：

- `types/shop.ts`
- `types/index.ts`
- `components/shop/ProductCard.vue`
- `components/shop/ProductInfo.vue`
- `components/shop/ProductInfoMobile.vue`
- `pages/product/[id].vue`
- `components/layout/Navigation.vue`
- `i18n/locales/zh.ts`
- `i18n/locales/en.ts`

现有实现：

- `ProductCard.vue` 使用 `product.hasPrice` 展示购买或咨询按钮。
- `ProductInfo.vue` 使用 `product.hasPrice` 展示价格、数量、加入购物车或咨询按钮。
- `ProductInfoMobile.vue` 同样依赖 `hasPrice`。
- `Navigation.vue` 桌面和移动端均有登录入口。

### 依赖项

- 前置任务：`BACKEND-017`
- 后端应返回 `purchaseMode`。但本任务必须兼容旧接口未返回字段的情况。

---

## 技术方案

### 架构设计

新增统一 helper，避免多组件重复硬编码：

```ts
getPurchaseMode(product)
isOnlineProduct(product)
isInquiryProduct(product)
isPreorderProduct(product)
```

兼容逻辑：

```ts
if (product.purchaseMode) return product.purchaseMode
return product.hasPrice ? 'ONLINE' : 'INQUIRY_ONLY'
```

### 页面逻辑

- `ONLINE`：显示价格、数量、加入购物车/购买入口。
- `INQUIRY_ONLY`：显示“立即咨询”。
- `PREORDER`：显示灰色禁用“即将上线”。

预约页跳转不再从商品卡片或详情页触发。首页入口负责跳转：

```ts
navigateTo('/preorder-discount?source=home_preorder')
```

---

## 实施步骤

1. 更新商品类型，增加 `purchaseMode?: 'ONLINE' | 'INQUIRY_ONLY' | 'PREORDER'`。
2. 新增购买模式 helper。
3. 修改 `ProductCard.vue` 的价格角标和按钮分支。
4. 修改 `ProductInfo.vue` 的详情页桌面分支，预售分支显示禁用状态。
5. 修改 `ProductInfoMobile.vue` 的详情页移动分支，预售分支显示禁用状态。
6. 确认 `pages/product/[id].vue` 不再从预售产品跳转预约页。
7. 修改 `Navigation.vue`，隐藏未登录状态下的登录入口。
8. 补充中英文文案：`即将上线` / `Coming Soon`。

---

## 验收标准

- [ ] `ONLINE` 商品仍显示购买能力。
- [ ] `INQUIRY_ONLY` 商品仍显示咨询能力。
- [ ] `PREORDER` 商品显示灰色禁用“即将上线”。
- [ ] `PREORDER` 商品不显示加入购物车或立即购买。
- [ ] 商品卡片和详情页的 `PREORDER` 状态不会跳转预约页。
- [ ] 首页“立即预约”跳转到 `/preorder-discount?source=home_preorder`。
- [ ] 官网桌面端和移动端登录/注册入口暂时隐藏。
- [ ] 后端未返回 `purchaseMode` 时，旧 `hasPrice` 分支仍可工作。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 预约页尚未实现 | 商品卡片和详情页不依赖预约页；首页预约入口和页面由 SHOP-FE-017 实现 |
| 后端字段未上线 | helper 必须回退到 `hasPrice` |
| 登录入口隐藏误删认证模块 | 只隐藏导航入口，不删除 `/login`、`/register` 页面 |

---

**相关文档:**
- [开发计划](../../docs/plans/2026-06-17-preorder-discount-code-closed-loop-plan.md)
- [项目状态](../../04-projects/nuxt-moxton.md)
