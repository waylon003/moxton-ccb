# Tech-Spec: 后台商品列表预售管理字段优化

**任务ID:** ADMIN-FE-014
**创建时间:** 2026-06-27
**状态:** 开发完成
**角色:** CRUD前端工程师
**项目:** moxton-lotadmin
**优先级:** P1
**技术栈:** Vue 3 + TypeScript + SoybeanAdmin + Naive UI
**QA_LEVEL:** smoke

---

## 概述

### 问题陈述

后台商品列表当前已经能显示购买模式，但字段和筛选对预售管理不够友好：

- 列名仍叫“商品类型”，实际含义是“购买模式”。
- 搜索区没有购买模式筛选，无法快速筛出 `PREORDER` 商品。
- 预售商品仍展示销售价和库存，容易让运营误以为可以线上购买。
- 导出数据缺少购买模式，不利于后续排查。

当前用户确认后端现有商品都是测试商品。清理测试商品并录入两款真实预售产品后，后台需要更清楚地展示这两款产品的购买模式。

### 解决方案

优化后台商品列表：

1. 把“商品类型”列改名为“购买模式”。
2. 搜索区增加购买模式筛选。
3. 商品列表请求带上 `purchaseMode`。
4. `PREORDER` 商品的价格和库存列展示为非购买语义。
5. 导出 CSV 增加分类、购买模式、标签。

### 范围

**包含:**

- 商品搜索组件增加购买模式筛选。
- 商品列表查询类型增加 `purchaseMode`。
- 商品 API 类型增加 `purchaseMode` 查询参数。
- 商品列表列名从“商品类型”改为“购买模式”。
- `PREORDER` 行的销售价显示 `暂不售卖` 或 `-`。
- `PREORDER` 行的库存显示 `预售` 或 `不适用`。
- 导出数据增加购买模式字段。

**不包含:**

- 商品表单购买模式配置，已由 `ADMIN-FE-010` 完成。
- 预售预约页内容配置，已由 `ADMIN-FE-013` 完成。
- 后端接口筛选实现，见 `BACKEND-022`。
- 预约优惠码名单页面。

---

## 开发上下文

当前相关文件：

- `src/views/product/index.vue`
- `src/views/product/modules/product-search.vue`
- `src/views/product/types.ts`
- `src/service/api/product.ts`
- `src/typings/api.d.ts`

当前列表字段：

- 分类
- 商品名称
- 商品图片
- 销售价
- 商品类型
- 标签
- 原价
- 库存
- 状态
- 创建时间
- 操作

当前搜索字段：

- 关键词
- 分类
- 最低价格
- 最高价格
- 商品状态

需要新增：

- 购买模式

---

## 技术方案

### 查询类型

`ProductListQuery` 增加：

```ts
purchaseMode?: Api.Product.PurchaseMode | ''
```

`ProductListParams` 增加：

```ts
purchaseMode?: 'ONLINE' | 'INQUIRY_ONLY' | 'PREORDER'
```

### 搜索区

新增购买模式选项：

```ts
const purchaseModeOptions = [
  { label: '全部购买模式', value: '' },
  { label: '线上购买', value: 'ONLINE' },
  { label: '仅咨询', value: 'INQUIRY_ONLY' },
  { label: '预售预约', value: 'PREORDER' }
]
```

搜索区新增 `NSelect`：

```vue
<NSelect
  v-model:value="searchForm.purchaseMode"
  :options="purchaseModeOptions"
  placeholder="购买模式"
  clearable
/>
```

`hasSearchConditions` 和 reset 逻辑都要包含 `purchaseMode`。

### 列表展示

列名调整：

```ts
title: '购买模式'
```

价格列：

- `PREORDER`：显示 `暂不售卖`，使用普通或 info 样式，不使用红色价格样式。
- 其他模式：保持当前价格显示。

库存列：

- `PREORDER`：显示 `预售` 或 `不适用`。
- `ONLINE`：保持库存数量和缺货/库存低提示。
- `INQUIRY_ONLY`：可保持库存，或显示 `不适用`。本任务至少处理 `PREORDER`。

### 导出

CSV 字段建议：

- 分类
- 商品名称
- 购买模式
- 价格
- 库存
- 状态
- 标签
- 创建时间

购买模式导出中文 label：

- `ONLINE` -> `线上购买`
- `INQUIRY_ONLY` -> `仅咨询`
- `PREORDER` -> `预售预约`

---

## 实施步骤

1. 更新 `ProductListQuery` 类型，增加 `purchaseMode`。
2. 更新 `ProductListParams` 类型，增加 `purchaseMode`。
3. 搜索表单初始值增加 `purchaseMode: ''`。
4. 搜索组件增加购买模式下拉。
5. `hasSearchConditions` 纳入 `purchaseMode`。
6. reset 逻辑清空 `purchaseMode`。
7. 商品列表页 `searchParams` 增加 `purchaseMode`。
8. 商品列表“商品类型”列改名为“购买模式”。
9. 价格列识别 `PREORDER`，显示 `暂不售卖` 或 `-`。
10. 库存列识别 `PREORDER`，显示 `预售` 或 `不适用`。
11. 导出 CSV 增加分类、购买模式、标签。
12. 联调 `BACKEND-022` 的 `purchaseMode` 筛选。

---

## 验收标准

- [ ] 搜索区可以选择“线上购买 / 仅咨询 / 预售预约”。
- [ ] 选择“预售预约”后请求参数包含 `purchaseMode=PREORDER`。
- [ ] 后端支持时，列表只显示预售商品。
- [ ] 商品列表列名显示为“购买模式”。
- [ ] `PREORDER` 商品显示“预售预约”标签。
- [ ] `PREORDER` 商品价格列不显示红色可购买价格。
- [ ] `PREORDER` 商品库存列不显示普通库存购买语义。
- [ ] 重置搜索会清空购买模式。
- [ ] 导出 CSV 包含购买模式。
- [ ] 不影响新增/编辑商品表单。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 后端尚未支持 `purchaseMode` 筛选 | 依赖 `BACKEND-022`，前端可先传参但最终验收必须联调后端 |
| 预售商品价格为空 | 价格列按购买模式优先显示，不依赖价格判断 |
| 现有字段命名变更影响用户认知 | 购买模式比商品类型更准确，和表单字段保持一致 |

---

**相关文档:**

- [后端筛选任务](../backend/BACKEND-022-admin-product-purchase-mode-filter.md)
- [开发计划](../../../docs/plans/2026-06-17-preorder-discount-code-closed-loop-plan.md)
- [项目状态](../../../04-projects/moxton-lotadmin.md)
