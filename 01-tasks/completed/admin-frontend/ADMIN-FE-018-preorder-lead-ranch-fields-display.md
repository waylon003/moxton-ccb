# Tech-Spec: 预约优惠码后台展示牧场扩展字段

**任务ID:** ADMIN-FE-018
**创建时间:** 2026-06-29
**状态:** 已完成
**角色:** CRUD前端工程师
**项目:** moxton-lotadmin
**优先级:** P1
**技术栈:** Vue 3 + TypeScript + SoybeanAdmin + Naive UI
**QA_LEVEL:** smoke

---

## 概述

### 问题陈述

官网预约页现在允许用户填写 4 个非必填牧场信息字段：

- 牧场名称
- 牧场地址
- 牧场规模 / 羊群数量
- 羊只品种

这些字段不再依赖“参加产品测试计划”勾选。也就是说，不管用户是否报名产品测试计划，只要在预约页填写了这 4 个字段，运营都应该能在“预约优惠码”后台管理页面看到。

当前后台“预约优惠码”页面主要展示预约用户、预约产品、优惠码和邮件状态。需要补充展示 4 个牧场扩展字段，避免运营只能在“产品测试申请”页面看到部分用户资料。

### 解决方案

调整后台“预约优惠码”列表和详情：

1. 列表页展示关键牧场字段，至少展示牧场名称、羊群数量、羊只品种。
2. 详情页展示完整 4 个字段。
3. keyword 搜索应覆盖牧场名称、牧场地址、羊只品种。
4. 如果后端预约优惠码接口当前未返回 `sheepCount`、`sheepBreed`，需要先补充接口字段后再接入前端展示。

### 范围

**包含:**

- 更新预约优惠码 API 类型。
- 更新预约优惠码列表字段。
- 更新预约优惠码详情弹窗或抽屉字段。
- 牧场地址在列表中可截断展示，详情中完整展示。
- 支持空值展示。
- 补齐中英文文案。

**不包含:**

- 产品测试申请后台页面调整。
- 测试计划筛选和资格邮件发送。
- 官网表单字段位置调整，详见 `SHOP-FE-020`。
- 预约优惠码导出功能。

---

## 开发上下文

前置相关任务：

- `ADMIN-FE-011`：后台预约优惠码名单与详情页。
- `SHOP-FE-020`：预约页牧场信息字段位置与测试计划勾选调整。
- `BACKEND-025`：产品测试计划申请数据模型与后台接口。

可能涉及文件：

- `src/service/api/preorder-discount.ts`
- `src/views/preorder-discount/index.vue`
- `src/views/preorder-discount/modules/preorder-discount-detail.vue`
- `src/locales/langs/zh-cn.ts`
- `src/locales/langs/en-us.ts`

API 文档来源：

- `../../../02-api/preorder-discounts.md`

---

## 字段口径

预约优惠码后台应展示以下字段：

| 字段 | 展示文案 | 说明 |
|------|----------|------|
| `ranchName` | Ranch name / 牧场名称 | 非必填 |
| `address` 或 `ranchAddress` | Ranch address / 牧场地址 | 非必填；以预约优惠码接口实际字段为准 |
| `sheepCount` | Sheep count / 羊群数量 | 非必填；数字 |
| `sheepBreed` | Sheep breed / 羊只品种 | 非必填；前台下拉或 Other 自定义后的最终文本 |

说明：

- 这 4 个字段是预约线索信息，不等同于产品测试计划申请。
- 即使 `testingProgramOptIn = false`，只要用户填写了字段，后台也应展示。
- 如果同一次提交选择多个预约产品，后端当前是一产品一条 lead，则每条 lead 都应能看到同一组牧场字段。
- `sheepBreed` 在后台按普通文本展示，不需要还原下拉选项。
- 如果用户选择 `Other` 并填写自定义品种，后台展示自定义文本。

---

## 后端字段依赖

后台前端接入前，需要确认 `GET /preorder-discounts/admin/leads` 和 `GET /preorder-discounts/admin/leads/:id` 是否返回完整 4 个字段。

当前已知历史字段：

- `ranchName`
- `address`

需要确认或补充字段：

- `sheepCount`
- `sheepBreed`

如果接口缺少 `sheepCount`、`sheepBreed`：

1. 后端应在预约提交时保存这两个字段到预约优惠码 lead 或等价扩展字段中。
2. 后台列表接口返回这两个字段。
3. 后台详情接口返回这两个字段。
4. API 文档 `02-api/preorder-discounts.md` 同步字段说明。

---

