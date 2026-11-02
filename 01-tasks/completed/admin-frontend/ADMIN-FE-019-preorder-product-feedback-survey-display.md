# Tech-Spec: 后台展示预售预约产品反馈 Survey

**任务ID:** ADMIN-FE-019
**创建时间:** 2026-07-02
**状态:** 已完成
**角色:** CRUD前端工程师
**项目:** moxton-lotadmin
**优先级:** P2
**技术栈:** Vue 3 + TypeScript + SoybeanAdmin + Naive UI
**QA_LEVEL:** smoke

---

## 概述

### 问题陈述

官网预售预约页将增加一个轻量产品反馈 Survey，用于收集用户对 Moxton 预售产品的兴趣、关键特性优先级、使用场景、价格接受范围和产品升级建议。

领导已补充新版规则：Survey 需要按用户选择的产品动态展示专属问题。因此后台展示也需要按产品分组：

- 羊毛直径分析仪反馈。
- 羊只计数相机反馈。
- 用户选择 `Both` 时，两组反馈都可能存在。
- 价格区间为用户自由填写文本，后台只展示原文，不做价格区间枚举映射。

预售预约折扣码有效期也已调整为永久有效。后台预约优惠码列表和详情如果展示有效期，需要支持 `expiresAt = null` 的永久有效状态，不再把空值误显示为 `-` 或错误状态。

领导先确认官网 UI 后，后端会保存这些 Survey 字段。后台需要在“预约优惠码”管理页面展示这些反馈，方便运营和产品团队查看真实用户需求。

### 解决方案

在后台“预约优惠码”列表和详情中展示 `productFeedbackSurvey`。

列表页只展示摘要，避免表格过宽：

- 感兴趣产品
- 是否填写羊毛直径分析仪反馈
- 是否填写羊只计数相机反馈
- 关键优先特性摘要
- 是否有开放文本反馈

详情页展示完整 Survey：

- 感兴趣产品
- 羊毛直径分析仪反馈分组
- 羊只计数相机反馈分组
- 两个产品各自的价格区间原文
- 两个产品各自的开放建议原文

---

## 范围

### 包含

- 更新预约优惠码 API 类型。
- 在预约优惠码列表展示 Survey 摘要。
- 在预约优惠码详情按产品展示完整 Survey 分组。
- 增加枚举值到中英文展示文案的映射。
- 空值统一展示 `-`。
- 长文本在列表中截断，详情中完整展示。
- 支持优惠码永久有效展示，`expiresAt = null` 时显示 `Permanent` / `永久有效`。
- 验证桌面常见宽度下表格不明显溢出。

### 不包含

- 官网 Survey UI，见 `SHOP-FE-021`。
- 后端保存 Survey 字段，见 `BACKEND-027`。
- Survey 统计报表。
- Survey 字段筛选。
- CSV 导出。
- 修改产品测试申请页面。

---

## 开发上下文

相关任务：

- `SHOP-FE-021`：官网预售预约页产品反馈 Survey UI 原型。
- `BACKEND-027`：后端保存预售预约产品反馈 Survey 字段。
- `ADMIN-FE-018`：预约优惠码后台展示牧场扩展字段。

可能涉及文件：

- `src/service/api/preorder-discount.ts`
- `src/views/preorder-discount/index.vue`
- `src/views/preorder-discount/modules/preorder-discount-detail.vue`
- `src/locales/langs/zh-cn.ts`
- `src/locales/langs/en-us.ts`

API 文档来源：

- `../../../02-api/preorder-discounts.md`

---

## 数据结构

后台前端类型建议：

```ts
interface WoolAnalyzerSurvey {
  prioritizedFeatures?: Array<
    | 'testing_accuracy'
    | 'testing_speed'
    | 'sample_preparation_efficiency'
    | 'portability'
    | 'price'
    | 'others'
  > | null
  optimizationSuggestions?: string | null
  priceRange?: string | null
  intendedUseLocations?: Array<
    | 'shed'
    | 'race'
    | 'laboratory'
    | 'office'
    | 'research_institution'
    | 'others'
  > | null
  idealTestingTime?: string | null
  desktopVersionInterest?: 'yes_desktop_needed' | 'no_portable_enough' | null
}

interface SheepCountingSurvey {
  prioritizedFeatures?: Array<
    | 'detection_accuracy'
    | 'portability'
    | 'price'
    | 'others'
  > | null
  optimizationSuggestions?: string | null
  priceRange?: string | null
  stationaryVersionInterest?: 'yes_stationary_needed' | 'no_portable_sufficient' | null
}

interface ProductFeedbackSurvey {
  interestedProduct?: 'sheep_counting_camera' | 'wool_diameter_analyzer' | 'both' | 'not_sure' | null
  woolAnalyzerSurvey?: WoolAnalyzerSurvey | null
  sheepCountingSurvey?: SheepCountingSurvey | null
  hasWoolAnalyzerSurvey?: boolean
  hasSheepCountingSurvey?: boolean
  hasOpenText?: boolean
}

interface PreorderDiscountLead {
  id: string
  // existing fields...
  productFeedbackSurvey?: ProductFeedbackSurvey | null
}
```

