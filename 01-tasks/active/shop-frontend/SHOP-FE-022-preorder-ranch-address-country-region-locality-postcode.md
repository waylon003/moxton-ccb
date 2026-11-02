# Tech-Spec: 预约预售表单接入 Google 牧场地址搜索

**任务ID:** SHOP-FE-022
**创建时间:** 2026-07-09
**状态:** migration_hold
**执行模式:** codex-desktop
**当前 attempt:** 0
**角色:** 独立站前端工程师
**项目:** nuxt-moxton
**优先级:** P1
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + UnoCSS + Google Places
**QA_LEVEL:** smoke

## 接管上下文（2026-11-02）

- 工作区：`E:\nuxt-moxton`；基线 `74a0227`，Google 地址和 Survey 主要实现位于原有未提交改动中。
- 前置依赖：BACKEND-028 的实际接口确认及隔离联调环境。不可用时返回阻塞，不向生产提交预约或发信。
- 本轮不改业务代码；续派前保存并核对最新 Git 差异，明确允许文件。新 worktree 不自动含这些修改。
- 必读：业务仓 `AGENTS.md`、`03-guides/codex-desktop-workflow.md`、`02-api/preorder-discounts.md`。
- 直接向父会话回报任务、attempt、命令/证据和限制，证据放 `05-verification/SHOP-FE-022/attempt-<N>`。
- 下次入口：验证 AU/NZ/Other、手填、修改后清理、无邮编、移动端和提交字段，保留已有问卷/测试报名。

---

## 概述

### 问题陈述

当前后台已有真实预约线索显示，用户会把不同层级地址混写到单一“牧场地址”字段中，例如：

- `Chudleigh, Tasmania`
- `Canterbury, New Zealand`
- `433 binginbar road Gollan nsw 2820`
- 道路名、州、邮编、国家混在同一行

根因是预约预售表单只让用户手填地址，没有国家选择，也没有地址搜索辅助。继续把国家、州/地区、城市/区镇、邮编都拆成可见输入框会让预约表单显得像正式收货地址，增加转化阻力。

独立站付款页的账单地址已经有 Google 地址快速搜索接口，本任务复用该实现，把预约表单地址采集改成轻量结构：用户只看到国家和牧场地址，系统在用户选择 Google 地址后自动解析隐藏结构化字段并随预约一起提交。

### 解决方案

在 `/preorder-discount` 牧场信息区域只展示两个地址相关控件：

1. `country`：国家选择框，默认 `Australia`，可选 `New Zealand` 和 `Other`。
2. `address` / `ranchAddress`：牧场地址输入框，接入 Google Places Autocomplete。

用户选择 Google 地址后，前端从 Google 返回的 `address_components` 中解析并保存在内存状态：

- `stateRegion`
- `locality`
- `postcode`
- `formattedAddress`
- `placeId`

用户界面不展开 `stateRegion`、`locality`、`postcode` 输入框。地址输入框选择完成后显示 Google 选择的完整地址文本。提交时把可见字段和隐藏结构化字段一起传给后端。

---

## 范围

**包含:**

- 检查付款页账单地址 Google 搜索实现并复用现有封装、配置或加载方式。
- 在预约预售表单新增 `country` 选择框。
- 将牧场地址输入框接入 Google Places Autocomplete。
- 根据国家选择限制 Google 搜索结果：`Australia` 限制 `AU`，`New Zealand` 限制 `NZ`，`Other` 不做国家限制或按现有组件能力处理。
- 选择 Google 地址后解析 `stateRegion`、`locality`、`postcode`、`formattedAddress`、`placeId`。
- 提交 payload 时携带隐藏结构化字段。
- 允许用户不选择 Google 建议，直接手填地址提交。
- 补齐中英文 i18n 文案。
- 验证桌面端和移动端布局。

**不包含:**

- 后端数据库迁移，见 `BACKEND-028`。
- 后台预约优惠码页面展示改造，见 `ADMIN-FE-020`。
- 国家 / 地区 / 城镇三级联动字典。
- 地址强校验。
- 地图定位和经纬度保存。

---

## 开发上下文

可能涉及文件：

- `pages/preorder-discount.vue`
- `components/preorder/PreorderDiscountForm.vue`
- 付款页账单地址相关组件或 composable
- `composables/api/preorder-discounts.ts`
- `types/shop.ts`
- `i18n/locales/en.ts`
- `i18n/locales/zh.ts`

相关任务：

- `SHOP-FE-020`：预约页牧场信息字段位置与测试计划勾选调整。
- `BACKEND-028`：预约预售线索保存 Google 解析后的牧场地址字段。
- `ADMIN-FE-020`：后台预约线索展示牧场地址结构化字段。

---

## 用户可见字段

| 字段 | 英文文案 | 中文文案 | 说明 |
|------|----------|----------|------|
| `country` | Country | 国家 | 默认 `Australia`，选项含 `New Zealand`、`Other` |
| `address` / `ranchAddress` | Ranch address | 牧场地址 | 接 Google 地址搜索；允许手填 |

### 可见交互

- 用户只需要选择国家并填写牧场地址。
- 地址输入框实时调用 Google 地址搜索。
- 用户选择建议后，地址输入框显示完整地址，例如 `433 Binginbar Road, Gollan NSW 2820, Australia`。
- 不额外展示州、城市、城镇、邮编输入框。
- 如需轻量确认，可在地址框下方显示一行只读文本，例如 `Detected: NSW 2820, Australia`，但不应变成可编辑表单字段。

---

