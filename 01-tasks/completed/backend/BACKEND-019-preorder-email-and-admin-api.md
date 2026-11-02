# Tech-Spec: 预约优惠码邮件发送与后台管理接口

**任务ID:** BACKEND-019
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

`BACKEND-018` 负责接收预约表单、按所选产品生成预约记录和优惠码。完整闭环还需要：

- 对每条预约记录发送优惠码邮件。
- 更新每条记录的邮件发送状态。
- 给管理后台提供预约名单、详情和重发接口。

当前 `moxton-lotapi` 已经有 Resend 版本雏形：

- `src/services/EmailService.ts`
- `src/models/PreorderDiscountLead.ts#sendDiscountEmail`
- `src/controllers/PreorderDiscount.ts`
- `src/routes/preorder-discounts.ts`

但当前逻辑仍基于单产品 claim，需要和 `BACKEND-018` 的 `productIds` 多产品提交结果对齐。

### 解决方案

邮件发送仍按 lead 粒度处理：

- 选择 1 个产品：创建 1 条 lead，发送 1 封邮件，邮件包含该产品的优惠码。
- 选择 2 个产品：创建 2 条 lead，发送 2 封邮件，每封邮件分别包含对应产品的优惠码。
- 重复领取的产品不生成新 code，默认不自动重发；如需重发，由后台重发接口处理。
- 邮件模板由代码维护，不依赖 Resend 后台模板。
- 邮件中可以展示产品图片，但图片必须是公网可访问的 `https://` URL。

### 范围

**包含:**

- Resend 邮件服务封装。
- `claim` 成功创建 lead 后逐条触发邮件发送。
- 更新 `emailStatus`、`emailSentAt`、`emailError`、`emailRetryCount`。
- 多产品提交时返回每个产品的邮件状态。
- 后台预约列表接口。
- 后台预约详情接口。
- 后台重发邮件接口。

**不包含:**

- 官网预约表单 UI。
- 管理后台页面。
- 结账优惠码抵扣。
- 邮件平台后台模板配置。
- 产品宣传视频展示。

---

## 开发上下文

当前相关文件：

- `src/services/EmailService.ts`
- `src/controllers/PreorderDiscount.ts`
- `src/models/PreorderDiscountLead.ts`
- `src/routes/preorder-discounts.ts`
- `src/config/index.ts`
- `package.json`

邮件模板来源：

- `E:\邮件模版\moxton-discount-email.html`
- `E:\邮件模版\moxton-logo.png`

当前代码状态：

- `package.json` 已包含 `resend`。
- `config.email.resendApiKey/from/support` 已存在。
- `EmailService` 已能发送 HTML + text 邮件。
- `sendDiscountEmail(leadId)` 已能按单条 lead 发送并更新状态。
- 后台接口路由已存在：
  - `GET /preorder-discounts/admin/leads`
  - `GET /preorder-discounts/admin/leads/:id`
  - `POST /preorder-discounts/admin/leads/:id/resend`

### 依赖项

- 前置任务：`BACKEND-018`
- 邮件服务默认使用 Resend。
- 需要准备 Resend API Key、发件域名、发件邮箱和支持邮箱。
- 正式上线前必须完成发件域名 SPF / DKIM 配置。

---

## 邮件服务

### 服务选择

本任务默认使用 Resend。原因：

- 当前预约优惠码是轻量事务邮件。
- 维护人员少，模板放代码中更直接。
- Resend 免费额度和 Node.js SDK 适合当前阶段。
- 后续如需切换 Postmark / SendGrid，只替换底层 `EmailService`，不改业务 controller。

### 环境变量

```env
RESEND_API_KEY=
EMAIL_FROM="Moxton <no-reply@moxton.ai>"
EMAIL_SUPPORT=support@moxton.ai
```

注意：

- `EMAIL_FROM` 必须使用已在 Resend 验证过的发件域名。
- 账号邮箱可以是 Gmail、163 或个人邮箱，但发件地址不能随意写未验证域名。
- 发件域名验证通过后，通常可以使用该域名下的发件地址，例如 `no-reply@moxton.ai`。

### 邮件发送接口

