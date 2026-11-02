# Tech-Spec: 清理后端测试商品数据

**任务ID:** BACKEND-021
**创建时间:** 2026-06-27
**状态:** 开发完成
**角色:** 后端工程师
**项目:** moxton-lotapi
**优先级:** P0
**技术栈:** Node.js + Koa + TypeScript + Prisma + MySQL
**QA_LEVEL:** smoke

---

## 概述

### 问题陈述

当前后端商品列表中的商品都是测试用商品，不是真实产品。预售预约功能即将依赖官网商品列表中的 `PREORDER` 产品展示两款真实预售产品。如果不先清理测试商品，官网预约页可能读取并展示错误商品，后台录入真实产品时也容易混淆。

### 解决方案

在录入真实预售产品之前，先清理当前测试商品数据。优先使用项目已有商品删除能力进行软删除，即设置 `Product.isDeleted = true`，避免直接物理删除导致订单、购物车、咨询单等历史关联数据异常。

清理完成后，后台商品列表应为空或只剩明确确认需要保留的真实商品。随后由业务方在后台管理系统重新录入两款真实预售产品，并设置购买模式为 `PREORDER`。

### 范围

**包含:**

- 盘点当前数据库商品列表。
- 确认当前商品均为测试商品。
- 使用现有商品删除接口或安全脚本批量软删除测试商品。
- 清理后验证前台商品列表不再返回测试商品。
- 清理后验证后台删除列表可看到被软删除商品，或数据库 `isDeleted = true`。
- 输出清理结果：删除数量、失败商品 ID、保留商品 ID。

**不包含:**

- 创建真实预售产品。
- 删除分类、订单、购物车、咨询单、预约线索。
- 物理删除商品记录。
- 清理图片存储文件。
- 修改商品模型结构。

---

## 开发上下文

当前相关文件：

- `src/routes/products.ts`
- `src/controllers/Product.ts`
- `src/models/Product.ts`
- `prisma/schema.prisma`

当前已有能力：

- `DELETE /products/:id`
- `DELETE /products/batch`
- `POST /products/:id/restore`
- `POST /products/batch/restore`
- `GET /products/deleted`
- `Product.isDeleted` 逻辑删除字段
- `productModel.batchDelete(productIds)` 中已使用 `isDeleted = true`

需要注意：

- 当前商品都是测试商品，但执行前仍必须查询并记录商品清单。
- 不允许直接 `truncate products`。
- 不允许直接物理删除商品，除非用户再次明确要求。
- 如果商品存在订单、购物车或咨询关联，软删除仍是安全路径。

---

## 技术方案

### 推荐清理方式

优先使用现有后台 API 或 controller 能力：

```http
DELETE /products/batch
```

请求体：

```json
{
  "productIds": ["product_id_1", "product_id_2"]
}
```

如果批量接口不稳定，可以使用单个删除接口循环调用：

```http
DELETE /products/:id
```

如果需要脚本清理，脚本也必须只做软删除：

```ts
await prisma.product.updateMany({
  where: {
    isDeleted: false
  },
  data: {
    isDeleted: true,
    status: 0
  }
})
```

脚本执行前必须先打印待清理商品列表，确认数量和名称。

### 清理前查询

需要记录：

- `id`
- `name`
- `purchaseMode`
- `status`
- `isDeleted`
- `createdAt`

建议查询条件：

```ts
where: {
  isDeleted: false
}
```

### 清理后验证

验证点：

1. 普通商品列表不再返回测试商品。
2. 后台商品列表不再展示未删除测试商品。
3. `GET /products/deleted` 可以看到被软删除商品，或数据库查询 `isDeleted = true`。
4. 商品恢复接口仍可恢复单个商品，证明没有物理删除。

---

## 实施步骤

1. 查询当前未删除商品列表。
2. 输出商品清单给负责人确认，或确认“当前所有商品均为测试商品”的前提。
3. 收集所有未删除测试商品 ID。
4. 调用现有批量删除能力，或执行只做软删除的安全脚本。
5. 记录删除成功数量和失败 ID。
6. 查询未删除商品列表，确认测试商品已不再出现。
7. 查询已删除商品列表，确认可追溯。
8. 不创建任何新商品，等待业务方在后台录入真实预售产品。

---

## 验收标准

- [ ] 清理前已输出待删除商品清单。
- [ ] 当前测试商品已被软删除。
- [ ] 没有执行物理删除。
- [ ] 商品表中记录仍可追溯或可恢复。
- [ ] 官网商品列表不再返回测试商品。
- [ ] 后台普通商品列表不再展示测试商品。
- [ ] 清理结果包含成功数量和失败 ID。
- [ ] 清理后不自动创建真实预售产品。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 误删真实商品 | 执行前输出清单；当前用户已确认现有商品均为测试商品 |
| 物理删除破坏关联数据 | 只允许软删除，不允许 truncate 或 deleteMany 物理删除 |
| 清理后官网无商品 | 这是预期中间态；后续由业务方录入两款真实预售产品 |
| 后台缓存导致仍显示 | 清理后刷新后台并重新请求接口 |

---

## 后续衔接

清理完成后，业务方需要在后台管理系统录入两款真实预售产品：

- `AI Sheep Counting Camera`
- `AI Wool Diameter Analyzer`

配置资料见：

- `E:\moxton-ccb\docs\assets\preorder-products\README.md`
- `E:\moxton-ccb\docs\assets\preorder-products\preorder-products.json`

---

**相关文档:**

- [预售产品资料包](../../../docs/assets/preorder-products/README.md)
- [开发计划](../../../docs/plans/2026-06-17-preorder-discount-code-closed-loop-plan.md)
- [项目状态](../../../04-projects/moxton-lotapi.md)
