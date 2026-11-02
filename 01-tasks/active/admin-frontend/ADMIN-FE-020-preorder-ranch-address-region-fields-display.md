# Tech-Spec: 后台预约线索展示牧场地址结构化字段

**任务ID:** ADMIN-FE-020
**创建时间:** 2026-07-09
**状态:** 待开发
**角色:** CRUD前端工程师
**项目:** moxton-lotadmin
**优先级:** P1
**技术栈:** Vue 3 + TypeScript + SoybeanAdmin + Naive UI
**QA_LEVEL:** smoke

---

## 概述

### 问题陈述

官网预约预售表单会只展示 `Country` 和 `Ranch address`，并通过 Google 地址搜索在前端解析隐藏结构化字段。后台需要展示这些最终保存的数据，否则运营仍只能看到一段混写地址，无法按国家、地区、城镇或邮编快速判断线索所在位置。

### 解决方案

调整后台“预约优惠码”列表和详情：

1. 更新预约优惠码 API 类型，接收 `country`、`stateRegion`、`locality`、`postcode`、`address`、`formattedAddress`、`placeId`。
2. 列表页展示关键地区字段，建议展示国家、州/地区、城市/区镇、邮编和牧场地址。
3. 详情页展示完整地址分组，包含用户提交地址、Google 标准化地址、国家、州/地区、城市/区镇、邮编、Place ID。
4. keyword 搜索提示或占位文案覆盖地区和邮编搜索能力。
5. 空值统一显示 `-`。

---

## 范围

**包含:**

- 更新预约优惠码列表和详情接口类型。
- 列表页新增国家、州/地区、城市/区镇、邮编展示。
- 详情页“牧场地址”分组新增完整结构化字段。
- 空值展示处理。
- 长地址截断或换行处理。
- 补齐中英文文案。
- 验证常见桌面宽度和窄屏展示。

**不包含:**

- 后端保存和返回字段，见 `BACKEND-028`。
- 官网 Google 地址搜索，见 `SHOP-FE-022`。
- 地区筛选器和统计报表。
- Google Place ID 跳转或地图预览。
- 导出功能。

---

## 开发上下文

可能涉及文件：

- `src/service/api/preorder-discount.ts`
- `src/views/preorder-discount/index.vue`
- `src/views/preorder-discount/modules/preorder-discount-detail.vue`
- `src/locales/langs/zh-cn.ts`
- `src/locales/langs/en-us.ts`

相关任务：

- `SHOP-FE-022`：预约预售表单接入 Google 牧场地址搜索。
- `BACKEND-028`：预约预售线索保存 Google 解析后的牧场地址字段。
- `ADMIN-FE-018`：预约优惠码后台展示牧场扩展字段。

---

## 字段口径

| 字段 | 英文文案 | 中文文案 | 展示位置 |
|------|----------|----------|----------|
| `country` | Country | 国家 | 列表、详情 |
| `stateRegion` | State / Region | 州 / 地区 | 列表、详情 |
| `locality` | City / Suburb / Town | 城市 / 区镇 | 列表、详情 |
| `postcode` | Postcode | 邮编 | 列表、详情 |
| `address` | Ranch address | 牧场地址 | 列表、详情 |
| `formattedAddress` | Google formatted address | Google 标准化地址 | 详情 |
| `placeId` | Google Place ID | Google Place ID | 详情 |

说明：

- `address` 是用户最终提交的牧场地址文本，可能来自 Google 选择，也可能是手填。
- `formattedAddress` 和 `placeId` 可能为空，后台不要显示 `null` 或 `undefined`。
- `stateRegion`、`locality`、`postcode` 是 Google 解析结果，允许为空。

---

## 页面展示

### 列表页

建议列表字段：

- 姓名
- 邮箱
- 电话
- 国家
- 州 / 地区
- 城市 / 区镇
- 邮编
- 牧场地址
- 预约产品
- 邮件状态
- 提交时间
- 操作

列表列宽要求：

- 国家、州/地区、城市/区镇、邮编允许单行省略。
- 牧场地址允许单行省略，完整内容放详情。
- 如果表格过宽，可把 `formattedAddress` 和 `placeId` 只放详情。

### 详情页

新增或扩展“牧场地址”分组：

- 国家
- 州 / 地区
- 城市 / 区镇
- 邮编
- 牧场地址
- Google 标准化地址
- Google Place ID

展示规则：

- 长地址支持换行。
- 空值显示 `-`。
- 不显示 `null`、`undefined`、空白区域。
- `placeId` 可作为普通文本展示，不要求可点击。

### 搜索提示

如果当前列表有 keyword 输入框，占位文案应覆盖地区字段，例如：

```text
Search name, email, phone, ranch, country, region, town, postcode, address, product or code
```

中文参考：

```text
搜索姓名、邮箱、电话、牧场、国家、地区、区镇、邮编、地址、产品或优惠码
```

---

## 实施步骤

1. 确认 `BACKEND-028` 接口字段已返回，或使用联调 mock 数据验证。
2. 更新预约优惠码 API 类型，加入 Google 地址结构化字段。
3. 列表页新增国家、州/地区、城市/区镇、邮编、牧场地址列。
4. 详情页新增完整牧场地址分组。
5. 更新 keyword 输入框占位文案。
6. 补齐中英文文案。
7. 验证空值、长地区名、长地址、无 Google 解析字段展示。
8. 验证桌面端表格无明显溢出，窄屏可正常横向滚动或自适应。

---

## 验收标准

- [ ] 预约优惠码列表能看到国家。
- [ ] 预约优惠码列表能看到州 / 地区。
- [ ] 预约优惠码列表能看到城市 / 区镇。
- [ ] 预约优惠码列表能看到邮编。
- [ ] 预约优惠码列表能看到牧场地址。
- [ ] 预约优惠码详情能看到 Google 标准化地址和 Place ID。
- [ ] 手填地址且无 Google 解析字段时，后台空字段显示 `-`。
- [ ] 不显示 `null` 或 `undefined`。
- [ ] 长地址在详情页可读，不挤压其他字段。
- [ ] keyword 占位文案包含国家、地区、区镇、邮编、地址。
- [ ] 现有牧场名称、羊群数量、羊只品种展示不受影响。
- [ ] 中英文文案完整。
- [ ] 常见桌面宽度下表格不明显溢出。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 后端接口未返回字段 | 先确认 `BACKEND-028`，缺字段时不做假展示 |
| 表格列过多 | 列表展示关键字段，Google 标准化地址和 Place ID 放详情 |
| Google 解析字段为空 | 统一显示 `-` |
| 用户手填地址无 `placeId` | 允许空值，不误判为异常 |
| 与牧场详细地址混淆 | 详情页明确区分用户提交地址和 Google 标准化地址 |

---

**相关文档:**

- [预约预售表单接入 Google 牧场地址搜索](../shop-frontend/SHOP-FE-022-preorder-ranch-address-country-region-locality-postcode.md)
- [预约预售线索保存 Google 解析后的牧场地址字段](../backend/BACKEND-028-preorder-ranch-address-country-region-locality-postcode.md)
- [预售预约优惠码 API](../../../02-api/preorder-discounts.md)
