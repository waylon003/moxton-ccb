# Tech-Spec: 后台产品测试申请展示结构化地址字段

**任务ID:** ADMIN-FE-021
**创建时间:** 2026-07-13
**状态:** 待开发
**角色:** CRUD前端工程师
**项目:** moxton-lotadmin
**优先级:** P1
**技术栈:** Vue 3 + TypeScript + SoybeanAdmin + Naive UI
**QA_LEVEL:** smoke

---

## 概述

### 问题陈述

后端 `ProductTestingApplication` 已新增 Google 地址解析后的结构化字段，并在预约提交创建或更新测试申请时同步这些字段。后台产品测试申请页如果不展示这些字段，运营仍只能看到一段牧场地址文本，无法快速判断申请人的国家、州/地区、城市/区镇和邮编，也不利于导出后筛选测试名额。

### 解决方案

调整后台“产品测试申请”列表、详情和导出展示：

1. 更新产品测试申请 API 类型，接收 `country`、`stateRegion`、`locality`、`postcode`、`formattedAddress`、`placeId`。
2. 列表页新增一个合并展示的地区列，避免表格过宽。
3. 详情页在牧场信息中展示完整结构化地址字段。
4. 导出字段确认包含国家、州/地区、城市/区镇、邮编、Google 标准化地址和 Place ID。
5. 搜索占位文案补充国家、州/地区、城市/区镇、邮编、格式化地址。
6. 空值统一显示 `-`。

---

## 范围

**包含:**

- 更新产品测试申请 API 类型。
- 列表页展示结构化地址摘要。
- 详情页展示完整结构化地址字段。
- CSV/Excel 导出列映射同步结构化地址字段。
- keyword 搜索提示文案覆盖新增可搜索字段。
- 补齐中英文文案。
- 验证空值和长地址展示。

**不包含:**

- 后端字段保存、迁移和搜索逻辑，后端已完成。
- 官网预约页 Google 地址搜索。
- 地图预览或 Google Place ID 跳转。
- 新增国家/地区筛选器。
- 批量修改地址字段。

---

## 开发上下文

可能涉及文件：

- `src/service/api/product-testing-application.ts`
- `src/views/product-testing-application/index.vue`
- `src/views/product-testing-application/modules/product-testing-application-detail.vue`
- `src/locales/langs/zh-cn.ts`
- `src/locales/langs/en-us.ts`

相关任务：

- `ADMIN-FE-017`：后台产品测试计划申请列表与资格邮件。
- `ADMIN-FE-020`：后台预约线索展示牧场地址结构化字段。
- 后端新增迁移：`prisma/migrations/20260713000000_add_product_testing_application_address_fields/migration.sql`。

---

## 字段口径

| 字段 | 英文文案 | 中文文案 | 展示位置 |
|------|----------|----------|----------|
| `country` | Country | 国家 | 列表、详情、导出 |
| `stateRegion` | State / Region | 州 / 地区 | 列表、详情、导出 |
| `locality` | City / Suburb / Town | 城市 / 区镇 | 列表、详情、导出 |
| `postcode` | Postcode | 邮编 | 列表、详情、导出 |
| `formattedAddress` | Google formatted address | Google 标准化地址 | 详情、导出 |
| `placeId` | Google Place ID | Google Place ID | 详情、导出 |

说明：

- `formattedAddress` 是 Google 返回的标准化地址，可能为空。
- `placeId` 仅作为普通文本展示，不要求可点击。
- 这些字段均为非必填，后台不能显示 `null` 或 `undefined`。

---

## 页面展示

### 列表页

建议新增一列：

- 中文列名：`地区`
- 英文列名：`Location`

展示格式：

```text
locality, stateRegion, postcode, country
```

示例：

```text
Warburton, Victoria, 3799, Australia
```

展示规则：

- 空值过滤后再拼接。
- 全部为空时显示 `-`。
- 单行省略，完整字段放详情页。
- 不建议在列表拆成 6 列，避免表格过宽。

### 详情页

在“牧场信息”或“地址信息”分组展示：

- 国家
- 州 / 地区
- 城市 / 区镇
- 邮编
- Google 标准化地址
- Google Place ID

展示规则：

- 长地址允许换行。
- 空值显示 `-`。
- 不显示 `null`、`undefined` 或空白占位。

### 导出

导出文件需要包含：

- `country`
- `stateRegion`
- `locality`
- `postcode`
- `formattedAddress`
- `placeId`

如果当前前端只是调用后端导出接口并下载文件，确认不需要额外列映射；如果前端本地生成 CSV，需要同步列头和字段取值。

### 搜索提示

如果当前列表有 keyword 输入框，占位文案应覆盖地区字段，例如：

```text
Search name, email, phone, ranch, country, region, town, postcode, address or notes
```

中文参考：

```text
搜索姓名、邮箱、电话、牧场、国家、地区、区镇、邮编、地址或备注
```

---

## 实施步骤

1. 确认产品测试申请接口已返回 `country`、`stateRegion`、`locality`、`postcode`、`formattedAddress`、`placeId`。
2. 更新 `product-testing-application` API 类型定义。
3. 列表页新增 `Location / 地区` 合并展示列。
4. 详情页新增完整结构化地址字段。
5. 检查导出逻辑；如前端维护导出列，则补齐新增字段。
6. 更新搜索框 placeholder 文案。
7. 补齐中英文文案。
8. 验证空值、长地址和窄屏表格展示。

---

## 验收标准

- [ ] 产品测试申请列表能看到地区摘要。
- [ ] 地区摘要按 `locality, stateRegion, postcode, country` 拼接。
- [ ] 地区字段全部为空时显示 `-`。
- [ ] 产品测试申请详情能看到国家。
- [ ] 产品测试申请详情能看到州 / 地区。
- [ ] 产品测试申请详情能看到城市 / 区镇。
- [ ] 产品测试申请详情能看到邮编。
- [ ] 产品测试申请详情能看到 Google 标准化地址。
- [ ] 产品测试申请详情能看到 Google Place ID。
- [ ] CSV/Excel 导出包含新增结构化地址字段。
- [ ] 搜索占位文案包含国家、地区、区镇、邮编和地址。
- [ ] 不显示 `null` 或 `undefined`。
- [ ] 长地址在详情页可读，不挤压其他字段。
- [ ] 现有申请状态、邮件状态、备注和资格邮件操作不受影响。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 表格列过宽 | 列表只展示合并地区列，完整字段放详情 |
| 旧数据没有结构化字段 | 空值统一显示 `-` |
| 前端导出列与后端导出重复 | 先确认导出实现方式，避免重复追加 |
| 搜索能力依赖后端 | 仅更新提示文案，不在前端假过滤 |
| 字段命名与预约线索页不一致 | 复用 `ADMIN-FE-020` 的字段文案口径 |

---

**相关文档:**

- [后台产品测试计划申请列表与资格邮件](../../completed/admin-frontend/ADMIN-FE-017-product-testing-applications.md)
- [后台预约线索展示牧场地址结构化字段](./ADMIN-FE-020-preorder-ranch-address-region-fields-display.md)
- [产品测试申请 API](../../../02-api/product-testing-applications.md)