# Tech-Spec: 产品表单预售模式简化与库存校验修正

**任务ID:** ADMIN-FE-015
**创建时间:** 2026-06-27
**状态:** 开发完成
**角色:** CRUD前端工程师
**项目:** moxton-lotadmin
**优先级:** P0
**技术栈:** Vue 3 + TypeScript + SoybeanAdmin + Naive UI
**QA_LEVEL:** smoke

---

## 概述

### 问题陈述

当前后台新增商品表单在选择或使用 `PREORDER` 预售模式时，会显示“预售预约页内容”配置区，包括：

- 产品宣传图
- 产品宣传说明
- 产品宣传视频

这已经不符合当前最新方案。当前官网预约页是固定页面，不再按单个产品渲染产品专属预约页内容；预约页产品展示区只读取 `PREORDER` 商品列表的主图、名称、描述等基础商品信息。

另外，当前商品表单仍强制校验库存数量。对预售产品来说库存不参与购买，也不应该成为录入阻塞项。

### 解决方案

修正产品表单：

1. `PREORDER` 模式不再显示“预售预约页内容”配置区。
2. 不再让运营填写产品宣传视频。
3. 预售产品只需要填写基础商品信息：
   - 商品名称
   - 商品分类
   - 商品描述
   - 购买模式 = `PREORDER`
   - 商品图片，至少一张主图
   - 商品标签，可选但建议填写
4. `PREORDER` 模式下库存不必填，保存时默认使用 `0`。
5. `PREORDER` 模式下价格也不必填。
6. 保留历史 `metadata.preorder` 类型兼容，但表单不主动展示该配置区。

### 范围

**包含:**

- 修改产品新增/编辑表单的 `PREORDER` 条件 UI。
- 隐藏或移除“预售预约页内容”区块。
- 隐藏或移除“产品宣传视频”输入。
- `PREORDER` 模式下库存不作为必填校验。
- `PREORDER` 模式下库存保存默认为 `0`。
- 调整提示文案，明确预售商品库存不参与线上购买。
- 确保编辑历史商品时不丢失已有 `metadata.preorder`。

**不包含:**

- 后端商品模型修改。
- 删除数据库中的 `metadata.preorder`。
- 官网预约页实现。
- 后台预约名单页面。

---

## 开发上下文

当前相关文件：

- `src/views/product/modules/product-form.vue`
- `src/views/product/types.ts`
- `src/service/api/product.ts`
- `src/typings/api.d.ts`

当前已发现的问题：

- `product-form.vue` 中 `isPreorderMode` 为 true 时展示“预售预约页内容”。
- “预售预约页内容”里仍有“产品宣传视频”。
- 表单校验中 `stock` 使用 `defaultRequiredRule`，导致库存必填。
- 新建商品默认 `stock: 0`，但 UI 上仍体现为必填购买库存语义。

---

## 技术方案

### 表单显示规则

购买模式：

- `ONLINE`：线上购买。
- `INQUIRY_ONLY`：仅咨询。
- `PREORDER`：预售展示，不支持购买。

字段显示建议：

| 字段 | ONLINE | INQUIRY_ONLY | PREORDER |
|------|--------|--------------|----------|
| 商品名称 | 必填 | 必填 | 必填 |
| 商品分类 | 必填 | 必填 | 必填 |
| 商品描述 | 必填 | 必填 | 必填 |
| 商品图片 | 必填或建议必填 | 必填或建议必填 | 建议必填，预约页依赖主图 |
| 购买模式 | 必填 | 必填 | 必填 |
| 销售价格 | 必填或选填按现有规则 | 不必填 | 不必填 |
| 原价 | 可选 | 可选 | 可选或隐藏 |
| 库存数量 | 必填 | 不必填 | 不必填 |
| 预售预约页内容 | 不显示 | 不显示 | 不显示 |
| 产品宣传视频 | 不显示 | 不显示 | 不显示 |
| 规格参数 | 可选 | 可选 | 可选 |
| 标签 | 可选 | 可选 | 建议填写 |

### 库存校验

当前：

```ts
stock: [defaultRequiredRule, { type: 'number', min: 0, message: '商品库存不能小于0', trigger: 'blur' }]
```

建议改为根据购买模式动态校验：

