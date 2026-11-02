# Tech-Spec: 预约优惠码线索补充牧场扩展字段

**任务ID:** BACKEND-026
**创建时间:** 2026-06-29
**状态:** 已完成
**角色:** 后端工程师
**项目:** moxton-lotapi
**优先级:** P1
**技术栈:** Node.js + Koa + TypeScript + Prisma + MySQL
**QA_LEVEL:** full

---

## 概述

### 问题陈述

官网预约页现在允许用户填写 4 个非必填牧场信息字段：

- `ranchName`：牧场名称
- `address` / `ranchAddress`：牧场地址
- `sheepCount`：牧场规模 / 羊群数量
- `sheepBreed`：羊只品种

这些字段不再依赖“参加产品测试计划”勾选。用户即使不报名测试计划，也可以填写这 4 个字段。因此后台“预约优惠码”列表和详情必须能看到这些字段。

当前后端检查结果：

- `prisma/schema.prisma` 的 `PreorderDiscountLead` 只有 `ranchName`、`address`。
- `POST /preorder-discounts/claim` 当前只读取并保存 `body.ranchName`、`body.address`。
- `GET /preorder-discounts/admin/leads` 当前返回 lead 原始记录，所以只包含 `ranchName`、`address`。
- `GET /preorder-discounts/admin/leads/:id` 同样只包含 `ranchName`、`address`。
- 后台 keyword 当前覆盖 `ranchName`，未覆盖 `address`、`sheepBreed`。

缺口是：预约优惠码 lead 没有保存和返回 `sheepCount`、`sheepBreed`，后台预约优惠码页面无法展示完整 4 个字段。

### 解决方案

扩展 `PreorderDiscountLead` 数据模型和预约提交接口：

1. 在 `PreorderDiscountLead` 增加 `sheepCount`、`sheepBreed` 字段。
2. `POST /preorder-discounts/claim` 接收根级 `sheepCount`、`sheepBreed`。
3. 创建预约优惠码 lead 时保存这两个字段。
4. 一次提交多个产品时，每条 lead 都保存同一组牧场字段。
5. 后台列表和详情接口返回完整 4 个牧场字段。
6. 后台 keyword 搜索覆盖牧场名称、牧场地址、羊只品种。
7. 同步更新 `02-api/preorder-discounts.md`。

### 范围

**包含:**

- Prisma 模型新增字段和迁移。
- 预约提交请求体新增根级 `sheepCount`、`sheepBreed`。
- 字段规范化和校验。
- `claimMany` / `claim` 保存扩展字段。
- 后台列表接口返回 `sheepCount`、`sheepBreed`。
- 后台详情接口返回 `sheepCount`、`sheepBreed`。
- 后台 keyword 搜索覆盖 `address`、`sheepBreed`。
- API 文档更新。

**不包含:**

- 官网表单位置调整，详见 `SHOP-FE-020`。
- 后台预约优惠码页面展示调整，详见 `ADMIN-FE-018`。
- 产品测试申请后台页面调整。
- 产品测试资格邮件逻辑。

---

## 开发上下文

相关文件：

- `prisma/schema.prisma`
- `src/controllers/PreorderDiscount.ts`
- `src/models/PreorderDiscountLead.ts`
- `src/routes/preorder-discounts.ts`
- `02-api/preorder-discounts.md`

当前构建产物显示：

- `deploy/moxton-webapi/prisma/schema.prisma` 中 `PreorderDiscountLead` 只有：
  - `ranchName String?`
  - `address String? @db.Text`
- `deploy/moxton-webapi/dist/controllers/PreorderDiscount.js` 的 claim 只传：
  - `ranchName: normalizeOptionalString(body.ranchName)`
  - `address: normalizeOptionalString(body.address)`
- `deploy/moxton-webapi/dist/models/PreorderDiscountLead.js` 创建 lead 时只保存：
  - `ranchName`
  - `address`

### 依赖项

- 前置任务：`BACKEND-018`
- 前置任务：`BACKEND-019`
- 关联前端任务：`SHOP-FE-020`
- 关联后台任务：`ADMIN-FE-018`

---

## 数据模型

### Prisma 模型调整

在 `PreorderDiscountLead` 增加：

```prisma
model PreorderDiscountLead {
  // existing fields...
  ranchName       String?
  address         String?  @db.Text
  sheepCount      Int?
  sheepBreed      String?
  // existing fields...

  @@index([createdAt])
  @@map("preorder_discount_leads")
}
```

字段说明：

| 字段 | 类型 | 说明 |
|------|------|------|
| `sheepCount` | `Int?` | 羊群数量，正整数，可为空 |
| `sheepBreed` | `String?` | 羊只品种，可为空 |

迁移要求：

- 新增字段必须可空，避免影响历史预约记录。
- 历史记录这两个字段返回 `null`。

---

## 用户侧 API 调整

### 提交预约

```http
POST /preorder-discounts/claim
```

请求体新增根级字段：

```json
{
  "firstName": "Morgan",
  "lastName": "Carter",
  "phone": "+61 400 000 000",
  "email": "morgan@example.com",
  "ranchName": "Carter Ranch",
  "address": "1200 Valley Road",
  "sheepCount": 1200,
  "sheepBreed": "Merino",
  "productIds": ["product_a_id"],
  "source": "home_preorder",
  "testingProgramOptIn": false
}
```

规则：

- `sheepCount` 非必填。
- `sheepBreed` 非必填。
- `testingProgramOptIn = false` 时仍保存根级 `sheepCount`、`sheepBreed` 到预约优惠码 lead。
- `testingProgramOptIn = true` 时，预约优惠码 lead 保存根级字段；测试申请可继续使用 `testingProgram` 内字段，或由 controller 映射同一组字段。

