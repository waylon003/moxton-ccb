# Tech-Spec: 后台产品预售预约页内容配置

**任务ID:** ADMIN-FE-013
**创建时间:** 2026-06-23
**最后更新:** 2026-06-27
**状态:** 已完成
**角色:** CRUD前端工程师
**项目:** moxton-lotadmin
**优先级:** P1
**技术栈:** Vue 3 + TypeScript + SoybeanAdmin + Naive UI
**QA_LEVEL:** smoke

---

## 概述

> 2026-06-27 备注：本任务已完成并保留产品宣传视频 URL 配置能力。但当前官网预约页方案已调整为固定页面，不展示视频；本阶段 `SHOP-FE-017` 不应依赖 `videoUrl`。后台已存在的视频字段可作为兼容字段保留，后续有视频展示需求时再启用。

### 问题陈述

后台可以把产品设置为 `PREORDER`。早期方案中，不同预售产品的预约页需要展示不同的产品宣传图、产品宣传说明和产品宣传视频，因此后台产品表单增加了 `metadata.preorder` 配置入口。当前最新方案已调整为固定预约页，官网本阶段主要使用商品主图和基础说明，不使用视频。

### 解决方案

在产品新增/编辑表单中，当购买模式为“预售预约”时显示“预售预约页内容”配置区，并保存到 `metadata.preorder`。当前官网预约页不再由单个 `productId` 驱动，但仍可以读取预售商品列表，并在需要时使用 `metadata.preorder.description` 或 `metadata.preorder.heroImage` 作为商品基础字段的补充。表单字段始终使用统一版本，不做按产品配置。

### 范围

**包含:**
- 产品类型增加 `metadata` 和 `metadata.preorder` 类型。
- 产品表单增加预售预约页配置区。
- 支持配置产品宣传图、产品宣传说明；产品宣传视频 URL 作为历史兼容字段保留，本阶段官网不使用。
- 编辑产品时回填已有配置。
- 保存产品时合并并提交 `metadata.preorder`。

**不包含:**
- 官网预约页实现。
- 后端预约发码接口。
- 独立活动管理系统。

---

## 开发上下文

重点文件：

- `src/service/api/product.ts`
- `src/views/product/types.ts`
- `src/views/product/modules/product-form.vue`

依赖后端：

- `Product.metadata` 可以保存并返回 `preorder` 配置。

### 依赖项

- 前置任务：`ADMIN-FE-010`
- 前置任务：`BACKEND-020`

---

## 技术方案

### 配置结构

```ts
type ProductPreorderPageContent = {
  heroImage?: string
  description?: string
  videoUrl?: string // 历史兼容字段，本阶段官网不使用
}
```

保存到：

```ts
product.metadata.preorder
```

### 表单字段

当 `purchaseMode === 'PREORDER'` 时显示：

- 产品宣传图：建议复用现有上传组件，单图。
- 产品宣传说明：建议用 textarea 或富文本，按官网页面实际展示需求决定。
- 产品宣传视频：历史兼容字段，可继续保留输入；本阶段官网不读取、不展示。

### 默认值策略

如果没有配置 `metadata.preorder`，表单可以默认：

- `description` 使用产品描述。
- `heroImage` 使用第一张产品图。
- `videoUrl` 为空。

注意：默认值用于 UI 展示即可，保存时只保存用户明确配置后的内容，避免不必要的数据膨胀。

---

## 实施步骤

1. 更新产品 API 类型，增加 `metadata`。
2. 在产品表单状态中增加 `preorderPageContent`。
3. 编辑产品时从 `product.metadata.preorder` 回填。
4. 当购买模式为 `PREORDER` 时显示配置区。
5. 实现产品宣传图上传或选择。
6. 实现产品宣传说明编辑。
7. 保留产品宣传视频 URL 输入作为兼容字段，不作为本阶段官网展示依赖。
8. 保存时把配置合并到 `metadata.preorder` 并提交。
9. 验证新建和编辑预售产品的数据回显。

---

## 验收标准

- [ ] 购买模式为“预售预约”时显示预约页内容配置区。
- [ ] 可以配置产品宣传图、产品宣传说明；视频 URL 如已存在可保留但不影响官网预约页。
- [ ] 保存后再次编辑可以正确回填。
- [ ] 切换为非预售模式时不影响历史配置，但 UI 可以隐藏。
- [ ] 提交产品时包含 `metadata.preorder`。
- [ ] 未配置时官网仍可用产品基础图文兜底。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 覆盖 metadata 其他字段 | 保存时合并原 `metadata`，只更新 `preorder` |
| 上传组件复用成本 | 可先使用图片 URL 输入，后续再优化为上传 |
| 非预售产品误填 | 配置区只在 `PREORDER` 下显示 |

---

**相关文档:**
- [开发计划](../../docs/plans/2026-06-17-preorder-discount-code-closed-loop-plan.md)
- [项目状态](../../04-projects/moxton-lotadmin.md)

