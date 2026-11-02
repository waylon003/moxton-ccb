# Tech-Spec: 预售优惠码邮件移除产品主图与短码规则调整

**任务ID:** BACKEND-024  
**创建时间:** 2026-06-28  
**状态:** 准备开发  
**角色:** 后端工程师  
**项目:** moxton-lotapi  
**优先级:** P1  
**技术栈:** Node.js + Koa + TypeScript + Prisma + MySQL + Resend  
**QA_LEVEL:** full

---

## 概述

### 问题陈述

当前预售优惠码邮件已经可以正常发送，但实际测试后发现两个体验问题：

- 邮件模板会渲染产品主图，邮件首屏内容过长，移动端查看时优惠码区域被产品图明显下推。
- 当前优惠码格式类似 `MXT-PREORD-AAAAAA`，长度偏长，不适合用户手动输入、展会现场口头沟通和后续结账使用。

本任务需要调整为：

- 邮件中不再展示产品主图。
- 优惠码改为固定 10 位，由大写英文字母和数字组成。

### 解决方案

1. 保留邮件 logo，不移除品牌 logo。
2. 移除邮件模板中的产品主图模块。
3. 发送邮件时不再需要读取或传入 `productImageUrl`。
4. 优惠码生成改为 10 位大写英文和数字随机码。
5. 继续保证优惠码唯一性。
6. 更新相关单元测试和 API 文档说明。

---

## 范围

**包含:**

- 修改后端优惠码生成规则。
- 修改邮件 HTML/text 模板相关输入类型。
- 移除邮件产品主图渲染逻辑。
- 调整发送邮件时的产品查询字段，避免为了邮件图片读取 `images` / `metadata`。
- 更新后端测试。
- 更新 `02-api/preorder-discounts.md` 中优惠码格式和邮件图片说明。

**不包含:**

- 后台配置邮件模板。
- Resend 后台模板配置。
- 官网预约页 UI。
- 管理后台预约名单页面。
- 结账使用优惠码抵扣。

---

## 当前代码定位

### 邮件模板

文件：

- `E:\moxton-lotapi\src\services\EmailService.ts`

当前关键点：

- `SendPreorderDiscountEmailInput` 包含 `productImageUrl?: string | null`。
- `buildPreorderDiscountHtml()` 中存在 `imageModule`。
- `imageModule` 会在 `productImageUrl` 是公网 `https://` 图片时渲染产品 `<img>`。

需要调整：

- 从 `SendPreorderDiscountEmailInput` 移除 `productImageUrl`。
- 删除 `imageModule` 构造逻辑。
- 删除 HTML 中的 `${imageModule}` 插入位置。
- 保留 logo 渲染逻辑，即 `EMAIL_LOGO_URL` 对应图片仍然展示。
- 保留 `productName`，因为邮件仍然需要说明该优惠码对应哪个产品。

### 邮件发送调用

文件：

- `E:\moxton-lotapi\src\models\PreorderDiscountLead.ts`

当前关键点：

- `sendDiscountEmail(leadId)` 查询 lead 时 include `product.images` 和 `product.metadata`。
- 调用 `emailService.sendPreorderDiscountEmail()` 时传入：

```ts
productImageUrl: this.getProductImageUrl(lead.product)
```

需要调整：

- 发送邮件不再传 `productImageUrl`。
- 查询产品时不再需要 `images` / `metadata`，如详情列表还需要另算，不要影响后台列表/详情已有展示。
- 如果 `getProductImageUrl()` 只剩后台列表详情使用，可保留；如果已无使用，可删除。

### 优惠码生成

文件：

- `E:\moxton-lotapi\src\models\PreorderDiscountLead.ts`

当前关键点：

- `buildProductShortCode(productName, productId)` 生成产品短码。
- `generateUniqueCode(productName, productId)` 生成：

```ts
MXT-${productShort}-${this.randomSegment(6)}
```

