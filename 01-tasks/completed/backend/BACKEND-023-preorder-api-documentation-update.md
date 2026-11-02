# Tech-Spec: 预售预约接口文档更新

**任务ID:** BACKEND-023
**创建时间:** 2026-06-27
**状态:** 开发完成
**角色:** 后端工程师
**项目:** moxton-lotapi / moxton-ccb
**优先级:** P0
**技术栈:** Markdown + API 文档
**QA_LEVEL:** smoke

---

## 概述

### 问题陈述

`BACKEND-018` 和 `BACKEND-019` 完成后，预售预约相关 API 会发生关键变化：

- 预约提交从单 `productId` 改为 `productIds`。
- 一次提交可以选择 1 到 2 个产品。
- 后端按产品拆分 lead/code/email。
- 邮件状态按每条 lead 返回。
- 后台预约列表、详情、重发接口可用。
- 商品后台列表新增 `purchaseMode` 筛选。
- 优惠码有效期从配置读取，本次配置为 2026 年 12 月 31 日。

如果不及时更新 `02-api` 文档，官网前端、后台前端和后续维护都会按旧接口理解，容易接错字段或遗漏错误状态。

### 解决方案

在 `BACKEND-018`、`BACKEND-019`、`BACKEND-022` 完成后，更新 `E:\moxton-ccb\02-api` 下的接口文档和 changelog。

建议新增独立文档：

```text
02-api/preorder-discounts.md
```

同时更新：

```text
02-api/products.md
02-api/README.md
02-api/CHANGELOG.md
```

---

## 范围

**包含:**

- 新增预售预约接口文档。
- 记录用户侧预约提交接口。
- 记录后台预约列表、详情、重发接口。
- 记录请求字段、响应字段、错误码。
- 记录 `productIds` 多产品提交语义。
- 记录“一产品一优惠码、一产品一邮件”的邮件语义。
- 更新商品接口文档，补充后台列表 `purchaseMode` 筛选。
- 更新 API README 索引。
- 更新 API changelog。

**不包含:**

- 业务代码实现。
- 前端页面开发。
- 邮件模板实现。
- OpenAPI 自动生成。

---

## 开发上下文

当前 API 文档目录：

- `02-api/README.md`
- `02-api/CHANGELOG.md`
- `02-api/products.md`
- 其他模块文档

需要参考的任务：

- `BACKEND-018-preorder-discount-claim-api.md`
- `BACKEND-019-preorder-email-and-admin-api.md`
- `BACKEND-022-admin-product-purchase-mode-filter.md`

---

## 文档内容要求

### 1. 新增 `02-api/preorder-discounts.md`

必须包含以下接口：

```http
POST /preorder-discounts/claim
GET /preorder-discounts/admin/leads
GET /preorder-discounts/admin/leads/:id
POST /preorder-discounts/admin/leads/:id/resend
```

### 2. 用户侧提交接口

必须写明请求体：

```json
{
  "firstName": "Morgan",
  "lastName": "Carter",
  "phone": "+61 400 000 000",
  "email": "morgan@example.com",
  "ranchName": "Carter Ranch",
  "address": "1200 Valley Road",
  "productIds": ["product_a_id", "product_b_id"],
  "source": "home_preorder"
}
```

必须写明：

- `productIds` 必填。
- `productIds` 是数组。
- 至少 1 个产品。
- 当前最多 2 个产品。
- 每个产品必须是 `PREORDER`。
- 同邮箱同产品去重。
- 同邮箱不同产品可分别领取。
- 页面不要求登录。

### 3. 响应结构

必须记录逐产品 `items`：

```json
{
  "success": true,
  "data": {
    "status": "SENT",
    "message": "Your preorder discount request has been received.",
    "submissionId": "pre_abc123",
    "items": [
      {
        "productId": "product_a_id",
        "productName": "AI Sheep Counting Camera",
        "leadId": "lead_a_id",
        "status": "SENT",
        "duplicate": false,
        "emailStatus": "SENT"
      }
    ]
  }
}
```

