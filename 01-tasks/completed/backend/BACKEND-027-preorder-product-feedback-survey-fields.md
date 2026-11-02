# Tech-Spec: 后端保存预售预约产品反馈 Survey 字段

**任务ID:** BACKEND-027
**创建时间:** 2026-07-02
**状态:** 已完成
**角色:** 后端工程师
**项目:** moxton-lotapi
**优先级:** P2
**技术栈:** Node.js + Koa + TypeScript + Prisma + MySQL
**QA_LEVEL:** full

---

## 概述

### 问题陈述

官网预售预约页计划增加一个轻量产品反馈 Survey，用于了解用户对 Moxton 预售产品的兴趣、关键特性优先级、使用场景、价格接受范围和产品升级建议。

领导已补充新版规则：Survey 需要按用户选择的产品动态展示专属问题。

- 用户选择 `Wool Diameter Analyzer` 时，提交羊毛直径分析仪专属问题。
- 用户选择 `Sheep Counting Camera` 时，提交羊只计数相机专属问题。
- 用户选择 `Both` 时，可同时提交两组产品问题。
- 价格区间由用户自由填写，后端按字符串保存，不做固定枚举和数值解析。

同时，预售预约折扣码有效期口径已调整为永久有效，不再按 2026 年 12 月 31 日到期展示。后端接入本任务或后续修改预约优惠码逻辑时，需要避免继续生成或返回固定年底到期日。

第一阶段由官网项目 `nuxt-moxton` 先实现 UI 原型，给领导确认体验和视觉。领导认可后，后端需要支持保存这些反馈字段，并让后台可以查看。

当前预约优惠码接口的核心对象是 `PreorderDiscountLead`，一位用户一次提交可以选择多个预售产品，后端会按产品拆成多条 lead。Survey 反馈属于这次预约提交的用户意向信息，需要能和预约 lead 一起查看。

### 解决方案

在预约优惠码提交接口中新增根级对象：

```json
{
  "productFeedbackSurvey": {
    "interestedProduct": "both",
    "woolAnalyzerSurvey": {
      "prioritizedFeatures": ["testing_accuracy", "testing_speed"],
      "optimizationSuggestions": "Need easier sample preparation.",
      "priceRange": "$1,000-$2,000",
      "intendedUseLocations": ["shed", "laboratory"],
      "idealTestingTime": "Under 3 minutes including sample preparation",
      "desktopVersionInterest": "yes_desktop_needed"
    },
    "sheepCountingSurvey": {
      "prioritizedFeatures": ["detection_accuracy", "portability"],
      "optimizationSuggestions": "Improve accuracy in dusty yards.",
      "priceRange": "Under $1,000",
      "stationaryVersionInterest": "no_portable_sufficient"
    }
  }
}
```

后端保存策略建议：

- 第一版直接在 `PreorderDiscountLead` 增加可空 JSON 字段 `productFeedbackSurvey`。
- 同一次提交选择多个产品时，每条 lead 都保存同一份 Survey 数据。
- 后台列表接口可以返回摘要字段。
- 后台详情接口返回完整 Survey 对象。

选择 JSON 字段的原因：

- Survey 字段仍处于领导评审和早期验证阶段，后续可能调整选项。
- 使用 JSON 可以降低数据库迁移频率。
- 后台只需要展示，不需要复杂统计。

如果后续需要按字段筛选或统计，再拆分为独立列或独立表。

---

## 范围

### 包含

- `POST /preorder-discounts/claim` 接收 `productFeedbackSurvey`。
- 对 Survey 字段做类型、枚举、长度校验。
- 保存 Survey 到预约优惠码 lead。
- 一次提交多个产品时，每条 lead 保存同一份 Survey。
- 后台预约列表接口返回 Survey 摘要。
- 后台预约详情接口返回完整 Survey。
- 更新 `02-api/preorder-discounts.md`。
- 同步预约优惠码永久有效口径，避免继续写死 `2026-12-31`。
- 增加测试或脚本验证。

### 不包含

- 官网 Survey UI 原型，见 `SHOP-FE-021`。
- 后台展示实现，见 `ADMIN-FE-019`。
- Survey 统计报表。
- CSV 导出。
- 按 Survey 字段筛选。
- A/B 测试。

---

## 开发上下文

相关任务：

- `SHOP-FE-021`：官网预售预约页产品反馈 Survey UI 原型。
- `ADMIN-FE-019`：后台展示预售预约产品反馈 Survey。
- `BACKEND-026`：预约优惠码线索补充牧场扩展字段。

