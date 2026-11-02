# Tech-Spec: 后台商品列表购买模式筛选支持

**任务ID:** BACKEND-022
**创建时间:** 2026-06-27
**状态:** 开发完成
**角色:** 后端工程师
**项目:** moxton-lotapi
**优先级:** P1
**技术栈:** Node.js + Koa + TypeScript + Prisma + MySQL
**QA_LEVEL:** smoke

---

## 概述

### 问题陈述

后台商品列表已经返回 `purchaseMode`，但管理端列表接口 `/products/admin/all` 当前不支持按购买模式筛选。后续清理测试商品并录入两款真实预售产品后，运营需要快速筛选 `PREORDER` 商品，确认预售产品配置是否正确。

### 解决方案

在后台商品列表接口增加 `purchaseMode` 查询参数，支持筛选：

- `ONLINE`
- `INQUIRY_ONLY`
- `PREORDER`

接口仍保留现有 keyword、categoryId、price、status、sort 参数。

### 范围

**包含:**

- `/products/admin/all` 支持 `purchaseMode` 查询参数。
- 校验 `purchaseMode` 合法性。
- 非法值返回明确参数错误。
- 商品列表响应继续返回 `purchaseMode` 和 `hasPrice`。

**不包含:**

- 前台商城商品列表筛选。
- 后台页面 UI。
- 商品购买模式模型改造。
- 预约发码接口。

---

## 开发上下文

当前相关文件：

- `src/controllers/Product.ts`
- `src/models/Product.ts`
- `src/utils/purchaseMode.ts`
- `src/routes/products.ts`

当前接口：

```http
GET /products/admin/all
```

当前已支持查询：

- `keyword`
- `categoryId`
- `minPrice`
- `maxPrice`
- `status`
- `sortBy`
- `sortOrder`
- `pageNum`
- `pageSize`

当前缺少：

- `purchaseMode`

---

## API 设计

### 后台商品列表

```http
GET /products/admin/all?purchaseMode=PREORDER&pageNum=1&pageSize=10
```

合法值：

```ts
type PurchaseMode = 'ONLINE' | 'INQUIRY_ONLY' | 'PREORDER'
```

非法值响应建议：

```json
{
  "success": false,
  "message": "Validation failed",
  "errors": ["purchaseMode must be one of ONLINE, INQUIRY_ONLY, PREORDER"]
}
```

### 查询逻辑

controller 中读取：

```ts
const { purchaseMode } = ctx.query
```

校验：

```ts
if (purchaseMode && !isValidPurchaseMode(purchaseMode)) {
  return ctx.validationError(['purchaseMode must be one of ONLINE, INQUIRY_ONLY, PREORDER'])
}
```

拼接 where：

```ts
if (purchaseMode) {
  where.purchaseMode = purchaseMode
}
```

---

## 实施步骤

1. 在 `getProductsForAdmin` 中读取 `purchaseMode`。
2. 复用或引入现有 `isValidPurchaseMode` 校验。
3. 合法时写入 `where.purchaseMode`。
4. 非法时返回 validation error。
5. 确认 `productModel.getProductsForAdmin` 不需要额外改动，因其接受 `where`。
6. 用接口请求验证 `ONLINE / INQUIRY_ONLY / PREORDER` 三种筛选。
7. 验证不传 `purchaseMode` 时原列表不变。

---

## 验收标准

- [ ] `/products/admin/all?purchaseMode=PREORDER` 只返回预售商品。
- [ ] `/products/admin/all?purchaseMode=ONLINE` 只返回线上购买商品。
- [ ] `/products/admin/all?purchaseMode=INQUIRY_ONLY` 只返回仅咨询商品。
- [ ] 非法 `purchaseMode` 返回明确错误。
- [ ] 不传 `purchaseMode` 时保持原列表行为。
- [ ] 响应中仍包含 `purchaseMode` 和 `hasPrice`。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 历史商品购买模式为空 | 当前数据库字段已有默认值，接口仍保留 `hasPrice` 兼容 |
| 前端先发筛选参数但后端未支持 | 本任务应先于 ADMIN-FE-014 执行或同步完成 |

---

**相关文档:**

- [开发计划](../../../docs/plans/2026-06-17-preorder-discount-code-closed-loop-plan.md)
- [项目状态](../../../04-projects/moxton-lotapi.md)
