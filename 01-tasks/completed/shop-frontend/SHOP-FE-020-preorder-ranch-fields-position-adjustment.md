# Tech-Spec: 预约页牧场信息字段位置与测试计划勾选调整

**任务ID:** SHOP-FE-020
**创建时间:** 2026-06-29
**状态:** 已完成
**角色:** 独立站前端工程师
**项目:** nuxt-moxton
**优先级:** P1
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia
**QA_LEVEL:** smoke

---

## 概述

### 问题陈述

当前官网预约页的产品测试计划功能已经完成，但交互口径需要调整：

- 现状：用户必须先勾选参加测试计划，才会看到并填写 4 个牧场信息字段。
- 新口径：4 个牧场信息字段不应该依赖测试计划勾选，用户不参加测试计划也可以填写。

原因：

- 牧场名称、牧场地址、羊群数量、羊只品种本身也是普通预约线索的补充信息。
- 测试计划勾选只是表达“是否申请参加测试计划”，不应该控制牧场信息字段是否出现。
- 用户可以只补充牧场信息但不报名测试计划。

### 解决方案

调整 `/preorder-discount` 表单结构：

1. 必填基础信息之后，始终显示 4 个非必填牧场信息字段。
2. 4 个字段下方再放测试计划 checkbox。
3. checkbox 下方展示测试计划说明文案。
4. 勾选 checkbox 只影响是否创建测试计划申请，不影响 4 个字段显示和填写。
5. 提交时：
   - 4 个牧场字段始终可以随预约提交。
   - `testingProgramOptIn = false` 时，不创建测试计划申请。
   - `testingProgramOptIn = true` 时，使用同一组牧场字段创建或更新测试计划申请。

### 范围

**包含:**

- 调整 `/preorder-discount` 表单 UI 顺序。
- 移除“勾选后才展开牧场信息字段”的交互。
- 4 个牧场字段始终显示、始终可填写、始终非必填。
- 将测试计划 checkbox 和说明移动到 4 个牧场字段下方。
- 调整提交 payload 组装逻辑。
- 调整成功提示逻辑。
- 补齐中英文文案。
- 验证桌面端和移动端布局。

**不包含:**

- 后端数据模型变更。
- 后台产品测试申请页面变更。
- 资格邮件模板变更。
- 导出功能变更。

---

## 开发上下文

前置任务已完成：

- `SHOP-FE-019`：官网预约页产品测试计划报名入口。
- `BACKEND-025`：产品测试计划申请数据模型与后台接口。
- `ADMIN-FE-017`：后台产品测试计划申请列表与资格邮件。

可能涉及文件：

- `pages/preorder-discount.vue`
- `components/preorder/PreorderDiscountForm.vue`
- `composables/api/preorder-discounts.ts`
- `types/shop.ts`
- `i18n/locales/zh.ts`
- `i18n/locales/en.ts`

API 文档：

- `../../../02-api/preorder-discounts.md`
- `../../../02-api/product-testing-applications.md`

---

## 新表单结构

### 字段顺序

推荐顺序：

1. `firstName`，必填。
2. `lastName`，必填。
3. `phone`，必填。
4. `email`，必填。
5. 分隔提示：填写牧场信息有助于我们更准确了解预约需求。
6. `ranchName`，非必填。
7. `ranchAddress` 或 `address`，非必填。
8. `sheepCount`，非必填。
9. `sheepBreed`，非必填；使用下拉选择。
10. `testingProgramOptIn` checkbox。
11. 测试计划说明文案。
12. `Send My Discount Code` 按钮。

### 视觉要求

- 4 个牧场字段属于表单主体，不放在 checkbox 展开区里。
- checkbox 与说明文案要明显属于测试计划报名，不要让用户误以为勾选后才会保存牧场信息。
- 移动端字段上下间距稳定，不要因为说明文案过长导致按钮被挤压或遮挡。

### 羊只品种下拉

`sheepBreed` 使用下拉选择，不使用默认自由文本输入。

第一版固定选项：

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

交互规则：

- 默认不选择，字段非必填。
- 选择常规选项时，提交该选项文本作为 `sheepBreed`。
- 选择 `Other` 时，在下拉下方展示一个自定义输入框。
- `Other` 自定义输入框非必填；如果用户填写，则提交填写内容作为 `sheepBreed`。
- 如果用户选择 `Other` 但未填写自定义内容，建议提交 `sheepBreed: "Other"` 或空值；实现时保持前后端口径一致。
- 切换离开 `Other` 时，应清空或忽略自定义输入值，避免提交旧值。

---

## 交互规则

### 默认状态

页面加载后：

- 4 个牧场字段直接显示。
- checkbox 默认不勾选。
- 测试计划说明可直接显示在 checkbox 下方。
- 用户不填写牧场字段也可以继续预约。

### 勾选测试计划

用户勾选 checkbox 后：

- 不展开额外字段。
- 不改变 4 个牧场字段的位置。
- 可以高亮或保留测试计划说明，但不要新增大段弹出内容。
- 提交时 `testingProgramOptIn = true`。

### 取消勾选

用户取消 checkbox 后：

- 4 个牧场字段仍保留显示。
- 已输入的牧场信息不清空。
- 提交时 `testingProgramOptIn = false`。
- 不创建测试计划申请。

