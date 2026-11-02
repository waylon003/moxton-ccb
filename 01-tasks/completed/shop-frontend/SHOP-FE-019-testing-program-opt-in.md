# Tech-Spec: 官网预约页产品测试计划报名入口

**任务ID:** SHOP-FE-019
**创建时间:** 2026-06-29
**状态:** 待开发
**角色:** 独立站前端工程师
**项目:** nuxt-moxton
**优先级:** P1
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia
**QA_LEVEL:** full

---

## 概述

### 问题陈述

官网 `/preorder-discount` 预约页当前主要用于领取预售优惠码。业务现在需要在该流程中加入 AI Sheep Counting Camera 官方产品测试计划报名入口。用户可以选择是否报名测试计划，报名后填写额外牧场信息，用于后续管理层筛选测试名额。

当前页面已有必填字段和产品选择弹窗。测试计划报名不应放在产品选择弹窗内，因为它不是产品选择行为，而是用户对测试计划的单独授权和申请。弹窗继续只负责选择预约产品。

### 解决方案

在主表单必填字段下方新增一个非必填测试计划报名区块：

1. 默认只显示 checkbox 和简短说明。
2. 用户勾选后展开详细信息区域。
3. 展开区域包含 4 个非必填字段：
   - 牧场名称
   - 牧场地址
   - 牧场规模 / 羊群数量
   - 羊只品种
4. 详细字段上方显示说明：填写详细信息有助于资格评估，但不保证入选。
5. 点击 `Send My Discount Code` 时仍先校验必填字段，通过后打开产品选择弹窗。
6. 弹窗确认后提交预约优惠码字段和测试计划报名字段。

### 范围

**包含:**

- 修改 `/preorder-discount` 表单布局。
- 将原可选 `ranchName`、`address` 调整为测试计划详情区内字段。
- 新增 `sheepCount` 和 `sheepBreed` 字段。
- 新增 `testingProgramOptIn` checkbox。
- 勾选后展开测试计划详细字段。
- 提交接口新增 `testingProgramOptIn` 和 `testingProgram`。
- 成功页或成功提示中补充测试计划报名已收到的提示。
- 补齐中英文文案。
- 桌面端和移动端适配。

**不包含:**

- 后端数据模型和接口实现，详见 `BACKEND-025`。
- 后台筛选页面，详见 `ADMIN-FE-017`。
- 测试计划资格邮件发送。
- 管理层导出和筛选。

---

## 开发上下文

相关现有任务：

- `SHOP-FE-017` 已定义 `/preorder-discount` 固定预约页。
- `BACKEND-018` 和 `BACKEND-019` 已定义预约优惠码提交流程。
- `BACKEND-025` 将扩展提交接口，支持测试计划申请。

可能涉及文件：

- `pages/preorder-discount.vue`
- `components/preorder/PreorderDiscountForm.vue`
- `components/preorder/PreorderProductSelectModal.vue`
- `composables/api/preorder-discounts.ts`
- `types/shop.ts`
- `i18n/locales/zh.ts`
- `i18n/locales/en.ts`

### API 文档来源

- 预约提交接口以 `../../../02-api/preorder-discounts.md` 为准。
- 测试计划申请字段以 `../../../02-api/product-testing-applications.md` 为准。

---

## 页面交互设计

### 表单结构

必填基础信息：

- `firstName`
- `lastName`
- `phone`
- `email`

测试计划报名区：

- `testingProgramOptIn`
- 勾选后展开：
  - `testingProgram.ranchName`
  - `testingProgram.ranchAddress`
  - `testingProgram.sheepCount`
  - `testingProgram.sheepBreed`

隐藏上下文：

- `source`

产品选择：

- 仍在产品选择弹窗中完成。
- 测试计划区块不改变产品选择弹窗职责。

### 默认状态

页面加载后：

- checkbox 默认不勾选。
- 4 个详细字段默认隐藏。
- 提交按钮仍可用，不要求用户报名测试计划。
- 未报名时，用户仍可以正常领取优惠码。

### 勾选后状态

用户勾选测试计划：

- 展开详细字段。
- 字段均为非必填。
- 字段不应阻塞优惠码预约提交，除非用户输入了明显非法值。
- 显示简短说明，表达填写详细信息有助于资格评估，但不保证入选。

### 取消勾选

用户取消勾选时：

- 详细字段收起。
- 推荐保留用户已输入内容在前端状态中，避免误触造成数据丢失。
- 提交时不发送 `testingProgram`，或发送 `testingProgramOptIn: false`。

---

## 文案建议

### 英文

checkbox 主文案：

```text
Apply for the AI Sheep Counting Camera testing program
```

简短说明：

```text
Tick this box to opt into our official product testing program. Selected eligible testers may receive a complimentary AI Sheep Counting Camera and will be contacted by email.
```

展开区提示：

```text
Providing ranch details helps us verify eligibility and may improve your chance of being selected. Applying does not guarantee selection.
```

职责说明，可放在折叠说明或小号正文：

```text
Selected testers will record on-site sheep footage with the provided device and upload collected data to our designated platform for model training and improvement.
```

### 中文

后台或中文站文案可参考：

```text
申请参加 AI Sheep Counting Camera 官方产品测试计划
```

```text
勾选后即表示申请参加官方产品测试计划。符合条件并被选中的测试者可能获得免费测试设备，我们将通过邮箱联系入选用户。
```

```text
填写牧场详细信息有助于我们评估资格，并可能提高入选机会；报名不代表一定入选。
```

### 文案注意事项

- 不要写成“填写后一定更高概率抽中”。
- 不要承诺一定免费获得设备。
- 不要承诺报名后一定联系。
- 必须保留“不保证入选”的说明。

---

## 表单字段与校验

### `testingProgramOptIn`