```ts
sendPreorderDiscountEmail({
  to,
  firstName,
  productName,
  productImageUrl,
  code,
  discountPercent,
  expiresAt
})
```

### 模板维护策略

- 邮件 HTML 模板以 `E:\邮件模版\moxton-discount-email.html` 为视觉基准迁移到代码中维护。
- `moxton-logo.png` 不能在邮件中使用本地相对路径，必须替换为公网可访问的 `https://` logo URL，或使用可公开访问的静态资源地址。
- 模板变量包括：
  - `firstName`
  - `productName`
  - `productImageUrl`
  - `code`
  - `discountPercent`
  - `expiresAt`
  - `supportEmail`
- 模板中的示例 `Hi there,` 必须替换为真实称呼，例如 `Hi ${firstName},`。
- 模板中的示例 `MOXTON15` 必须替换为真实 `code`。
- 模板中的示例有效期 `December 31, 2026` 必须由 `expiresAt` 格式化得到。
- 邮件正文重点保证优惠码、产品名称、折扣比例、有效期清晰。
- 不在邮件里放复杂活动配置。
- 不在邮件里放视频。
- `productImageUrl` 有值时渲染 `<img>`，无值时跳过图片模块。
- 图片必须是公网可访问 `https://` URL。
- 本地路径、相对路径、需要登录鉴权的图片不应放入邮件。

### 产品图片来源

当前用户口径是预约页产品展示区使用商品列表主图。因此邮件图片也建议优先使用商品主图：

```text
1. product.images[0]
2. product.metadata.preorder.heroImage
3. 不展示图片
```

说明：

- 如果当前代码已经优先使用 `metadata.preorder.heroImage`，可以保留，但必须确保 `product.images[0]` 也可作为可靠兜底。
- 图片 URL 必须通过 `isPublicHttpsUrl` 校验。

### 邮件内容必须包含

- 预约产品名称。
- 产品图片，如果有可用公网图片 URL。
- 优惠代码。
- 折扣比例。
- 过期时间。
- 支持联系说明。

### 产品名称渲染规则

邮件是“一产品一封”。即使用户一次选择两个产品，也会发送两封邮件：

- A 产品邮件只显示 A 产品名称和 A 产品优惠码。
- B 产品邮件只显示 B 产品名称和 B 产品优惠码。

模板底部当前示例区是：

```text
Eligible products
- AI Sheep Counting Camera
- AI Wool Diameter Analyzer
```

实际开发时必须改成单产品动态渲染：

```text
Eligible product
- ${productName}
```

不能在单封邮件里同时写两个产品名称，避免用户误以为一个优惠码可同时用于两款产品。

---

## 多产品提交后的邮件衔接

`BACKEND-018` 返回逐产品 `items` 后，本任务需要对非重复、新创建的 lead 逐条发送邮件。

推荐流程：

1. controller 校验并创建 lead。
2. 得到 `items`。
3. 对 `duplicate === false` 的 item 调用 `sendDiscountEmail(leadId)`。
4. 每条发送独立 try/catch。
5. 单条发送失败只影响该条 lead 的 `emailStatus`，不能阻断其他产品邮件。
6. 汇总所有 item 的最终 `emailStatus` 返回给前端。

示例状态：

```ts
type PreorderClaimItemStatus =
  | 'PENDING'
  | 'SENT'
  | 'FAILED'
  | 'DUPLICATE'
```

响应聚合状态建议：

- `SENT`：所有新建 lead 邮件发送成功。
- `PARTIAL_SENT`：部分成功、部分失败。
- `FAILED`：所有新建 lead 邮件发送失败。
- `PARTIAL_DUPLICATE`：有重复，也有新建 lead。
- `DUPLICATE`：全部重复。

前端不展示优惠码，只展示“请检查邮箱”或失败提示。

---

## 后台接口

### 预约名单

```http
GET /preorder-discounts/admin/leads
```

查询参数：

- `pageNum`
- `pageSize`
- `keyword`
- `productId`
- `emailStatus`
- `source`
- `submissionId`，如果 `BACKEND-018` 增加了该字段，可选支持

列表字段建议：