---

## 提交 Payload

### 未勾选测试计划

即使未勾选测试计划，也允许提交牧场信息：

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

说明：

- 后端如当前未在预约优惠码 lead 中保存 `sheepCount`、`sheepBreed`，前端仍可先按接口契约提交；若后端未接收这两个根级字段，应在本任务实现时按实际接口调整。
- `testingProgramOptIn = false` 时，不应发送用于创建测试申请的 `testingProgram`，除非后端明确要求该对象用于保存普通预约扩展信息。

### 勾选测试计划

勾选后，使用同一组牧场字段构造测试申请：

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

---

## 文案建议

牧场信息分隔提示：

```text
Ranch details help us understand your preorder request and product needs.
```

测试计划 checkbox：

```text
Apply for the AI Sheep Counting Camera testing program
```

测试计划说明：

```text
Tick this box to opt into our official product testing program. Selected eligible testers may receive a complimentary AI Sheep Counting Camera and will be contacted by email. Applying does not guarantee selection.
```

如果需要展示职责说明，可放在同一说明段落后半部分或 tooltip 中：

```text
Selected testers will record on-site sheep footage with the provided device and upload collected data for model training and improvement.
```

---

## 校验规则

- `firstName`、`lastName`、`phone`、`email` 继续按预约页既有必填规则校验。
- `ranchName` 非必填，填写后 trim。
- `ranchAddress` / `address` 非必填，填写后 trim。
- `sheepCount` 非必填；填写后必须是正整数。
- `sheepBreed` 非必填，使用下拉选择。
- `sheepBreed = Other` 时允许填写自定义品种，填写后 trim。
- 自定义品种建议最大长度 100。
- checkbox 不参与必填校验。
- 未勾选测试计划时，牧场字段非法仍应阻止提交，因为这些字段仍会作为预约表单数据提交。

---

## 实施步骤

1. 定位当前 `/preorder-discount` 表单中测试计划区块。
2. 移除 checkbox 控制牧场字段显隐的逻辑。
3. 将 `ranchName`、`ranchAddress/address`、`sheepCount`、`sheepBreed` 调整为始终显示。
4. 将 `testingProgramOptIn` checkbox 和说明文案移动到 4 个字段下方。
5. 将 `sheepBreed` 改为下拉选择，并实现 `Other` 自定义输入。
6. 调整表单状态命名，确保牧场字段不是 checkbox 子状态。
7. 调整 payload：
   - 根级始终可提交牧场字段。
   - 只有勾选时才提交 `testingProgram` 或让后端创建测试申请。
8. 调整成功提示：
   - 未勾选时只提示预约提交成功。
   - 勾选时额外提示测试计划申请已收到。
9. 补齐中英文文案。
10. 验证桌面端、移动端布局。
11. 验证未勾选但填写牧场字段、勾选并填写牧场字段、勾选但不填写牧场字段三种场景。

---

## 验收标准

- [ ] 4 个牧场字段默认显示，不依赖 checkbox。
- [ ] checkbox 和测试计划说明位于 4 个牧场字段下方。
- [ ] 未勾选 checkbox 时，用户仍可填写牧场字段。
- [ ] 未勾选 checkbox 时，提交不会创建测试计划申请。
- [ ] 未勾选 checkbox 且填写牧场字段时，预约优惠码流程正常提交。
- [ ] 勾选 checkbox 时，不出现额外展开字段。
- [ ] 勾选 checkbox 时，提交会创建或更新测试计划申请。
- [ ] 取消勾选不会清空已填写的牧场字段。
- [ ] `sheepCount` 非法输入会阻止提交并显示错误。
- [ ] `sheepBreed` 使用下拉选择。
- [ ] `sheepBreed` 下拉包含 `Merino`、`Dorper`、`Dorset`、`Suffolk`、`Texel`、`Romney`、`Border Leicester`、`Australian White`、`Mixed breed`、`Other`。
- [ ] 选择 `Other` 后出现自定义品种输入框。
- [ ] `Other` 自定义输入会作为最终 `sheepBreed` 提交。
- [ ] 产品选择弹窗仍只负责选择产品。
- [ ] 成功提示能区分“仅预约成功”和“预约成功且测试计划申请已收到”。
- [ ] 移动端字段和说明文案不重叠、不溢出。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 用户误以为填写牧场信息等于报名测试计划 | checkbox 文案明确“Apply for testing program”，并放在字段下方 |
| 未勾选时后端丢弃 `sheepCount/sheepBreed` | 实现前确认后端当前是否接收根级扩展字段；如不接收，需要补接口或只在勾选时进入测试申请 |
| 表单状态仍绑定在 `testingProgram` 对象下 | 前端状态应把牧场字段提升为普通表单字段，再按需映射到 `testingProgram` |
| 成功提示误报测试申请 | 只有响应包含 `testingApplication` 或本次勾选成功时才展示测试申请提示 |
| 品种选项无法覆盖所有牧场情况 | 保留 `Other` 自定义输入，最终仍以字符串提交 |

---

**相关文档:**

- [官网测试计划报名任务](./SHOP-FE-019-testing-program-opt-in.md)
- [产品测试计划申请 API](../../../02-api/product-testing-applications.md)
- [预售预约优惠码 API](../../../02-api/preorder-discounts.md)