### 字段规范化

`sheepCount`：

- 允许为空、`null`、空字符串。
- 如果填写，必须能转换为正整数。
- 建议最大值 `999999`，避免明显异常输入。
- 非法时返回 validation error。

`sheepBreed`：

- trim。
- 空字符串转为 `null`。
- 建议最大长度 100。
- 前端第一版会使用固定下拉选项加 `Other` 自定义输入。
- 后端不强制枚举校验，按最终字符串保存，避免 `Other` 自定义品种被拒绝。
- 后端只做类型、trim、长度校验。

前端建议选项：

- `Merino`
- `Dorper`
- `Dorset`
- `Suffolk`
- `Texel`
- `Romney`
- `Border Leicester`
- `Australian White`
- `Mixed breed`
- `Other`

---

## 后台 API 调整

### 预约列表

```http
GET /preorder-discounts/admin/leads
```

列表项新增：

```json
{
  "ranchName": "Carter Ranch",
  "address": "1200 Valley Road",
  "sheepCount": 1200,
  "sheepBreed": "Merino"
}
```

### 预约详情

```http
GET /preorder-discounts/admin/leads/:id
```

详情新增：

```json
{
  "ranchName": "Carter Ranch",
  "address": "1200 Valley Road",
  "sheepCount": 1200,
  "sheepBreed": "Merino"
}
```

### keyword 搜索

当前 keyword 搜索需要补充：

- `address`
- `sheepBreed`

保留已有搜索：

- `firstName`
- `lastName`
- `email`
- `phone`
- `ranchName`
- `productName`
- `code`

说明：

- `sheepCount` 是数字字段，不强制纳入 keyword 模糊搜索。
- 如果需要按羊群数量筛选，后续单独增加范围筛选，不在本任务内。

---

## 与产品测试申请的关系

预约优惠码 lead 和产品测试申请是两个业务对象：

- `PreorderDiscountLead`：记录预约优惠码线索和优惠码邮件。
- `ProductTestingApplication`：记录测试计划报名、筛选状态和资格邮件。

本任务要求：

- 不管是否勾选测试计划，预约优惠码 lead 都保存 4 个牧场字段。
- 只有勾选测试计划时，才创建或更新 `ProductTestingApplication`。
- 如果勾选测试计划，测试申请中的牧场字段应与预约 lead 中的牧场字段保持一致。

---

## 实施步骤

1. 修改 `prisma/schema.prisma`，在 `PreorderDiscountLead` 新增 `sheepCount`、`sheepBreed`。
2. 生成数据库迁移。
3. 修改 claim 请求体类型，新增 `sheepCount?: unknown`、`sheepBreed?: unknown`。
4. 新增或复用 helper 规范化 `sheepCount`、`sheepBreed`。
5. 修改 controller，将规范化后的字段传入 model。
6. 修改 `ClaimPreorderDiscountInput` / `claimMany` / `claim`，保存新增字段。
7. 确认 `getLeadsForAdmin` 和 `getLeadDetailForAdmin` 返回新增字段。
8. 修改 keyword 搜索，加入 `address`、`sheepBreed`。
9. 更新 `02-api/preorder-discounts.md` 请求体、字段说明、后台列表和详情响应示例。
10. 增加 API 测试或脚本验证。

---

## 验收标准

- [ ] `PreorderDiscountLead` 表包含 `sheepCount`、`sheepBreed` 可空字段。
- [ ] 未勾选测试计划时，提交 `sheepCount`、`sheepBreed` 会保存到预约优惠码 lead。
- [ ] 勾选测试计划时，预约优惠码 lead 同样保存 `sheepCount`、`sheepBreed`。
- [ ] 一次提交多个产品时，每条 lead 都保存同一组牧场字段。
- [ ] `GET /preorder-discounts/admin/leads` 返回 `sheepCount`、`sheepBreed`。
- [ ] `GET /preorder-discounts/admin/leads/:id` 返回 `sheepCount`、`sheepBreed`。
- [ ] 历史记录没有这两个字段时返回 `null`，接口不报错。
- [ ] `sheepCount` 非法值返回明确校验错误。
- [ ] `sheepBreed` 空字符串保存为 `null`。
- [ ] `sheepBreed` 接收下拉选项文本。
- [ ] `sheepBreed` 接收 `Other` 自定义输入文本。
- [ ] 后端不因非枚举品种文本拒绝提交。
- [ ] keyword 可按牧场地址搜索。
- [ ] keyword 可按羊只品种搜索。
- [ ] API 文档已同步。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 只把字段保存到测试申请，未保存到预约 lead | 本任务明确要求预约 lead 也保存，因为未报名用户也可能填写 |
| 多产品提交字段不一致 | `claimMany` 中同一次提交的所有产品复用同一组牧场字段 |
| 历史记录兼容问题 | 新字段可空，返回 `null` |
| `sheepCount` 字符串输入 | controller 统一规范化为整数或 `null` |
| `sheepBreed` 做严格枚举导致 Other 无法提交 | 后端不做枚举限制，只做字符串规范化 |
| keyword 搜索数字字段复杂 | 本任务不做 `sheepCount` keyword 搜索，只补地址和品种 |

---

**相关文档:**

- [预售预约优惠码 API](../../../02-api/preorder-discounts.md)
- [预约页牧场信息字段位置调整](../shop-frontend/SHOP-FE-020-preorder-ranch-fields-position-adjustment.md)
- [预约优惠码后台展示牧场扩展字段](../admin-frontend/ADMIN-FE-018-preorder-lead-ranch-fields-display.md)