如果后端列表接口只返回摘要，详情接口返回完整对象，前端类型应允许产品分组字段缺省。

---

## 展示文案映射

### 感兴趣产品

| value | 英文 | 中文 |
|-------|------|------|
| `sheep_counting_camera` | Sheep Counting Camera | AI 羊只计数相机 |
| `wool_diameter_analyzer` | Wool Diameter Analyzer | AI 羊毛直径分析仪 |
| `both` | Both | 两个都感兴趣 |
| `not_sure` | Not sure yet | 还不确定 |

### 羊毛直径分析仪关键特性

| value | 英文 | 中文 |
|-------|------|------|
| `testing_accuracy` | Testing Accuracy | 检测准确性 |
| `testing_speed` | Testing Speed | 检测速度 |
| `sample_preparation_efficiency` | Sample Preparation Efficiency | 样品制备效率 |
| `portability` | Portability | 便携性 |
| `price` | Price | 价格 |
| `others` | Others | 其他 |

### 羊毛直径分析仪使用场景

| value | 英文 | 中文 |
|-------|------|------|
| `shed` | Shed | 羊棚 |
| `race` | Race | 赶羊通道 |
| `laboratory` | Laboratory | 实验室 |
| `office` | Office | 办公室 |
| `research_institution` | Research Institution | 研究机构 |
| `others` | Others | 其他 |

### 羊毛直径分析仪桌面专业版意向

| value | 英文 | 中文 |
|-------|------|------|
| `yes_desktop_needed` | Yes, I need this desktop version | 是，我需要桌面专业版 |
| `no_portable_enough` | No, the portable version meets my needs | 否，便携版已满足我的需求 |

### 羊只计数相机关键特性

| value | 英文 | 中文 |
|-------|------|------|
| `detection_accuracy` | Detection Accuracy | 识别准确性 |
| `portability` | Portability | 便携性 |
| `price` | Price | 价格 |
| `others` | Others | 其他 |

### 羊只计数相机固定式版本意向

| value | 英文 | 中文 |
|-------|------|------|
| `yes_stationary_needed` | Yes, I need this stationary version | 是，我需要固定式版本 |
| `no_portable_sufficient` | No, the portable version is sufficient | 否，便携版已足够 |

未知值处理：

- 如果后端返回未知枚举值，后台应展示原始值或 `Unknown`，不要报错。
- 中文环境可展示 `未知选项`，并在 tooltip 中保留原始值。

---

## 页面展示

### 列表页

建议新增列：

1. `Interested product` / `感兴趣产品`
2. `Survey groups` / `反馈分组`
3. `Priority features` / `优先特性`
4. `Feedback` / `开放反馈`

列表展示规则：

- `Interested product` 展示枚举映射文案。
- `Survey groups` 展示 `Wool Analyzer`、`Sheep Camera` 或 `-`。
- `Priority features` 可合并展示两组产品的关键特性摘要，最多展示 2 到 3 个标签，超出用 `+N`。
- `Feedback` 只展示 `Yes` / `No` 或图标，不展示完整长文本。
- 空值显示 `-`。

如果当前表格列已经很多，可以折中：

- 默认只新增 `Interested product` 和 `Feedback` 两列。
- 产品分组和完整反馈放到详情页。
- 或者将 Survey 摘要合并为一列，使用紧凑标签展示。

最终以页面宽度和现有表格风格为准。

### 详情页

在预约详情弹窗或抽屉中新增分组：

```text
Product feedback
```

中文：

```text
产品反馈
```

字段：

- Interested product / 感兴趣产品

羊毛直径分析仪反馈：

- Prioritized features / 优先关注特性
- Optimization suggestions / 希望优化或升级的功能
- Price range / 可接受价格区间
- Intended use locations / 计划使用场景
- Ideal testing time / 理想单次测试总时长
- Desktop version interest / 桌面专业版意向

羊只计数相机反馈：

- Prioritized features / 优先关注特性
- Optimization suggestions / 希望优化或升级的功能
- Price range / 可接受价格区间
- Stationary version interest / 固定式版本意向

详情展示规则：

- 分组应与“联系信息”“牧场信息”“优惠码信息”区分开。
- `Wool Analyzer feedback` 和 `Sheep Counting Camera feedback` 分别展示。
- 如果某个产品分组不存在，显示“未填写该产品反馈”，不要展示空字段列表。
- 开放文本使用多行文本展示，保留换行。
- 价格区间展示用户填写原文，不做格式化。
- 长文本不要撑破抽屉宽度，应自动换行。
- 空值显示 `-`。