- 类型：boolean。
- 默认：false。
- 非必填。

### `ranchName`

- 类型：string。
- 非必填。
- trim。
- 建议最大长度 100。

### `ranchAddress`

- 类型：string。
- 非必填。
- trim。
- 建议最大长度 500。

### `sheepCount`

- 类型：number 或 string 输入后转 number。
- 非必填。
- 允许为空。
- 如果填写，必须是正整数。
- 建议最大值 999999，避免明显异常输入。

### `sheepBreed`

- 类型：string。
- 非必填。
- trim。
- 建议最大长度 100。

---

## API 接入

### 提交预约

接口：

```http
POST /preorder-discounts/claim
```

未勾选测试计划时：

```json
{
  "firstName": "Morgan",
  "lastName": "Carter",
  "phone": "+61 400 000 000",
  "email": "morgan@example.com",
  "productIds": ["product_a_id"],
  "source": "home_preorder",
  "testingProgramOptIn": false
}
```

勾选测试计划时：

```json
{
  "firstName": "Morgan",
  "lastName": "Carter",
  "phone": "+61 400 000 000",
  "email": "morgan@example.com",
  "productIds": ["product_a_id"],
  "source": "home_preorder",
  "testingProgramOptIn": true,
  "testingProgram": {
    "programKey": "ai_sheep_counting_camera",
    "ranchName": "Carter Ranch",
    "ranchAddress": "1200 Valley Road",
    "sheepCount": 1200,
    "sheepBreed": "Merino"
  }
}
```

兼容说明：

- 如果页面原先已有根级 `ranchName`、`address`，本次可以继续向根级提交，供旧预约优惠码后台展示。
- 但测试计划字段应放在 `testingProgram` 内，避免后续继续污染预约优惠码模型。
- 推荐映射：
  - 根级 `ranchName` = `testingProgram.ranchName`
  - 根级 `address` = `testingProgram.ranchAddress`

### 成功处理

如果响应包含：

```json
{
  "testingApplication": {
    "id": "pta_abc123",
    "status": "APPLIED",
    "duplicate": false
  }
}
```

前端成功页可以补充提示：

```text
Your testing program application has also been received. We will contact selected applicants by email.
```

如果 `duplicate = true`：

```text
We already have a testing program application for this email. Your latest details have been received.
```

不要在用户侧展示后台申请 ID。

---

## 产品选择弹窗影响

产品选择弹窗保持原职责：

- 只选择预售产品。
- 不显示测试计划 checkbox。
- 不展示测试计划长文案。
- 不修改测试计划字段。

触发顺序保持：

1. 用户填写基础信息。
2. 用户可选勾选测试计划并填写详情。
3. 点击 `Send My Discount Code`。
4. 前端校验基础信息和已填写的测试计划字段。
5. 打开产品选择弹窗。
6. 用户选择产品并确认。
7. 统一提交预约和测试计划字段。

---

## 实施步骤

1. 阅读当前 `/preorder-discount` 页面和表单组件结构。
2. 调整表单状态类型，新增 `testingProgramOptIn` 和 `testingProgram`。
3. 将原可选 `ranchName`、`address` 移入测试计划展开区。
4. 新增 checkbox 区块和展开交互。
5. 新增 `sheepCount`、`sheepBreed` 输入框。
6. 补充字段校验。
7. 调整提交 payload 组装逻辑。
8. 根据后端响应处理 `testingApplication` 摘要。
9. 补齐中英文文案。
10. 检查桌面端、平板、移动端布局。
11. 验证未勾选、勾选空详情、勾选完整详情、重复报名、提交失败场景。

---

## 验收标准

- [ ] `/preorder-discount` 页面默认只显示基础必填信息和测试计划 checkbox。
- [ ] checkbox 默认不勾选。
- [ ] 未勾选时，4 个测试计划详细字段不显示。
- [ ] 未勾选时，预约优惠码流程仍可正常提交。
- [ ] 勾选后展开牧场名称、牧场地址、羊群数量、羊只品种字段。
- [ ] 4 个测试计划字段均为非必填。
- [ ] 羊群数量填写非法值时有明确提示。
- [ ] 表单必填字段校验失败时不会打开产品选择弹窗。
- [ ] 测试计划字段非法时不会打开产品选择弹窗。
- [ ] 表单校验通过后仍打开产品选择弹窗。
- [ ] 产品选择弹窗不承载测试计划交互。
- [ ] 勾选测试计划后提交请求包含 `testingProgramOptIn: true`。
- [ ] 未勾选测试计划后提交请求不包含测试详情，或包含 `testingProgramOptIn: false`。
- [ ] 成功后提示优惠码邮件已发送或已受理。
- [ ] 勾选测试计划成功后额外提示申请已收到。
- [ ] 移动端字段不溢出、不重叠。
- [ ] 中英文文案完整。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 把测试计划放进产品选择弹窗导致流程混乱 | 测试计划只放主表单，弹窗只选产品 |
| 可选字段太多降低提交率 | 默认隐藏，用户主动勾选后再展开 |
| “提高入选概率”和“随机选择”冲突 | 文案使用“有助于资格评估 / may improve your chance”，并明确不保证入选 |
| 旧根级 `ranchName/address` 与新字段重复 | 提交时可同步映射，但业务语义以 `testingProgram` 为准 |
| 取消勾选误删输入 | 前端保留本地输入，但提交时不发送测试详情 |

---

**相关文档:**

- [后端测试申请任务](../backend/BACKEND-025-product-testing-application.md)
- [后台测试申请任务](../admin-frontend/ADMIN-FE-017-product-testing-applications.md)
- [产品测试计划申请 API](../../../02-api/product-testing-applications.md)
- [预售预约优惠码 API](../../../02-api/preorder-discounts.md)