## 隐藏结构化字段

Google 地址选择后，前端需要解析并保存：

| 字段 | 来源建议 | 说明 |
|------|----------|------|
| `stateRegion` | `administrative_area_level_1` | 澳洲州/领地、新西兰地区 |
| `locality` | `locality`、`postal_town`、`administrative_area_level_2`、`sublocality` 兜底 | 城市 / 区镇 / locality |
| `postcode` | `postal_code` | 邮编；解析不到允许为空 |
| `formattedAddress` | Google formatted address | Google 返回的标准化完整地址 |
| `placeId` | Google place id | 用于后续排查和去重 |

地址输入框最终提交的 `address`：

- 如果用户选择了 Google 建议，优先提交选择后的完整地址文本或 `formattedAddress`。
- 如果用户没有选择建议，提交用户手填文本。
- 不因为无法解析 `postcode` 或 `locality` 阻断提交。

---

## 提交 Payload

选择 Google 地址后的示例：

```json
{
  "firstName": "Morgan",
  "lastName": "Carter",
  "phone": "+61 400 000 000",
  "email": "morgan@example.com",
  "ranchName": "Carter Ranch",
  "country": "Australia",
  "address": "433 Binginbar Road, Gollan NSW 2820, Australia",
  "formattedAddress": "433 Binginbar Road, Gollan NSW 2820, Australia",
  "stateRegion": "New South Wales",
  "locality": "Gollan",
  "postcode": "2820",
  "placeId": "google_place_id",
  "productIds": ["product_a_id"],
  "source": "home_preorder"
}
```

用户手填但未选择 Google 地址时：

```json
{
  "country": "Australia",
  "address": "397 Bryant's Gap Road",
  "formattedAddress": null,
  "stateRegion": null,
  "locality": null,
  "postcode": null,
  "placeId": null
}
```

---

## 校验规则

- `country` 默认有值，用户可改为 `Australia`、`New Zealand`、`Other`。
- `address` 非必填，保持当前牧场信息字段的低阻力口径。
- `address` 最大长度建议 500。
- 隐藏字段均非必填。
- `postcode` 不做格式强校验。
- Google 解析失败不阻断预约提交。
- 用户手动修改已选地址后，应清空或标记旧的 `placeId`、`formattedAddress`、`stateRegion`、`locality`、`postcode`，避免提交过期结构化数据。

---

## 实施步骤

1. 定位付款页账单地址 Google 搜索实现。
2. 提取或复用现有 Google Places 加载、搜索、选择和解析逻辑。
3. 在预约预售表单中新增 `country` 选择框。
4. 将牧场地址输入框接入 Google Autocomplete。
5. 根据 `country` 限制 Google 搜索国家范围。
6. 实现 Google `address_components` 到 `stateRegion`、`locality`、`postcode` 的解析。
7. 选择地址后更新地址输入框为完整地址文本，并保存隐藏结构化字段。
8. 用户手动编辑地址时处理旧 Google 解析结果，避免提交错配字段。
9. 调整预约提交 payload。
10. 补齐中英文文案。
11. 验证澳洲地址、新西兰地址、只手填地址、切换国家、解析不到邮编五种场景。
12. 验证移动端地址搜索下拉不遮挡表单按钮。

---

## 验收标准

- [ ] 预约预售表单只展示国家选择框和牧场地址输入框，不展示州/城市/邮编输入框。
- [ ] 国家默认 `Australia`，并可选择 `New Zealand` 和 `Other`。
- [ ] 牧场地址输入框接入已有 Google 地址搜索能力。
- [ ] `Australia` 时 Google 搜索优先返回澳洲地址。
- [ ] `New Zealand` 时 Google 搜索优先返回新西兰地址。
- [ ] 用户选择 Google 地址后，地址输入框显示完整地址文本。
- [ ] 用户选择 Google 地址后，payload 包含 `stateRegion`、`locality`、`postcode`、`formattedAddress`、`placeId`。
- [ ] Google 未解析出邮编时不阻断提交。
- [ ] 用户不选择 Google 建议、只手填地址时仍可提交。
- [ ] 用户手动改动已选择地址后，不提交过期的 Google 结构化字段。
- [ ] 现有牧场名称、羊群数量、羊只品种、测试计划 checkbox、Survey 区块不受影响。
- [ ] 中英文文案完整。
- [ ] 移动端搜索下拉和表单布局不重叠、不溢出。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| Google 对牧场或乡村道路识别不完整 | 允许用户手填地址，不强制选择建议 |
| 邮编解析为空或不准 | 邮编只做辅助字段，不参与前端强校验 |
| 用户切换国家后旧地址仍存在 | 切换国家时提示或清空 Google 解析结果，避免国家和地址错配 |
| 手动编辑地址后结构化字段过期 | 手动编辑时清空 `placeId` 和解析字段，或标记为手填 |
| 表单变得像收货地址 | 不展示州/城市/邮编输入框，只隐藏提交结构化字段 |

---

**相关文档:**

- [预约页牧场信息字段位置与测试计划勾选调整](../../completed/shop-frontend/SHOP-FE-020-preorder-ranch-fields-position-adjustment.md)
- [预约预售线索保存 Google 解析后的牧场地址字段](../backend/BACKEND-028-preorder-ranch-address-country-region-locality-postcode.md)
- [后台预约线索展示牧场地址结构化字段](../admin-frontend/ADMIN-FE-020-preorder-ranch-address-region-fields-display.md)
- [预售预约优惠码 API](../../../02-api/preorder-discounts.md)
