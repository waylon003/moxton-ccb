# Tech-Spec: 预售预约优惠码数据模型与多产品提交接口

**任务ID:** BACKEND-018
**创建时间:** 2026-06-17
**最后更新:** 2026-06-27
**状态:** 开发完成
**角色:** 后端工程师
**项目:** moxton-lotapi
**优先级:** P1
**技术栈:** Node.js + Koa + TypeScript + Prisma + MySQL
**QA_LEVEL:** full

---

## 概述

### 问题陈述

官网预约页现在是固定页面，不再由单个 `productId` 驱动。用户填写一次表单后，会在提交前弹窗选择 1 到 2 个预售产品。后端需要接收 `productIds`，并按每个产品分别生成优惠码、保存预约线索。

当前 `moxton-lotapi` 已经存在单产品版本：

- `prisma/schema.prisma` 已有 `PreorderDiscountLead`
- `src/controllers/PreorderDiscount.ts` 已有 `POST /preorder-discounts/claim`
- `src/models/PreorderDiscountLead.ts` 已有单 `productId` 的 `claim`
- `src/routes/preorder-discounts.ts` 已注册路由

当前缺口是接口仍接收单个 `productId`，不适配前端最新的多产品选择弹窗。

### 解决方案

保留“一产品一条预约记录、一产品一个优惠码、一产品一封邮件”的简单模型，把提交接口从单 `productId` 升级为 `productIds` 数组。

核心规则：

- 请求体必须传 `productIds: string[]`。
- `productIds` 至少 1 个。
- 本阶段最多 2 个，和当前两款预售产品匹配。
- 每个 `productId` 必须存在且 `purchaseMode = PREORDER`。
- 同一邮箱同一产品继续按 `normalizedEmail + productId` 去重。
- 同一邮箱可以预约不同产品，并分别得到各自产品的优惠码。
- 一次提交选择两个产品时，后端创建两条 lead，生成两个 code。
- 邮件发送由 `BACKEND-019` 负责，但本任务的数据结构和返回值要能承载逐产品结果。

### 范围

**包含:**

- 调整预约提交接口请求体，从 `productId` 改为 `productIds`。
- 校验 `productIds` 数组。
- 批量查询和校验产品存在、上架、`purchaseMode = PREORDER`。
- 对每个产品分别创建或识别重复预约记录。
- 保留 `PreorderDiscountLead` 一产品一行的数据模型。
- 推荐增加 `submissionId` 字段，把同一次表单提交下的多条记录关联起来。
- 返回逐产品处理结果，便于前端展示成功、重复、失败。

**不包含:**

- Resend 邮件发送实现，详见 `BACKEND-019`。
- 后台列表/详情/重发接口，详见 `BACKEND-019`。
- 结账优惠码抵扣。
- 单独活动表或优惠码规则后台。

---

## 开发上下文

当前相关文件：

- `prisma/schema.prisma`
- `src/controllers/PreorderDiscount.ts`
- `src/models/PreorderDiscountLead.ts`
- `src/routes/preorder-discounts.ts`
- `src/routes/index.ts`
- `src/utils/purchaseMode.ts`

当前代码状态：

- `ClaimRequestBody` 里仍是 `productId?: unknown`。
- controller 会先查单个 product，再调用 `preorderDiscountLeadModel.claim`。
- model 的 `ClaimPreorderDiscountInput` 仍是单个 `productId`。
- Prisma 复合唯一索引 `@@unique([normalizedEmail, productId])` 是正确的，应保留。

### 依赖项

- 前置任务：`BACKEND-017`
- 需要 `Product.purchaseMode` 字段可用。

---

## 数据模型

### 当前模型保留

继续使用 `PreorderDiscountLead` 表保存预约和优惠码信息。

推荐模型：

```prisma
model PreorderDiscountLead {
  id              String   @id @default(cuid())
  submissionId    String?
  firstName       String
  lastName        String
  phone           String
  email           String
  normalizedEmail String
  ranchName       String?
  address         String?  @db.Text
  source          String?
  userId          String?

  productId       String
  productName     String
  code            String   @unique
  discountPercent Int      @default(15)
  expiresAt       DateTime
  codeStatus      String   @default("ACTIVE")
  redeemedAt      DateTime?
  orderId         String?

  emailStatus     String   @default("PENDING")
  emailSentAt     DateTime?
  emailError      String?  @db.Text
  emailRetryCount Int      @default(0)

  createdAt       DateTime @default(now())
  updatedAt       DateTime @updatedAt

  product Product @relation(fields: [productId], references: [id])

  @@unique([normalizedEmail, productId])
  @@index([submissionId])
  @@index([productId])
  @@index([emailStatus])
  @@index([createdAt])
  @@map("preorder_discount_leads")
}
```