示例：

```text
MXT-PREORD-AAAAAA
```

需要调整为：

```text
^[A-Z0-9]{10}$
```

示例：

```text
7KQ9M2XA4B
```

---

## 优惠码规则

### 新规则

- 长度固定 10 位。
- 字符集：`A-Z`、`0-9`。
- 统一大写。
- 不带连字符。
- 不带产品短码。
- 不带 `MXT` 前缀。
- 生成后仍写入 `preorder_discount_leads.code`。
- `code` 字段仍保持唯一约束。

### 推荐实现

建议新增常量：

```ts
const PREORDER_DISCOUNT_CODE_LENGTH = 10
const PREORDER_DISCOUNT_CODE_CHARSET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
```

生成函数示意：

```ts
private randomCode(length = PREORDER_DISCOUNT_CODE_LENGTH): string {
  return Array.from({ length }, () => {
    const index = Math.floor(Math.random() * PREORDER_DISCOUNT_CODE_CHARSET.length)
    return PREORDER_DISCOUNT_CODE_CHARSET[index]
  }).join('')
}
```

然后 `generateUniqueCode()` 中最多重试 10 次：

```ts
const code = this.randomCode()
```

继续通过：

```ts
prisma.preorderDiscountLead.findUnique({ where: { code } })
```

判断是否冲突。

### 随机性说明

10 位 `A-Z0-9` 理论空间为：

```text
36^10 = 3,656,158,440,062,976
```

当前预售预约量级下冲突概率极低。保留数据库唯一检查和重试即可。

如果后续要提高安全性，可以改用 `crypto.randomInt()`，但本任务优先保持改动小。

---

## 测试数据处理

当前仍处于测试阶段，不需要兼容旧规则生成的优惠码。

- 可以清理测试阶段已生成的旧预约优惠码记录。
- 如果保留旧测试记录，重发旧记录仍会使用原 lead 的旧 `code`，但这不是本阶段需要保障的正式兼容行为。
- 推荐在联调前清空或删除旧测试预约记录，避免后台列表里同时出现旧格式和新格式优惠码。
- 新提交预约必须全部使用 10 位新格式。
- 代码中旧的产品短码生成逻辑可以直接删除，不需要保留兜底。

---

## 邮件模板规则

### 保留内容

- Moxton logo。
- `Exclusive pre-launch offer`。
- 标题：`Your 15% Discount Code Is Ready`。
- 用户称呼。
- 产品名称。
- 优惠码。
- 折扣比例。
- 有效期。
- `Eligible product` 单产品名称。
- 支持邮箱。

### 移除内容

- 产品主图。
- 与 `productImageUrl` 相关的 HTML 模块。
- 与邮件产品图片相关的测试断言。

### 注意事项

- 不要移除 logo。用户截图中破图问题是 `EMAIL_LOGO_URL` 旧地址 404，已经通过环境变量替换为 OSS 图片地址解决。
- 邮件仍然是一产品一封。
- 单封邮件底部仍然只能展示一个动态产品名。
- 邮件里不要展示两个产品名。
- 邮件里不要展示视频。

---

## API 文档同步

需要更新：

- `E:\moxton-ccb\02-api\preorder-discounts.md`

调整点：

- “邮件模板基于 `E:\邮件模版\moxton-discount-email.html`，产品图片和 logo 必须使用公网可访问的 `https://` URL。”这句需要改为：