- `ONLINE`：库存必填且 `>= 0`。
- `INQUIRY_ONLY`：库存可不填，保存时默认 `0`。
- `PREORDER`：库存可不填，保存时默认 `0`。

可实现方式：

```ts
stock: [
  {
    validator: (_rule, value) => {
      if (formData.value.purchaseMode !== 'ONLINE') return true
      return typeof value === 'number' && value >= 0
    },
    message: '线上购买商品需要填写库存数量',
    trigger: ['blur', 'change']
  }
]
```

如果 Naive UI 表单校验中访问 `formData` 不方便，也可以在 `handleSubmit` 中做模式判断：

- `ONLINE` 缺库存则报错。
- `PREORDER` / `INQUIRY_ONLY` 提交前统一 `stock = 0`。

### 提交数据处理

提交前归一化：

```ts
const submitData = {
  ...formData.value,
  stock: formData.value.purchaseMode === 'ONLINE' ? formData.value.stock : 0,
  metadata: buildSubmitMetadata()
}
```

`buildSubmitMetadata` 调整：

- 不再因为 `purchaseMode === 'PREORDER'` 自动写入 `metadata.preorder`。
- 编辑历史商品时，如果已有 `metadata.preorder`，可以保留原值，不主动清空。
- 如果表单已不展示预售配置区，就不要让空值覆盖历史 `metadata.preorder`。

### UI 调整

在价格/库存区域增加提示：

- `PREORDER`：`预售商品暂不支持线上购买，库存和价格不会用于结账。`
- `INQUIRY_ONLY`：`仅咨询商品不参与线上购买。`

库存输入：

- `ONLINE`：显示正常库存输入。
- `PREORDER`：可以隐藏库存输入，或禁用并显示 `不适用`。
- `INQUIRY_ONLY`：可以隐藏库存输入，或禁用并显示 `不适用`。

建议本任务选择更简单方案：

- `ONLINE` 显示库存输入。
- 非 `ONLINE` 隐藏库存输入，并在提示文案说明库存不适用。

---

## 实施步骤

1. 修改 `product-form.vue`，移除或隐藏“预售预约页内容”区块。
2. 移除或隐藏“产品宣传视频”输入。
3. 修改库存校验规则，让库存只对 `ONLINE` 商品必填。
4. 提交前对非 `ONLINE` 商品设置 `stock = 0`。
5. 调整 `buildSubmitMetadata`，不再因 `PREORDER` 自动写入空的 `metadata.preorder`。
6. 编辑历史商品时保留已有 `metadata`，不要误清空。
7. 在购买模式区域增加非线上购买提示文案。
8. 验证新建 `PREORDER` 商品时不需要填写库存。
9. 验证新建 `PREORDER` 商品时不会看到产品宣传视频。
10. 验证新建 `ONLINE` 商品时库存校验仍正常。

---

## 验收标准

- [ ] 新增商品选择 `PREORDER` 时，不显示“预售预约页内容”区块。
- [ ] 新增商品选择 `PREORDER` 时，不显示“产品宣传视频”输入。
- [ ] 新增 `PREORDER` 商品不需要填写库存数量。
- [ ] 新增 `PREORDER` 商品提交时 `stock` 默认为 `0`。
- [ ] 新增 `PREORDER` 商品仍可以上传商品主图。
- [ ] 新增 `PREORDER` 商品仍可以填写商品描述和标签。
- [ ] 新增 `ONLINE` 商品库存校验仍正常。
- [ ] 编辑历史带 `metadata.preorder` 的商品时，不会因为表单隐藏而清空历史 metadata。
- [ ] 商品保存后购买模式仍正确提交。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 隐藏预售配置区导致历史 metadata 丢失 | 保存时合并 metadata，不主动提交空 preorder 覆盖历史值 |
| 非线上商品库存为空导致后端报错 | 提交前统一把非 ONLINE 的 `stock` 设为 0 |
| 后续又需要产品专属预约页 | 保留 `metadata.preorder` 类型和后端字段，只是不在当前表单主动展示 |

---

**相关文档:**

- [开发计划](../../../docs/plans/2026-06-17-preorder-discount-code-closed-loop-plan.md)
- [预售产品资料包](../../../docs/assets/preorder-products/README.md)
- [项目状态](../../../04-projects/moxton-lotadmin.md)