### `submissionId` 是否必须

建议新增，但不是业务闭环的硬依赖。

新增好处：

- 一次提交选择两个产品时，后台可以看出这两条 lead 来自同一次表单提交。
- 后续排查邮件发送和用户反馈更方便。
- 不影响 `normalizedEmail + productId` 去重。

如果希望尽量少改数据库，也可以暂不加 `submissionId`。但文档建议加，因为迁移成本很低。

---

## API 设计

### 提交预约

```http
POST /preorder-discounts/claim
```

请求：

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

兼容策略：

- 新接口以 `productIds` 为准。
- 不建议继续支持旧 `productId`，避免前端误以为商品详情入口仍驱动预约。
- 如果为了短期兼容旧调用，可以在 controller 内把单 `productId` 转成数组，但返回和文档都统一为 `productIds`。

### 成功响应

全部首次领取且记录创建成功：

```json
{
  "success": true,
  "data": {
    "status": "PENDING",
    "message": "Your preorder discount request has been received.",
    "submissionId": "pre_abc123",
    "items": [
      {
        "productId": "product_a_id",
        "productName": "AI Sheep Counting Camera",
        "leadId": "lead_a_id",
        "status": "PENDING",
        "duplicate": false,
        "emailStatus": "PENDING"
      },
      {
        "productId": "product_b_id",
        "productName": "AI Wool Diameter Analyzer",
        "leadId": "lead_b_id",
        "status": "PENDING",
        "duplicate": false,
        "emailStatus": "PENDING"
      }
    ]
  }
}
```

注意：

- 响应中可以不返回 `code`，前端也不应展示优惠码。
- 后台接口可以查看 `code`。
- 邮件发送后的 `emailStatus` 更新由 `BACKEND-019` 衔接。

### 部分重复响应

一个产品已领取，另一个产品首次领取：

```json
{
  "success": true,
  "data": {
    "status": "PARTIAL_DUPLICATE",
    "message": "Some selected products have already been claimed for this email.",
    "submissionId": "pre_abc123",
    "items": [
      {
        "productId": "product_a_id",
        "productName": "AI Sheep Counting Camera",
        "leadId": "existing_lead_id",
        "status": "DUPLICATE",
        "duplicate": true,
        "emailStatus": "SENT"
      },
      {
        "productId": "product_b_id",
        "productName": "AI Wool Diameter Analyzer",
        "leadId": "new_lead_id",
        "status": "PENDING",
        "duplicate": false,
        "emailStatus": "PENDING"
      }
    ]
  }
}
```

### 全部重复响应

所有选择产品都已领取：

```json
{
  "success": false,
  "code": "PREORDER_DISCOUNT_ALREADY_CLAIMED",
  "message": "This email has already claimed discount codes for the selected products.",
  "data": {
    "items": [
      {
        "productId": "product_a_id",
        "status": "DUPLICATE",
        "duplicate": true
      }
    ]
  }
}
```

HTTP 状态建议：

- 全部重复返回 `400` 或 `409` 均可。
- 项目当前单产品版本使用 `400`，为了减少改动可以继续使用 `400`。

### 校验失败

常见错误：

- 缺少必填字段。
- 邮箱格式错误。
- `productIds` 不是数组。
- `productIds` 为空。
- `productIds` 超过 2 个。
- `productIds` 内有重复 ID。
- 任意产品不存在。
- 任意产品不是 `PREORDER`。

示例：

```json
{
  "success": false,
  "message": "Validation failed",
  "errors": [
    "At least one product must be selected"
  ]
}
```

---

## 业务规则

### 产品校验

对 `productIds` 做规范化：

1. 必须是数组。
2. 每个值必须是非空字符串。
3. trim。
4. 去重后长度必须与原长度一致，否则返回重复产品错误。
5. 长度至少 1。
6. 长度最多 2。

查询产品：