相关 API 文档：

- `../../../02-api/preorder-discounts.md`

可能涉及后端文件：

- `prisma/schema.prisma`
- `src/controllers/PreorderDiscount.ts`
- `src/models/PreorderDiscountLead.ts`
- `src/routes/preorder-discounts.ts`
- 预约优惠码相关类型文件
- 测试或脚本目录

---

## 数据结构

### 请求对象

```ts
interface WoolAnalyzerSurveyInput {
  prioritizedFeatures?: Array<
    | 'testing_accuracy'
    | 'testing_speed'
    | 'sample_preparation_efficiency'
    | 'portability'
    | 'price'
    | 'others'
  >
  optimizationSuggestions?: string
  priceRange?: string
  intendedUseLocations?: Array<
    | 'shed'
    | 'race'
    | 'laboratory'
    | 'office'
    | 'research_institution'
    | 'others'
  >
  idealTestingTime?: string
  desktopVersionInterest?: 'yes_desktop_needed' | 'no_portable_enough'
}

interface SheepCountingSurveyInput {
  prioritizedFeatures?: Array<
    | 'detection_accuracy'
    | 'portability'
    | 'price'
    | 'others'
  >
  optimizationSuggestions?: string
  priceRange?: string
  stationaryVersionInterest?: 'yes_stationary_needed' | 'no_portable_sufficient'
}

interface ProductFeedbackSurveyInput {
  interestedProduct?: 'sheep_counting_camera' | 'wool_diameter_analyzer' | 'both' | 'not_sure'
  woolAnalyzerSurvey?: WoolAnalyzerSurveyInput
  sheepCountingSurvey?: SheepCountingSurveyInput
}
```

### 数据库字段建议

在 `PreorderDiscountLead` 增加：

```prisma
model PreorderDiscountLead {
  // existing fields...
  productFeedbackSurvey Json?
  // existing fields...
}
```

字段说明：

| 字段 | 类型 | 说明 |
|------|------|------|
| `productFeedbackSurvey` | `Json?` | 用户在预约页填写的产品反馈 Survey，可为空 |

兼容要求：

- 历史 lead 返回 `null`。
- 未填写 Survey 的新 lead 返回 `null`。
- 部分填写时只保存有值字段。

---

## 字段校验

### 总体规则

- `productFeedbackSurvey` 非必填。
- 缺省、`null`、空对象都视为未填写，保存为 `null`。
- 如果传入非对象类型，返回 validation error。
- 未识别字段可以忽略，也可以拒绝；推荐第一版忽略未知字段，避免前端试验字段造成失败。

### 触发字段

`interestedProduct` 合法值：

- `sheep_counting_camera`
- `wool_diameter_analyzer`
- `both`
- `not_sure`

规则：

- 空字符串转为 `undefined`。
- 非空但不在合法枚举内时返回 validation error。
- `interestedProduct = wool_diameter_analyzer` 时，允许保存 `woolAnalyzerSurvey`。
- `interestedProduct = sheep_counting_camera` 时，允许保存 `sheepCountingSurvey`。
- `interestedProduct = both` 时，允许同时保存两组产品 Survey。
- `interestedProduct = not_sure` 或空值时，后端可以忽略产品专属 Survey，也可以保存但不推荐；推荐规范化时移除隐藏分组数据。

### 羊毛直径分析仪字段

`woolAnalyzerSurvey.prioritizedFeatures` 合法值：

- `testing_accuracy`
- `testing_speed`
- `sample_preparation_efficiency`
- `portability`
- `price`
- `others`

`woolAnalyzerSurvey.intendedUseLocations` 合法值：

- `shed`
- `race`
- `laboratory`
- `office`
- `research_institution`
- `others`

`woolAnalyzerSurvey.desktopVersionInterest` 合法值：

- `yes_desktop_needed`
- `no_portable_enough`

校验规则：

- 多选字段非必填。
- 多选字段如果传入，必须是数组。
- 数组内空字符串应过滤。
- 数组内非法值返回 validation error。
- 数组应去重，保持前端顺序或后端固定顺序均可，但需口径一致。

文本字段：

- `woolAnalyzerSurvey.optimizationSuggestions`：最大 1000 字符。
- `woolAnalyzerSurvey.priceRange`：最大 200 字符，按用户原文保存，不做价格解析。
- `woolAnalyzerSurvey.idealTestingTime`：最大 200 字符。

### 羊只计数相机字段

`sheepCountingSurvey.prioritizedFeatures` 合法值：

- `detection_accuracy`
- `portability`
- `price`
- `others`