```text
邮件模板基于 `E:\邮件模版\moxton-discount-email.html`，但当前发信邮件只展示 logo，不展示产品主图；logo 必须使用公网可访问的 `https://` URL。
```

- 增加优惠码格式说明：

```text
新生成的预约优惠码为固定 10 位大写英文字母和数字组合，格式为 `^[A-Z0-9]{10}$`。
```

- 后台列表/详情中的示例 `code` 从旧格式：

```text
MXT-AISHEE-ABC123
```

改成新格式：

```text
7KQ9M2XA4B
```

---

## 测试要求

需要更新：

- `E:\moxton-lotapi\tests\api\preorder-discount.spec.ts`

建议测试点：

1. `generateUniqueCode()` 返回 10 位大写英文数字：

```ts
expect(code).toMatch(/^[A-Z0-9]{10}$/)
```

2. 不再测试 `buildProductShortCode()`，如果函数被删除，需要同步删除 import 和测试。

3. 邮件 HTML 不包含产品主图 URL：

```ts
expect(html).not.toContain('https://cdn.example.com/sheep.jpg')
```

4. 邮件 HTML 仍包含 logo URL。

5. 邮件 HTML 仍包含：

- 用户称呼。
- 优惠码。
- 产品名称。
- `Eligible product`。

6. `sendDiscountEmail()` 调用 `emailService.sendPreorderDiscountEmail()` 时不再包含 `productImageUrl`。

7. 删除旧短码相关测试，例如 `buildProductShortCode()`。

---

## 实施步骤

1. 修改 `EmailService.ts` 的 `SendPreorderDiscountEmailInput`，移除 `productImageUrl`。
2. 删除 `buildPreorderDiscountHtml()` 中产品主图 `imageModule`。
3. 删除 HTML 中 `${imageModule}`。
4. 确认 logo 模块仍使用 `config.email.logoUrl`。
5. 修改 `PreorderDiscountLead.ts#sendDiscountEmail()`，不再传 `productImageUrl`。
6. 如果邮件发送查询不再需要产品图片，精简 include 的产品字段。
7. 修改优惠码生成逻辑为 10 位 `A-Z0-9`。
8. 删除 `buildProductShortCode()`，以及旧的产品短码测试。
9. 更新单元测试。
10. 更新 `02-api/preorder-discounts.md`。
11. 运行测试。
12. 清理旧测试预约优惠码记录，避免测试后台中混杂旧格式优惠码。
13. 触发一次真实或测试预约邮件，确认邮件不展示产品主图且优惠码为 10 位。

---

## 验收标准

- [ ] 新预约生成的优惠码固定 10 位。
- [ ] 新优惠码只包含大写英文字母和数字。
- [ ] 新优惠码不包含 `MXT` 前缀。
- [ ] 新优惠码不包含产品短码。
- [ ] 新优惠码不包含连字符。
- [ ] 新优惠码仍保证唯一。
- [ ] 旧产品短码生成逻辑已删除。
- [ ] 测试阶段旧预约优惠码记录已清理，或已确认不会影响联调验收。
- [ ] 邮件 HTML 不再展示产品主图。
- [ ] 邮件 HTML 仍展示 Moxton logo。
- [ ] 邮件 HTML 仍展示单个动态产品名称。
- [ ] 邮件 HTML 仍展示优惠码、折扣比例和有效期。
- [ ] 后台重发邮件不会生成新优惠码。
- [ ] `02-api/preorder-discounts.md` 已同步新规则。
- [ ] 后端相关测试通过。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 测试阶段旧码与新码格式不一致 | 联调前清理旧测试预约记录，不做正式兼容 |
| 邮件移除产品图后视觉变空 | 保留产品名称、优惠码卡片和 `Eligible product` 区块 |
| 误删 logo | 产品主图和 logo 是两件事，只移除产品主图 |
| 重发邮件生成新码 | 重发必须使用 lead 原有 `code`，但测试阶段旧记录可清理 |
| 测试仍断言产品图片存在 | 同步调整测试为不包含产品图片 |

---

**相关文档:**

- [预售预约优惠码 API](../../../02-api/preorder-discounts.md)
- [BACKEND-019 预约优惠码邮件发送与后台管理接口](./BACKEND-019-preorder-email-and-admin-api.md)
- [开发计划](../../../docs/plans/2026-06-17-preorder-discount-code-closed-loop-plan.md)
