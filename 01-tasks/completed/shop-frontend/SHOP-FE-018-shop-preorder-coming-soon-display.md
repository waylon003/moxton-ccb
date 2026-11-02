# Tech-Spec: 官网商店预售产品“即将上线”展示修正

**任务ID:** SHOP-FE-018
**创建时间:** 2026-06-27
**状态:** 开发完成
**角色:** 独立站前端工程师
**项目:** nuxt-moxton
**优先级:** P0
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia
**QA_LEVEL:** smoke

---

## 概述

### 问题陈述

当前官网代码里，商店商品卡片和商品详情页对 `PREORDER` 商品仍然使用旧方案：

- 商品卡片显示 `Reserve Now / 立即预约`。
- 商品卡片点击后跳转 `/preorder-discount?source=product_card&productId=<id>`。
- 商品详情页桌面端显示 `Reserve Now / 立即预约`。
- 商品详情页移动端显示 `Reserve Now / 立即预约`。
- 商品详情页点击后跳转 `/preorder-discount?source=product_detail&productId=<id>`。

这和当前最新业务口径冲突。当前方案要求：

- 商店商品卡片中的预售产品按钮为灰色禁用，文案为 `Coming Soon / 即将上线`。
- 商品详情页桌面端和移动端也显示灰色禁用按钮 `Coming Soon / 即将上线`。
- 商品卡片和商品详情页不再跳转预约页。
- 固定预约页入口只放在首页“立即预约”。

### 解决方案

修正 `PREORDER` 商品在官网商店和详情页的展示逻辑：

1. 保留 `purchaseMode` 判断 helper。
2. 商品卡片 `PREORDER` 分支显示不可点击状态。
3. 商品详情桌面端 `PREORDER` 分支显示不可点击状态。
4. 商品详情移动端 `PREORDER` 分支显示不可点击状态。
5. 删除或停用商品卡片和商品详情页的 `handlePreorder` 跳转。
6. i18n 增加 `comingSoon` 文案。
7. 检查预售产品主图在商店卡片中是否被 `object-cover` 裁切，必要时对 `PREORDER` 商品使用 `object-contain`。

### 范围

**包含:**

- 商品卡片预售状态展示修正。
- 商品详情桌面端预售状态展示修正。
- 商品详情移动端预售状态展示修正。
- i18n 增加中英文 `Coming Soon / 即将上线`。
- 去掉从商品入口跳转预约页的旧逻辑。
- 检查预售产品图在商品卡片和详情页中的展示方式。

**不包含:**

- 固定预约页 `/preorder-discount` 开发，见 `SHOP-FE-017`。
- 首页“立即预约”入口开发，见 `SHOP-FE-017`。
- 后端接口开发。
- 后台商品配置。
- 预约提交和邮件发送。

---

## 开发上下文

当前相关文件：

- `components/shop/ProductCard.vue`
- `components/shop/ProductInfo.vue`
- `components/shop/ProductInfoMobile.vue`
- `pages/product/[id].vue`
- `utils/purchaseMode.ts`
- `types/shop.ts`
- `i18n/locales/en.ts`
- `i18n/locales/zh.ts`

当前已发现的旧逻辑：

- `ProductCard.vue` 有 `handlePreorder`，会跳转 `/preorder-discount` 并携带 `productId`。
- `ProductCard.vue` 预售按钮仍显示 `reserveNow`。
- `ProductInfo.vue` 预售按钮仍 emit `preorder`。
- `ProductInfoMobile.vue` 预售按钮仍 emit `preorder`。
- `pages/product/[id].vue` 有 `handlePreorder`，会跳转 `/preorder-discount` 并携带 `productId`。
- i18n 当前只有 `reserveNow`，没有专门的 `comingSoon`。

---

## 技术方案

### 文案

新增 i18n：

```ts
shop: {
  product: {
    comingSoon: 'Coming Soon'
  }
}
```

中文：

```ts
shop: {
  product: {
    comingSoon: '即将上线'
  }
}
```

保留 `reserveNow` 不删除，因为首页预约入口或后续预约页可能仍使用“立即预约”。

### 商品卡片

当前：

```vue
<button v-else @click="handlePreorder">
  {{ t('shop.product.reserveNow', 'Reserve Now') }}
</button>
```

调整为：

```vue
<button
  v-else
  disabled
  aria-disabled="true"
  class="..."
>
  {{ t('shop.product.comingSoon', 'Coming Soon') }}
</button>
```

样式建议：

- 背景：`bg-gray-300 dark:bg-gray-700`
- 文本：`text-gray-600 dark:text-gray-300`
- 鼠标：`cursor-not-allowed`
- 不加 hover 激活色。

价格角标中 `PREORDER` 也显示 `Coming Soon / 即将上线`，不要显示 `Reserve Now / 立即预约`。

### 商品详情桌面端