### 有效期展示

如果预约优惠码列表或详情中展示 `expiresAt`：

- `expiresAt` 有值：按现有日期格式展示。
- `expiresAt = null`：展示 `Permanent` / `永久有效`。
- 不要展示 `null`、`undefined` 或 `-`，否则运营会误以为数据缺失。
- 不要在前端自行补成 `2026-12-31`。

---

## 交互规则

- 列表中的 Survey 字段不参与编辑。
- 详情页只读。
- 不需要新增删除或修改 Survey 的后台操作。
- 不需要单独权限，沿用预约优惠码页面现有权限。
- 如果接口返回 `productFeedbackSurvey = null`，整个分组可以展示空值，也可以显示“未填写”。
- 如果接口只返回某一个产品分组，详情页只展示该产品分组，另一个产品分组显示“未填写”或不展示。

推荐详情空态：

英文：

```text
No product feedback submitted.
```

中文：

```text
用户未填写产品反馈。
```

---

## 与其他后台页面的关系

Survey 属于预约优惠码线索，不属于产品测试申请。

因此：

- 不要把 Survey 只放到产品测试申请页面。
- 不要把填写 Survey 解释为报名测试计划。
- 产品测试申请页面后续如需展示，可单独规划，不在本任务内。

---

## 实施步骤

1. 确认 `BACKEND-027` 已完成并更新 API 文档。
2. 检查预约优惠码列表接口是否返回 `productFeedbackSurvey` 摘要。
3. 检查预约优惠码详情接口是否返回完整 `productFeedbackSurvey`。
4. 更新后台 API 类型。
5. 新增 Survey 枚举映射 helper，覆盖两个产品分组。
6. 列表页新增 Survey 摘要展示。
7. 详情页新增“产品反馈”分组，并按产品展示子分组。
8. 补齐中英文文案。
9. 支持 `expiresAt = null` 的永久有效展示。
10. 验证空值、未知枚举、长文本、多行文本、数组多选值。
11. 验证表格在常见桌面宽度下不明显溢出。

---

## 验收标准

- [ ] 后台预约优惠码列表能展示 Survey 摘要。
- [ ] 后台预约详情能展示完整 Survey。
- [ ] 感兴趣产品展示为可读文案。
- [ ] 羊毛直径分析仪关键特性展示为可读文案。
- [ ] 羊毛直径分析仪使用场景展示为可读文案。
- [ ] 羊毛直径分析仪桌面专业版意向展示为可读文案。
- [ ] 羊只计数相机关键特性展示为可读文案。
- [ ] 羊只计数相机固定式版本意向展示为可读文案。
- [ ] 两个产品的价格区间均展示用户填写原文。
- [ ] 两个产品的开放建议在详情中完整展示。
- [ ] 空值显示 `-` 或“未填写”，不显示 `null`、`undefined`。
- [ ] 未填写 Survey 的历史记录不报错。
- [ ] 未报名测试计划但填写 Survey 的记录也能展示。
- [ ] 报名测试计划并填写 Survey 的记录也能展示。
- [ ] 选择 `Both` 的记录能展示两组产品反馈。
- [ ] `expiresAt = null` 时展示为永久有效。
- [ ] 后台不再把永久有效误显示为普通空值。
- [ ] 未知枚举值不会导致页面崩溃。
- [ ] 表格没有明显横向溢出。
- [ ] 中英文文案已补齐。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 表格列过多 | 只展示摘要，完整内容放详情 |
| 后端列表只返回摘要 | 类型允许产品分组字段缺省，详情再展示完整文本 |
| 未知枚举导致渲染异常 | 映射 helper 做 fallback |
| Survey 与测试计划混淆 | 后台分组命名为“产品反馈”，不放到测试计划分组 |
| 长文本撑破详情页 | 使用自动换行和最大宽度样式 |
| 价格字段格式不统一 | 后台只展示用户填写原文，不做数值解释 |
| 永久有效被误判为空值 | `expiresAt = null` 单独映射为 `Permanent` / `永久有效` |

---

## 相关文档

- [预售预约优惠码 API](../../../02-api/preorder-discounts.md)
- [官网预售预约页产品反馈 Survey UI 原型](../shop-frontend/SHOP-FE-021-preorder-product-feedback-survey-ui.md)
- [后端保存预售预约产品反馈 Survey 字段](../backend/BACKEND-027-preorder-product-feedback-survey-fields.md)
- [预约优惠码后台展示牧场扩展字段](./ADMIN-FE-018-preorder-lead-ranch-fields-display.md)