```ts
const products = await prisma.product.findMany({
  where: {
    id: { in: productIds },
    isDeleted: false,
    status: 1
  },
  select: {
    id: true,
    name: true,
    price: true,
    purchaseMode: true
  }
})
```

校验：

- 查询结果数量必须等于 `productIds.length`。
- 每个产品 `resolvePurchaseMode(product.purchaseMode, product.price)` 必须是 `PREORDER`。
- 如果产品下架或逻辑删除，不允许领取优惠码。

### 去重

保留：

```prisma
@@unique([normalizedEmail, productId])
```

规则：

- 同一邮箱同一产品只生成一次优惠码。
- 同一邮箱不同产品可以分别生成。
- 同一提交内，如果 A 重复、B 不重复，B 仍应创建并继续后续邮件发送。
- 全部重复时不创建新记录。

### 优惠码生成与有效期

格式：

```text
MXT-<PRODUCT_SHORT>-<RANDOM>
```

要求：

- 随机段至少 6 位大写字母数字。
- 写库前检查唯一性。
- 不用邮箱生成码。
- `expiresAt` 不再按提交年份自动推导，必须从配置读取。
- 本次上线配置为 `2026-12-31 23:59:59.999`。
- 每个产品单独生成一个 code。

推荐配置项：

```env
PREORDER_DISCOUNT_EXPIRES_AT=2026-12-31T23:59:59.999+11:00
```

说明：

- 如果项目统一使用 UTC 保存时间，读取配置后应转换为数据库 `DateTime`。
- 对澳大利亚用户展示时，邮件中应按 `en-AU` 或指定业务时区格式化。
- 配置缺失或格式非法时，服务启动或接口调用应给出明确错误，不能静默回退到当前年份年底。

---

## 实施步骤

1. 如采用 `submissionId`，更新 Prisma 模型并生成迁移。
2. 修改 `ClaimRequestBody`：新增 `productIds?: unknown`，移除或降级 `productId`。
3. 新增 `normalizeProductIds` helper。
4. controller 中批量校验表单字段和 `productIds`。
5. 批量查询产品并校验 `PREORDER`。
6. 在 model 中新增 `claimMany`，或在 controller 中循环调用现有 `claim`。
7. 推荐 `claimMany` 内生成一次 `submissionId`，并传给每个 lead。
8. 每个产品按 `normalizedEmail + productId` 检查重复。
9. 非重复产品创建 lead，重复产品返回 existing lead 摘要。
10. 返回 `items` 级别结果。
11. 全部重复时返回 `PREORDER_DISCOUNT_ALREADY_CLAIMED`。
12. 补充接口测试或脚本验证。

---

## 验收标准

- [ ] 缺少必填字段返回明确错误。
- [ ] 邮箱格式错误返回明确错误。
- [ ] `productIds` 缺失返回明确错误。
- [ ] `productIds` 为空返回明确错误。
- [ ] `productIds` 超过 2 个返回明确错误。
- [ ] `productIds` 有重复 ID 返回明确错误。
- [ ] 任一产品不存在返回明确错误。
- [ ] 任一产品不是 `PREORDER` 返回明确错误。
- [ ] 同邮箱同产品重复提交不会创建新记录。
- [ ] 同邮箱不同产品可以分别提交。
- [ ] 一次提交两个产品会创建两条预约记录。
- [ ] 两条预约记录各自有独立优惠码。
- [ ] 优惠码过期时间来自配置。
- [ ] 本次上线配置后，优惠码过期时间为 2026 年 12 月 31 日。
- [ ] 记录默认 `emailStatus = PENDING`。
- [ ] 如果新增 `submissionId`，同一次提交创建的多条记录具有相同 `submissionId`。
- [ ] 接口响应包含逐产品 `items`。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 现有代码已经实现单产品版本 | 在现有 `claim` 基础上扩展 `claimMany`，不要推倒重写 |
| 全部重复和部分重复语义不清 | 统一用 `items` 返回每个产品状态 |
| 与邮件发送衔接 | 本任务只保证创建 PENDING 记录，BACKEND-019 负责逐条发送 |
| 数据库迁移影响 | `submissionId` 是可空字段，迁移风险低 |
| 前端误用旧 `productId` | 文档和类型统一使用 `productIds` |

---

**相关文档:**

- [开发计划](../../docs/plans/2026-06-17-preorder-discount-code-closed-loop-plan.md)
- [项目状态](../../04-projects/moxton-lotapi.md)