当前 `ProductInfo.vue` 的 `PREORDER` 区域是可点击按钮。

调整：

- 顶部价格/状态区域显示 `Coming Soon / 即将上线`。
- CTA 按钮禁用。
- 不 emit `preorder`。
- 不显示加入购物车、数量、小计。

### 商品详情移动端

当前 `ProductInfoMobile.vue` 的 `PREORDER` 区域是可点击按钮。

调整：

- 顶部状态显示 `Coming Soon / 即将上线`。
- CTA 按钮禁用。
- 不 emit `preorder`。
- 不显示加入购物车、数量、小计。

### 商品详情页容器

`pages/product/[id].vue` 中：

- 删除或停用 `handlePreorder`。
- 移除给 `ShopProductInfo` / `ShopProductInfoMobile` 传递的 `@preorder`。
- 如果组件 emit 类型还保留 `preorder`，也不能触发跳转。

### 预售产品图片展示

两款预售产品图片来自原型资料包，多为设备透明图或高纵横比图：

- `AI Sheep Counting Camera` 主图较高。
- `AI Wool Diameter Analyzer` 主图较高。

商品卡片当前使用方形容器和 `object-cover`，可能裁切产品主体。建议：

- `PREORDER` 商品卡片图使用 `object-contain`。
- 增加内边距和浅色背景，保证设备完整可见。
- 非预售商品可保持原有 `object-cover`，避免影响已有商品展示。

示例：

```vue
<img
  :class="[
    isPreorder ? 'object-contain p-4 bg-gray-50' : 'object-cover',
    'w-full h-full object-center group-hover:scale-105 transition-transform duration-500'
  ]"
/>
```

---

## 实施步骤

1. 新增 i18n 文案 `shop.product.comingSoon`。
2. 修改 `ProductCard.vue` 的价格角标 `PREORDER` 文案。
3. 修改 `ProductCard.vue` 的 `PREORDER` CTA 为禁用按钮。
4. 删除或停用 `ProductCard.vue` 的 `handlePreorder` 跳转。
5. 修改 `ProductInfo.vue` 的 `PREORDER` 状态文案为 `comingSoon`。
6. 修改 `ProductInfo.vue` 的 `PREORDER` CTA 为禁用按钮。
7. 修改 `ProductInfoMobile.vue` 的 `PREORDER` 状态文案为 `comingSoon`。
8. 修改 `ProductInfoMobile.vue` 的 `PREORDER` CTA 为禁用按钮。
9. 修改 `pages/product/[id].vue`，移除 `handlePreorder` 跳转和 `@preorder` 绑定。
10. 检查 `PREORDER` 商品图片是否被裁切，必要时在商品卡片使用 `object-contain`。
11. 桌面端和移动端检查商品列表、商品详情。

---

## 验收标准

- [ ] 商品卡片中的 `PREORDER` 产品显示 `Coming Soon / 即将上线`。
- [ ] 商品卡片中的 `PREORDER` 按钮为灰色禁用。
- [ ] 商品卡片中的 `PREORDER` 按钮点击后不会跳转。
- [ ] 商品卡片不再携带 `productId` 跳转 `/preorder-discount`。
- [ ] 商品详情桌面端 `PREORDER` 产品显示 `Coming Soon / 即将上线`。
- [ ] 商品详情桌面端 `PREORDER` CTA 为灰色禁用。
- [ ] 商品详情桌面端点击预售 CTA 不会跳转。
- [ ] 商品详情移动端 `PREORDER` 产品显示 `Coming Soon / 即将上线`。
- [ ] 商品详情移动端 `PREORDER` CTA 为灰色禁用。
- [ ] 商品详情移动端点击预售 CTA 不会跳转。
- [ ] `ONLINE` 商品原有购买能力不回归。
- [ ] `INQUIRY_ONLY` 商品原有咨询能力不回归。
- [ ] 预售产品在商品卡片中的主图不裁掉关键设备主体。
- [ ] 首页预约入口仍可由 `SHOP-FE-017` 单独实现，不受本任务影响。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 误删首页预约文案 | 不删除 `reserveNow`，只是不在商品卡/详情预售 CTA 中使用 |
| 商品详情仍触发旧跳转 | `pages/product/[id].vue` 必须移除 `@preorder` 绑定或保证 handler 不跳转 |
| 预售设备图被裁切 | `PREORDER` 商品图使用 `object-contain` 并做移动端检查 |
| 影响线上购买商品 | 只改 `isPreorder` 分支，保留 `ONLINE` 和 `INQUIRY_ONLY` 分支 |

---

**相关文档:**

- [固定预约页任务](SHOP-FE-017-preorder-discount-form.md)
- [开发计划](../../../docs/plans/2026-06-17-preorder-discount-code-closed-loop-plan.md)
- [项目状态](../../../04-projects/nuxt-moxton.md)