- `id`
- `submissionId`
- `firstName`
- `lastName`
- `email`
- `phone`
- `ranchName`
- `address`
- `source`
- `productId`
- `productName`
- `code`
- `discountPercent`
- `expiresAt`
- `codeStatus`
- `emailStatus`
- `emailSentAt`
- `emailRetryCount`
- `createdAt`
- `product`

### 预约详情

```http
GET /preorder-discounts/admin/leads/:id
```

详情返回：

- 完整表单信息。
- 产品信息。
- 优惠码。
- 折扣比例。
- 过期时间。
- 邮件状态。
- 发送时间。
- 失败原因。
- 重试次数。

### 重发邮件

```http
POST /preorder-discounts/admin/leads/:id/resend
```

规则：

- 重发必须使用原 lead 的原 code。
- 不生成新优惠码。
- 重发成功更新 `emailStatus = SENT`、`emailSentAt = now`、`emailError = null`。
- 重发失败更新 `emailStatus = FAILED`、`emailError`、`emailRetryCount += 1`。

认证：

- 使用现有 `auth` + `adminRole` 或项目内等价后台权限中间件。
- 当前后台权限未细分时，保持和产品管理接口一致。

---

## 实施步骤

1. 确认 Resend 配置读取正常。
2. 按 `E:\邮件模版\moxton-discount-email.html` 迁移 `EmailService` HTML/text 模板。
3. 确保模板变量统一转义，避免 HTML 注入。
4. 确保产品图片 URL 使用公网 `https://` 校验。
5. 修改 claim 邮件衔接逻辑：对 `productIds` 创建出的多条 lead 逐条发送。
6. 汇总逐产品 `emailStatus` 返回前端。
7. 保留单条 `sendDiscountEmail(leadId)`，供后台重发复用。
8. 完善后台列表接口字段，必要时支持 `submissionId` 筛选。
9. 完善后台详情接口字段。
10. 完善后台重发接口。
11. 补充 API 测试或脚本验证：
    - 单产品发送。
    - 两产品发送两封邮件。
    - 一封成功一封失败。
    - 重发成功。
    - 重发失败。

---

## 验收标准

- [ ] 预约提交 1 个产品时发送 1 封邮件。
- [ ] 预约提交 2 个产品时发送 2 封邮件。
- [ ] 每封邮件只包含对应产品的优惠码。
- [ ] 每封邮件底部只显示对应的一个产品名称。
- [ ] 邮件模板视觉基于 `E:\邮件模版\moxton-discount-email.html`。
- [ ] 邮件 logo 使用公网可访问 URL，不使用本地相对路径。
- [ ] 邮件有效期文字由 `expiresAt` 动态格式化，不写死。
- [ ] 邮件成功时对应记录更新为 `SENT`。
- [ ] 邮件失败时对应记录更新为 `FAILED` 且保存错误摘要。
- [ ] 单个产品邮件失败不影响另一个产品发送。
- [ ] 重复领取的产品不会生成新 code。
- [ ] 邮件 HTML 中可展示产品图片。
- [ ] 图片 URL 非公网 `https://` 时不渲染图片模块。
- [ ] 邮件模板不包含视频模块。
- [ ] 后台列表支持分页。
- [ ] 后台列表支持 keyword / productId / emailStatus / source 查询。
- [ ] 后台详情返回完整表单信息、产品、优惠码、邮件状态。
- [ ] 后台重发成功后状态变为 `SENT`。
- [ ] 后台重发失败时更新失败原因和重试次数。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| Resend 域名未验证 | 开发环境可先用已验证域名，正式上线必须完成 SPF / DKIM |
| 邮件错误信息过长 | 保存摘要，不保存敏感凭据 |
| 多产品发送部分失败 | 单条 lead 独立发送和更新，响应中返回逐产品状态 |
| 重复发送 | 重发接口只重发同一 code，不生成新 code |
| 图片无法显示 | 只使用公网 https 图片；邮件客户端仍可能拦截远程图片，这是正常行为 |

---

**相关文档:**

- [开发计划](../../docs/plans/2026-06-17-preorder-discount-code-closed-loop-plan.md)
- [项目状态](../../04-projects/moxton-lotapi.md)
