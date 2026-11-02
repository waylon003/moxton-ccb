# Tech-Spec: 后台产品购买模式配置

**任务ID:** ADMIN-FE-010
**创建时间:** 2026-06-17
**状态:** 已完成
**角色:** CRUD前端工程师
**项目:** moxton-lotadmin
**优先级:** P0
**技术栈:** Vue 3 + TypeScript + SoybeanAdmin + Naive UI
**QA_LEVEL:** smoke

---


## 概述

### 问题陈述

管理后台产品类型当前通过 `hasPrice` 显示“购买商品 / 咨询商品”，产品表单也用“价格留空则为咨询商品”的隐式规则。新功能需要后台明确设置购买模式，包括“预售预约”。

### 解决方案

在产品管理中增加 `purchaseMode` 字段配置和展示，提交给后端。

购买模式：

- `ONLINE`：线上购买
- `INQUIRY_ONLY`：仅咨询
- `PREORDER`：预售预约

### 范围

**包含:**
- 产品类型定义增加 `purchaseMode`。
- 产品新增/编辑表单增加“购买模式”选择。
- 产品列表“商品类型”列改为基于 `purchaseMode` 展示。
- 创建/更新商品时提交 `purchaseMode`。
- 历史数据无 `purchaseMode` 时回退到 `hasPrice`。

**不包含:**
- 预约优惠码名单页面。
- 邮件重发。
- 官网页面。

---

## 开发上下文

重点文件：

- `src/service/api/product.ts`
- `src/views/product/types.ts`
- `src/views/product/modules/product-form.vue`
- `src/views/product/index.vue`

现有实现：

- `product-form.vue` 的价格提示写着“选填（留空则为咨询商品）”。
- `product/index.vue` 的“商品类型”列使用 `row.hasPrice`。
- `productService` 类型未包含 `purchaseMode`。

### 依赖项

- 前置任务：`BACKEND-017`
- 后端需要返回并接收 `purchaseMode`。

---

## 技术方案

### 页面结构

在商品表单基础信息或价格库存区域加入：

```text
购买模式：线上购买 / 仅咨询 / 预售预约
```

建议靠近价格字段，因为它决定用户侧行为。

### 数据流

表单数据增加：

```ts
purchaseMode: 'ONLINE' | 'INQUIRY_ONLY' | 'PREORDER'
```

初始化策略：

- 编辑时优先使用 `props.product.purchaseMode`。
- 若缺失，则 `hasPrice ? 'ONLINE' : 'INQUIRY_ONLY'`。
- 新建默认 `ONLINE`。

### API 调用

使用现有接口：

- `POST /products`
- `PUT /products/:id`
- `GET /products/admin/all`

---

## 实施步骤

1. 更新产品 API 类型，增加 `purchaseMode`。
2. 更新 `ProductFormData`，增加 `purchaseMode`。
3. 表单新增 `NSelect` 购买模式字段。
4. 修改价格输入提示，不再强调“留空则咨询商品”。
5. 编辑初始化时正确回填购买模式。
6. 产品列表“商品类型”列改为显示三种模式。
7. 保存时提交 `purchaseMode`。

---

## 验收标准

- [ ] 新建商品时可以选择购买模式。
- [ ] 编辑商品时可以回填并修改购买模式。
- [ ] 商品列表正确显示“线上购买 / 仅咨询 / 预售预约”。
- [ ] 历史商品无 `purchaseMode` 时仍能显示合理类型。
- [ ] 提交创建/更新请求时包含 `purchaseMode`。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 后端字段尚未完成 | 若接口缺字段，按依赖阻塞回传，不要用前端假字段上线 |
| 历史数据为空 | 用 `hasPrice` 兜底显示 |

---

**相关文档:**
- [开发计划](../../docs/plans/2026-06-17-preorder-discount-code-closed-loop-plan.md)
- [项目状态](../../04-projects/moxton-lotadmin.md)