状态至少说明：

- `SENT`
- `PENDING`
- `FAILED`
- `DUPLICATE`
- `PARTIAL_DUPLICATE`
- `PARTIAL_SENT`

### 4. 错误码

至少记录：

- `PREORDER_DISCOUNT_ALREADY_CLAIMED`
- 产品不存在。
- 产品不是 `PREORDER`。
- `productIds` 缺失。
- `productIds` 超过上限。
- 邮箱格式错误。

### 5. 有效期配置

必须写明：

- 优惠码有效期来自后端配置。
- 本次上线配置为 2026 年 12 月 31 日。
- API 响应中后台详情可返回 `expiresAt`。
- 前端不要自己推导有效期。

### 6. 邮件语义

必须写明：

- 一个产品对应一个优惠码。
- 一个产品对应一封邮件。
- 用户选择两个产品时发送两封邮件。
- 每封邮件只展示对应的一个产品名称。
- 邮件模板基于 `E:\邮件模版\moxton-discount-email.html`。

### 7. 后台接口

后台列表查询参数：

- `pageNum`
- `pageSize`
- `keyword`
- `productId`
- `emailStatus`
- `source`
- `submissionId`，如果实现了该字段

后台详情字段：

- 表单信息。
- 产品信息。
- 优惠码。
- 折扣比例。
- 过期时间。
- 邮件状态。
- 发送时间。
- 失败原因。
- 重试次数。

重发接口：

- 使用原优惠码。
- 不生成新优惠码。
- 返回最新邮件状态。

### 8. 更新 `products.md`

补充：

```http
GET /products/admin/all?purchaseMode=PREORDER
```

说明：

- `purchaseMode` 可选。
- 合法值：`ONLINE`、`INQUIRY_ONLY`、`PREORDER`。
- 用于后台筛选购买模式。

---

## 实施步骤

1. 新增 `02-api/preorder-discounts.md`。
2. 按实际后端实现填写请求、响应和错误码。
3. 更新 `02-api/products.md`，补充 `purchaseMode` 筛选。
4. 更新 `02-api/README.md`，加入预售预约接口索引。
5. 更新 `02-api/CHANGELOG.md`。
6. 对照 `BACKEND-018/019/022` 实际代码确认字段一致。
7. 将接口文档作为 `SHOP-FE-017`、`ADMIN-FE-011`、`ADMIN-FE-012` 的接入依据。

---

## 验收标准

- [ ] `02-api/preorder-discounts.md` 已新增。
- [ ] 文档包含用户侧预约提交接口。
- [ ] 文档包含后台列表、详情、重发接口。
- [ ] 文档使用 `productIds`，不再使用旧单 `productId` 作为提交字段。
- [ ] 文档说明一个产品一个优惠码、一封邮件。
- [ ] 文档说明每封邮件只显示一个产品名称。
- [ ] 文档说明有效期来自配置，本次为 2026 年 12 月 31 日。
- [ ] `products.md` 已补充后台商品列表 `purchaseMode` 筛选。
- [ ] `README.md` 已加入预售预约接口入口。
- [ ] `CHANGELOG.md` 已记录本次接口变更。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 文档和代码不一致 | 必须在 BACKEND-018/019/022 实现后按实际响应更新 |
| 前端接入旧字段 | 文档明确 `productIds` 是唯一推荐提交字段 |
| 邮件模板误解 | 文档明确一封邮件只显示一个产品名 |

---

**相关文档:**

- [BACKEND-018](BACKEND-018-preorder-discount-claim-api.md)
- [BACKEND-019](BACKEND-019-preorder-email-and-admin-api.md)
- [BACKEND-022](BACKEND-022-admin-product-purchase-mode-filter.md)
- [API 文档目录](../../../02-api/README.md)