`sheepCountingSurvey.stationaryVersionInterest` 合法值：

- `yes_stationary_needed`
- `no_portable_sufficient`

校验规则：

- 多选字段非必填。
- 多选字段如果传入，必须是数组。
- 数组内空字符串应过滤。
- 数组内非法值返回 validation error。
- 数组应去重。

文本字段：

- `sheepCountingSurvey.optimizationSuggestions`：最大 1000 字符。
- `sheepCountingSurvey.priceRange`：最大 200 字符，按用户原文保存，不做价格解析。

### 文本字段通用规则

- 非必填。
- trim。
- 空字符串转为 `undefined`。
- 超长返回 validation error。
- 不需要做敏感词处理，后续如有运营需求再补。

---

## API 调整

### 用户侧提交预约

```http
POST /preorder-discounts/claim
```

请求体新增：

```json
{
  "productFeedbackSurvey": {
    "interestedProduct": "both",
    "woolAnalyzerSurvey": {
      "prioritizedFeatures": ["testing_accuracy", "testing_speed"],
      "optimizationSuggestions": "Need easier sample preparation.",
      "priceRange": "$1,000-$2,000",
      "intendedUseLocations": ["shed", "laboratory"],
      "idealTestingTime": "Under 3 minutes including sample preparation",
      "desktopVersionInterest": "yes_desktop_needed"
    },
    "sheepCountingSurvey": {
      "prioritizedFeatures": ["detection_accuracy", "portability"],
      "optimizationSuggestions": "Improve accuracy in dusty yards.",
      "priceRange": "Under $1,000",
      "stationaryVersionInterest": "no_portable_sufficient"
    }
  }
}
```