## 页面展示

### 列表页

建议列表字段：

- 姓名
- 邮箱
- 电话
- 牧场名称
- 羊群数量
- 羊只品种
- 预约产品
- 来源
- 邮件状态
- 提交时间
- 操作

列表中牧场地址可不默认展示，避免表格过宽；可以在详情里展示。如果当前表格支持列配置，也可以把牧场地址作为可选列。

### 详情页

详情页新增“牧场信息”分组：

- 牧场名称
- 牧场地址
- 羊群数量
- 羊只品种

羊只品种展示规则：

- 直接展示接口返回的 `sheepBreed` 字符串。
- 常规下拉选项和 `Other` 自定义输入在后台不做视觉区分。
- 空值显示 `-`。

空值展示：

- 推荐统一显示 `-`。
- 不要显示 `null`、`undefined` 或空白区域。

### 搜索

keyword 搜索建议覆盖：

- 姓名
- 邮箱
- 电话
- 牧场名称
- 牧场地址
- 羊只品种
- 产品名称
- 优惠码

如果后端当前 keyword 未覆盖牧场地址或羊只品种，应由后端补齐搜索范围。

---

## API 类型建议

```ts
interface PreorderDiscountLead {
  id: string
  submissionId?: string | null
  firstName: string
  lastName: string
  email: string
  phone: string
  ranchName?: string | null
  address?: string | null
  ranchAddress?: string | null
  sheepCount?: number | null
  sheepBreed?: string | null
  source?: string | null
  productId: string
  productName: string
  code: string
  emailStatus: 'PENDING' | 'SENT' | 'FAILED'
  createdAt: string
}
```

实现时以真实 API 返回字段为准。如果后端统一使用 `address`，前端不要强行改名为 `ranchAddress`；如果后端新增 `ranchAddress`，详情展示优先使用 `ranchAddress`，兼容回退 `address`。

---

## 实施步骤

1. 检查预约优惠码后台列表和详情接口返回字段。
2. 如果接口缺 `sheepCount`、`sheepBreed`，先补后端和 API 文档。
3. 更新 `preorder-discount` API 类型。
4. 列表页增加牧场名称、羊群数量、羊只品种列。
5. 详情页新增“牧场信息”分组并展示 4 个字段。
6. 确认 keyword 搜索是否覆盖牧场字段。
7. 补齐中英文文案。
8. 验证空值、长地址、超长品种名、移动/窄屏表格展示。

---

## 验收标准

- [ ] 预约优惠码列表能看到牧场名称。
- [ ] 预约优惠码列表能看到羊群数量。
- [ ] 预约优惠码列表能看到羊只品种。
- [ ] 预约优惠码详情能看到牧场名称、牧场地址、羊群数量、羊只品种。
- [ ] 用户选择常规羊只品种时，后台展示对应品种文本。
- [ ] 用户选择 `Other` 并填写自定义品种时，后台展示自定义文本。
- [ ] 未报名测试计划但填写了 4 个字段的预约记录，后台预约优惠码页面能展示这些字段。
- [ ] 报名测试计划并填写了 4 个字段的预约记录，后台预约优惠码页面也能展示这些字段。
- [ ] 字段为空时显示 `-`，不显示 `null` 或 `undefined`.
- [ ] keyword 能按牧场名称搜索。
- [ ] 如果后端支持，keyword 能按牧场地址和羊只品种搜索。
- [ ] 列表在常见桌面宽度下不明显溢出。
- [ ] 详情页字段分组清晰，不和测试计划申请入口混淆。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 误把牧场字段只放到产品测试申请页 | 预约优惠码页面也必须展示，因为未报名用户也可能填写 |
| 后端 lead 未保存 `sheepCount/sheepBreed` | 前端接入前先确认接口；缺字段则补后端保存和返回 |
| 列表列过多 | 列表只放 3 个关键字段，完整地址放详情 |
| `address` / `ranchAddress` 命名不一致 | 前端兼容回退，API 文档明确最终字段 |
| 用户误解为已报名测试计划 | 预约优惠码详情中牧场信息和测试计划申请入口分组展示 |

---

**相关文档:**

- [后台预约优惠码名单与详情页](./ADMIN-FE-011-preorder-discount-leads-page.md)
- [预约页牧场信息字段位置调整](../shop-frontend/SHOP-FE-020-preorder-ranch-fields-position-adjustment.md)
- [预售预约优惠码 API](../../../02-api/preorder-discounts.md)
- [产品测试计划申请 API](../../../02-api/product-testing-applications.md)