完整示例：

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
  "productIds": ["product_a_id", "product_b_id"],
  "source": "home_preorder",
  "testingProgramOptIn": false,
  "productFeedbackSurvey": {
    "interestedProduct": "both",
    "woolAnalyzerSurvey": {
      "prioritizedFeatures": ["testing_accuracy", "testing_speed"],
      "optimizationSuggestions": "Need easier sample preparation.",
      "priceRange": "$1,000-$2,000",
      "intendedUseLocations": ["shed", "laboratory"],
      "idealTestingTime": "Under 3 minutes including sample preparation",
      "desktopVersionInterest": "yes_desktop_needed"
    },
    "sheepCountingSurvey": {
      "prioritizedFeatures": ["detection_accuracy", "portability"],
      "optimizationSuggestions": "Improve accuracy in dusty yards.",
      "priceRange": "Under $1,000",
      "stationaryVersionInterest": "no_portable_sufficient"
    }
  }
}
```

### 后台列表

```http
GET /preorder-discounts/admin/leads
```

列表项建议返回：

```json
{
  "id": "lead_a_id",
  "productFeedbackSurvey": {
    "interestedProduct": "both",
    "hasWoolAnalyzerSurvey": true,
    "hasSheepCountingSurvey": true,
    "woolPrioritizedFeatures": ["testing_accuracy", "testing_speed"],
    "sheepCountingPrioritizedFeatures": ["detection_accuracy", "portability"],
    "hasOpenText": true
  }
}
```

说明：

- 列表可以不返回完整开放文本，避免长文本撑大表格数据。
- 如果实现简单，也可以直接返回完整对象，由后台前端自行截断。

### 后台详情

```http
GET /preorder-discounts/admin/leads/:id
```

详情返回完整对象：

```json
{
  "productFeedbackSurvey": {
    "interestedProduct": "both",
    "woolAnalyzerSurvey": {
      "prioritizedFeatures": ["testing_accuracy", "testing_speed"],
      "optimizationSuggestions": "Need easier sample preparation.",
      "priceRange": "$1,000-$2,000",
      "intendedUseLocations": ["shed", "laboratory"],
      "idealTestingTime": "Under 3 minutes including sample preparation",
      "desktopVersionInterest": "yes_desktop_needed"
    },
    "sheepCountingSurvey": {
      "prioritizedFeatures": ["detection_accuracy", "portability"],
      "optimizationSuggestions": "Improve accuracy in dusty yards.",
      "priceRange": "Under $1,000",
      "stationaryVersionInterest": "no_portable_sufficient"
    }
  }
}
```

---

## 与现有业务的关系

### 与预约优惠码 lead 的关系

Survey 是预约 lead 的补充信息：

- 不影响优惠码生成。
- 不影响邮件发送。
- 不参与同邮箱同产品去重。
- 不影响 `submissionId` 生成。
- 不影响产品选择上限。

有效期口径：

- 当前业务要求优惠码永久有效。
- 如果数据库和接口继续保留 `expiresAt` 字段，建议允许为 `null` 表示永久有效。
- 后台列表和详情接口返回 `expiresAt = null` 时，前端应展示 `Permanent` / `永久有效` 或不展示有效期。
- 不应再由后端默认写入 `2026-12-31`。
- API 文档中的示例也需要同步改为 `expiresAt: null`。

### 与产品测试计划的关系

Survey 不是产品测试计划报名：

- 用户不勾选 `testingProgramOptIn` 也可以填写 Survey。
- 用户填写 Survey 不代表报名测试计划。
- 后台展示时应与测试计划申请区分。

### 与牧场字段的关系

Survey 和牧场字段都属于预约线索补充信息，但含义不同：

- 牧场字段描述用户现有牧场情况。
- Survey 描述用户产品兴趣、关键特性优先级、使用场景、价格接受范围和产品升级建议。

---

## 实施步骤

1. 确认 `BACKEND-026` 是否已完成，如果未完成，需要避免迁移冲突。
2. 修改 `prisma/schema.prisma`，在 `PreorderDiscountLead` 增加 `productFeedbackSurvey Json?`。
3. 生成 Prisma 迁移。
4. 新增 `normalizeProductFeedbackSurvey` helper。
5. 在 claim controller 中读取并校验 `body.productFeedbackSurvey`。
6. 将规范化后的 Survey 传入 `claimMany` / lead 创建逻辑。
7. 确保一产品一 lead 时每条 lead 都保存同一份 Survey。
8. 后台列表接口返回 Survey 摘要或完整对象。
9. 后台详情接口返回完整对象。
10. 更新 `02-api/preorder-discounts.md`。
11. 确认预约优惠码有效期口径为永久有效，接口示例不再写死 2026 年底。
12. 增加接口测试或脚本验证。

---

## 验收标准

- [ ] `PreorderDiscountLead` 支持保存 `productFeedbackSurvey`。
- [ ] 不传 `productFeedbackSurvey` 时预约流程正常。
- [ ] 传空对象时保存为 `null` 或空对象，口径一致。
- [ ] 传合法 Survey 时每条预约 lead 都保存成功。
- [ ] 一次提交多个产品时，每条 lead 都保存同一份 Survey。
- [ ] 非法枚举值返回 validation error。
- [ ] 多选字段传入非数组时返回 validation error。
- [ ] 多选字段会过滤空值并去重。
- [ ] `woolAnalyzerSurvey.priceRange` 按字符串原文保存。
- [ ] `sheepCountingSurvey.priceRange` 按字符串原文保存。
- [ ] 价格字段不做固定区间枚举校验。
- [ ] 开放文本超长返回 validation error。
- [ ] Survey 不影响优惠码生成。
- [ ] Survey 不影响邮件发送。
- [ ] Survey 不影响重复领取判断。
- [ ] 后台列表接口返回 Survey 摘要或完整对象。
- [ ] 后台详情接口返回完整 Survey。
- [ ] 历史记录无 Survey 时接口返回 `null`，不报错。
- [ ] 新预约优惠码不再默认写入 2026 年底有效期。
- [ ] `expiresAt = null` 时表示永久有效，接口和后台不报错。
- [ ] API 文档已更新。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 领导评审后字段变化 | 使用 JSON 字段，降低迁移成本 |
| Survey 被误用于测试计划报名 | 字段命名为 `productFeedbackSurvey`，不放进 `testingProgram` |
| 列表返回长文本影响性能和展示 | 列表可返回摘要，详情返回完整对象 |
| 多产品提交数据不一致 | `claimMany` 中同一次提交复用同一份 Survey |
| 前端第一阶段未提交字段 | 本任务排在领导确认后实施 |
| 价格区间格式不统一 | 按自由文本保存和展示，暂不做统计 |
| `Both` 场景数据较多 | 使用 JSON 字段整体保存，详情页完整展示 |
| 有效期仍使用旧配置 | 明确 `expiresAt = null` 或等价永久有效口径，更新 API 示例 |

---

## 相关文档

- [预售预约优惠码 API](../../../02-api/preorder-discounts.md)
- [官网预售预约页产品反馈 Survey UI 原型](../shop-frontend/SHOP-FE-021-preorder-product-feedback-survey-ui.md)
- [后台展示预售预约产品反馈 Survey](../admin-frontend/ADMIN-FE-019-preorder-product-feedback-survey-display.md)

