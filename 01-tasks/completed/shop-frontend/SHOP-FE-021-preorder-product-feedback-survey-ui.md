# Tech-Spec: 官网预售预约页产品反馈 Survey UI 原型

**任务ID:** SHOP-FE-021
**创建时间:** 2026-07-02
**状态:** 已完成
**角色:** 独立站前端工程师
**项目:** nuxt-moxton
**优先级:** P1
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + UnoCSS
**QA_LEVEL:** smoke

---

## 概述

### 问题陈述

二维码内容为：

```text
https://moxton.ai/preorder-discount?source=home_preorder
```

用户扫码后会进入官网预售产品预约页面。当前页面核心目标是领取预售折扣码、选择感兴趣的预售产品，并可选申请产品测试计划。领导希望在用户进入该页面时增加一个目的：收集用户对产品的意见和需求，类似轻量 survey。

领导已补充新版需求：Survey 需要按用户选择的产品动态展示专属问题。

- 用户选择 `Wool Diameter Analyzer` 时，展示羊毛直径分析仪专属问题。
- 用户选择 `Sheep Counting Camera` 时，展示羊只计数相机专属问题。
- 用户选择 `Both` 时，同时展示两组产品专属问题。
- 用户选择 `Not sure yet` 或未选择时，不展示产品专属追问。
- 价格区间不提供固定选项，由用户自由填写。

领导同时要求调整预售预约页首屏口径：页面从单纯“预售折扣码领取”转为“预售 Survey + 15% 发布折扣码”。因此首屏横幅、主标题、副标题和权益清单需要同步更新，且优惠码有效期改为永久有效，不再展示到 2026 年底。

需要注意：

- 预约页的第一目标仍然是获取预约线索和折扣码领取转化。
- Survey 不能像独立问卷一样抢走主流程。
- 第一阶段只需要在官网项目做 UI 原型，方便给领导确认体验和视觉。
- 领导认可后，再补后端存储和后台查看能力。

### 解决方案

在 `/preorder-discount` 现有表单内嵌一个轻量产品反馈区块，不做弹窗、不做单独问卷页、不强制跳转。

Survey 采用“先选择产品，再条件展示追问”的结构：

1. 先展示一个通用问题：用户最感兴趣的产品。
2. 根据通用问题的选择结果，展示对应产品的专属问题组。
3. 每个产品问题组使用独立标题和轻量分隔，避免用户误以为所有问题都必须填写。
4. 所有 Survey 问题第一版均非必填。

推荐位置：

1. 基础联系信息之后。
2. 牧场信息之后。
3. 产品测试计划 checkbox 之前。
4. 提交按钮之前。

推荐理由：

- 用户已经进入填写状态，此时询问产品需求最自然。
- 不阻断用户阅读首屏权益和填写联系方式。
- 放在测试计划前，可以把“产品需求反馈”和“申请测试计划”区分开。
- 不改变产品选择弹窗职责，产品选择弹窗仍只负责选择预约产品。

### 阶段策略

本任务为第一阶段：

- 只实现官网 UI 原型。
- 不依赖后端新增字段。
- 默认不把 survey 数据提交到接口，或仅在代码中预留组装函数但不启用。
- 重点产出可截图、可演示、可给领导评审的页面效果。

第二阶段见：

- `BACKEND-027`：后端保存预约反馈 Survey 字段。
- `ADMIN-FE-019`：后台预约优惠码页面展示 Survey 反馈。

---

## 范围

### 包含

- 在官网 `/preorder-discount` 表单内新增产品反馈 Survey UI。
- 调整 `/preorder-discount` 首屏 Hero 文案和权益清单。
- 移除首屏“Valid until December 31, 2026”展示。
- 新增永久有效口径，前端不再写死年底有效期。
- Survey 与当前页面视觉保持一致，不突兀。
- 支持桌面端和移动端响应式展示。
- Survey 字段第一版全部非必填，降低转化阻力。
- 支持按产品选择动态展示专属问题。
- 支持多选题、单选题、自由文本题和说明型问题。
- 价格区间题使用自由文本输入，不提供固定价格选项。
- 表单提交主路径保持不变。
- 产品选择弹窗保持不变。
- 补齐中英文 i18n 文案。
- 为后续后端接入预留清晰字段名和数据结构。

### 不包含

- 后端数据库字段变更。
- `POST /preorder-discounts/claim` 接口入参变更。
- 后台预约线索页面展示变更。
- Survey 数据导出。
- Survey 分析报表。
- A/B 测试系统。

---

## 开发上下文

当前官网预售页相关文件：

- `pages/preorder-discount.vue`
- `components/preorder/PreorderDiscountForm.vue`
- `components/preorder/PreorderProductSelectModal.vue`
- `components/preorder/PreorderProductShowcase.vue`
- `types/shop.ts`
- `i18n/locales/en.ts`
- `i18n/locales/zh.ts`

当前表单已有字段：

- `firstName`
- `lastName`
- `phone`
- `email`
- `ranchName`
- `address`
- `sheepCount`
- `sheepBreed`
- `testingProgramOptIn`
- `source`

当前表单提交流程：

1. 用户填写主表单。
2. 点击提交。
3. 打开产品选择弹窗。
4. 用户选择 1 到 2 个预售产品。
5. 调用 `preorderDiscountsApi.claim`。
6. 根据响应展示成功、警告或错误提示。

本任务不应破坏以上流程。

---

## 用户体验设计

### 设计原则

- **轻量**：不让用户感觉又多了一个完整问卷。
- **非阻断**：不使用首屏弹窗、强制遮罩、单独问卷页。
- **贴合语境**：文案围绕牧场需求和产品改进，而不是泛泛“满意度调查”。
- **低压力**：全部问题非必填，用户可快速跳过。
- **可演示**：第一版要适合截图给领导看，视觉完整但不过度设计。

### 区块标题

英文：

```text
Help us understand your ranch needs
```

中文：

```text
帮助我们了解你的牧场需求
```

### 区块说明

英文：

```text
A few quick answers help us shape the launch version for real ranch workflows.
```

中文：

```text
简单补充几个问题，能帮助我们把正式发布版本做得更贴近真实牧场工作流。
```

### 视觉要求

- 放在现有白色表单卡片内部。
- 不再套一个很重的大卡片，避免“卡片套卡片”。
- 可以使用轻量分隔标题、浅色背景带、细边框或小图标增强层次。
- 选项建议使用 pill / segmented button / radio tile 风格。
- 选中态使用官网当前橙色主色。
- 移动端选项一列或两列自适应，不允许文字溢出。
- 开放文本框高度适中，默认 3 行左右。

---

## 首屏 Hero 文案调整

本节为明确替换要求。实现时按“旧文案 -> 新文案”逐项替换，不要保留旧的预售折扣页口径。

### 文案替换总表

| 位置 | 旧文案 | 新文案 | 备注 |
|------|--------|--------|------|
| 顶部横幅 | `EXCLUSIVE PRE-LAUNCH OFFER` | `EXCLUSIVE PRE-LAUNCH SURVEY OFFER` | 全大写 |
| 主标题 | `Thank You For Your Interest Save 15% On Official Launch` | `Help Us Shape the Next Generation of Livestock Testing Tools` | 替换整段标题，不再在标题里展示 `15%` |
| 副标题 | `Share your details to secure your exclusive discount code, redeemable once our smart livestock devices officially launch.` | `We are collecting user feedback, product preferences and purchase plans to improve our smart livestock devices. Share your feedback, and we'll send you an exclusive 15% launch discount code for official release.` | `15%` 高亮 |
| 权益 1 | `Receive your 15% discount code by email` | `Get your unique discount code delivered via email` | 保留邮件图标 |
| 权益 2 | `Use the code on selected Moxton products` | `Valid for eligible Moxton livestock equipment` | 保留设备/盾牌类图标均可 |
| 权益 3 | `Valid until December 31, 2026` | 删除 | 不展示固定有效期 |

说明：

- 用户原始消息中的 `yourexclusive`、`redeemableonce`、`officiallylaunch` 是粘贴时缺少空格，实际旧文案按页面现有空格版本匹配。
- 用户原始消息中的 `discount coude` 应修正为 `discount code` 后展示。
- `15%` 必须高亮，沿用当前橙色主色。

### 顶部横幅

旧文案：

```text
EXCLUSIVE PRE-LAUNCH OFFER
```

新文案：

```text
EXCLUSIVE PRE-LAUNCH SURVEY OFFER
```

中文参考：

```text
预发布调研专属优惠
```

### 主标题

旧文案：

```text
Thank You For Your Interest
Save 15% On Official Launch
```

新文案：

```text
Help Us Shape the Next Generation of Livestock Testing Tools
```

中文参考：

```text
帮助我们打造下一代智能畜牧检测工具
```

### 副标题

旧文案：

```text
Share your details to secure your exclusive discount code, redeemable once our smart livestock devices officially launch.
```

新文案：

```text
We are collecting user feedback, product preferences and purchase plans to improve our smart livestock devices. Share your feedback, and we'll send you an exclusive 15% launch discount code for official release.
```

说明：

- 用户原始反馈中 `discount coude` 应修正为 `discount code`。
- `15%` 必须高亮，沿用当前橙色主色。
- 文案里的 `15% launch discount code` 是页面核心利益点，不应弱化。

中文参考：

```text
我们正在收集用户反馈、产品偏好和购买计划，用于改进 Moxton 智能畜牧设备。分享你的反馈后，我们会通过邮件发送正式发布时可使用的专属 15% 折扣码。
```

### 权益清单

旧权益清单：

```text
Receive your 15% discount code by email
Use the code on selected Moxton products
Valid until December 31, 2026
```

新权益清单：

```text
Get your unique discount code delivered via email
Valid for eligible Moxton livestock equipment
```

中文参考：

```text
通过邮件获取你的专属折扣码
适用于符合条件的 Moxton 畜牧设备
```

### 有效期展示规则

- 不再展示 `Valid until December 31, 2026`。
- 当前业务口径为永久有效。
- 首屏可以不展示有效期；如果必须展示，使用：

```text
No expiration date
```

中文：

```text
长期有效
```

- 不要在前端写死任何日期。
- 如果后端未来返回 `expiresAt = null`，前端应展示为永久有效或不展示有效期。

---

## Survey 字段设计

### 通用触发字段：感兴趣的产品

字段名：

```ts
interestedProduct
```

展示文案：

```text
Which product are you most interested in?
```

选项：

| value | 英文文案 | 中文文案 |
|-------|----------|----------|
| `sheep_counting_camera` | Sheep Counting Camera | AI 羊只计数相机 |
| `wool_diameter_analyzer` | Wool Diameter Analyzer | AI 羊毛直径分析仪 |
| `both` | Both | 两个都感兴趣 |
| `not_sure` | Not sure yet | 还不确定 |

触发规则：

- `interestedProduct = wool_diameter_analyzer`：展示 `woolAnalyzerSurvey`。
- `interestedProduct = sheep_counting_camera`：展示 `sheepCountingSurvey`。
- `interestedProduct = both`：同时展示 `woolAnalyzerSurvey` 和 `sheepCountingSurvey`。
- `interestedProduct = not_sure` 或空值：不展示产品专属问题。

### 羊毛直径分析仪专属问题

分组标题：

英文：

```text
Questions about the Wool Diameter Analyzer
```

中文：

```text
关于羊毛直径分析仪的问题
```

#### Q1：优先关注的关键特性

字段名：

```ts
woolAnalyzerSurvey.prioritizedFeatures
```

题型：多选。

英文问题：

```text
What key features of the Wool Diameter Analyzer do you prioritize?
```

选项：

| value | 英文文案 | 中文文案 |
|-------|----------|----------|
| `testing_accuracy` | Testing Accuracy | 检测准确性 |
| `testing_speed` | Testing Speed | 检测速度 |
| `sample_preparation_efficiency` | Sample Preparation Efficiency | 样品制备效率 |
| `portability` | Portability | 便携性 |
| `price` | Price | 价格 |
| `others` | Others | 其他 |

#### Q2：希望优化或升级的功能

字段名：

```ts
woolAnalyzerSurvey.optimizationSuggestions
```

题型：开放文本。

英文问题：

```text
What functions or features would you like us to optimize or upgrade?
```

规则：

- 非必填。
- 最大 1000 字符。
- 前端 trim。

#### Q3：可接受价格区间

字段名：

```ts
woolAnalyzerSurvey.priceRange
```

题型：自由文本输入。

英文问题：

```text
What price range would make you consider purchasing this device?
```

规则：

- 不提供固定价格选项。
- 用户自由填写，例如 `$1,000-$2,000`、`Under $1,500`、`Depends on accuracy`。
- 非必填。
- 最大 200 字符。

#### Q4：计划使用场景

字段名：

```ts
woolAnalyzerSurvey.intendedUseLocations
```

题型：多选。

英文问题：

```text
Where do you intend to use the Wool Diameter Analyzer?
```

选项：

| value | 英文文案 | 中文文案 |
|-------|----------|----------|
| `shed` | Shed | 羊棚 |
| `race` | Race | 赶羊通道 |
| `laboratory` | Laboratory | 实验室 |
| `office` | Office | 办公室 |
| `research_institution` | Research Institution | 研究机构 |
| `others` | Others | 其他 |

#### Q5：理想单次测试总时长

字段名：

```ts
woolAnalyzerSurvey.idealTestingTime
```

题型：自由文本输入。

英文问题：

```text
What is your ideal total testing time per test run (including sample preparation)?
```

规则：

- 非必填。
- 最大 200 字符。
- 前端 trim。

#### Q6：是否需要桌面专业版

字段名：

```ts
woolAnalyzerSurvey.desktopVersionInterest
```

题型：单选。

英文问题：

```text
Would you be interested in a desktop/professional version of the Wool Diameter Analyzer?
```

说明文案：

```text
The upgraded desktop model delivers laboratory-level testing accuracy, supports full staple fiber testing, featuring premium upgraded performance and specifications.
```

选项：

| value | 英文文案 | 中文文案 |
|-------|----------|----------|
| `yes_desktop_needed` | Yes, I need this desktop version | 是，我需要桌面专业版 |
| `no_portable_enough` | No, the portable version meets my needs | 否，便携版已满足我的需求 |

### 羊只计数相机专属问题

分组标题：

英文：

```text
Questions about the Sheep Counting Camera
```

中文：

```text
关于羊只计数相机的问题
```

#### Q1：优先关注的关键特性

字段名：

```ts
sheepCountingSurvey.prioritizedFeatures
```

题型：多选。

英文问题：

```text
What key features of the Sheep Counting Camera do you prioritize?
```

选项：

| value | 英文文案 | 中文文案 |
|-------|----------|----------|
| `detection_accuracy` | Detection Accuracy | 识别准确性 |
| `portability` | Portability | 便携性 |
| `price` | Price | 价格 |
| `others` | Others | 其他 |

#### Q2：希望优化或升级的功能

字段名：

```ts
sheepCountingSurvey.optimizationSuggestions
```

题型：开放文本。

英文问题：

```text
What functions or features would you like us to optimize or upgrade?
```

规则：

- 非必填。
- 最大 1000 字符。
- 前端 trim。

#### Q3：可接受价格区间

字段名：

```ts
sheepCountingSurvey.priceRange
```

题型：自由文本输入。

英文问题：

```text
What price range would make you consider purchasing this device?
```

规则：

- 不提供固定价格选项。
- 用户自由填写，例如 `$500-$1,000`、`Under $800`、`Depends on accuracy`。
- 非必填。
- 最大 200 字符。

#### Q4：是否需要固定式版本

字段名：

```ts
sheepCountingSurvey.stationaryVersionInterest
```

题型：单选。

英文问题：

```text
Would you be interested in a stationary version of the AI Sheep Counting Camera?
```

说明文案：

```text
This dedicated stationary model comes with a fixed mounting frame, solar power supply and wireless transmission functionality for fixed-scenario deployment.
```

选项：

| value | 英文文案 | 中文文案 |
|-------|----------|----------|
| `yes_stationary_needed` | Yes, I need this stationary version | 是，我需要固定式版本 |
| `no_portable_sufficient` | No, the portable version is sufficient | 否，便携版已足够 |

---

## 表单状态建议

建议在 `PreorderDiscountForm.vue` 中新增独立状态：

```ts
const survey = reactive({
  interestedProduct: '',
  woolAnalyzerSurvey: {
    prioritizedFeatures: [] as string[],
    optimizationSuggestions: '',
    priceRange: '',
    intendedUseLocations: [] as string[],
    idealTestingTime: '',
    desktopVersionInterest: ''
  },
  sheepCountingSurvey: {
    prioritizedFeatures: [] as string[],
    optimizationSuggestions: '',
    priceRange: '',
    stationaryVersionInterest: ''
  }
})
```

第一阶段不要把这些字段混进现有 `form` 必填校验，也不要影响 `validateForm()` 的通过条件。

条件展示状态建议：

```ts
const showWoolAnalyzerSurvey = computed(() =>
  survey.interestedProduct === 'wool_diameter_analyzer' || survey.interestedProduct === 'both'
)

const showSheepCountingSurvey = computed(() =>
  survey.interestedProduct === 'sheep_counting_camera' || survey.interestedProduct === 'both'
)
```

当用户切换 `interestedProduct` 时，第一版建议不自动清空隐藏分组的数据，避免用户误点后丢失已填内容。提交或后续构造 payload 时，只包含当前可见产品分组。

可预留后续映射函数：

```ts
const buildProductFeedbackSurvey = () => {
  const payload: Record<string, unknown> = {
    interestedProduct: survey.interestedProduct || undefined
  }

  if (showWoolAnalyzerSurvey.value) {
    payload.woolAnalyzerSurvey = {
      prioritizedFeatures: survey.woolAnalyzerSurvey.prioritizedFeatures,
      optimizationSuggestions: survey.woolAnalyzerSurvey.optimizationSuggestions.trim() || undefined,
      priceRange: survey.woolAnalyzerSurvey.priceRange.trim() || undefined,
      intendedUseLocations: survey.woolAnalyzerSurvey.intendedUseLocations,
      idealTestingTime: survey.woolAnalyzerSurvey.idealTestingTime.trim() || undefined,
      desktopVersionInterest: survey.woolAnalyzerSurvey.desktopVersionInterest || undefined
    }
  }

  if (showSheepCountingSurvey.value) {
    payload.sheepCountingSurvey = {
      prioritizedFeatures: survey.sheepCountingSurvey.prioritizedFeatures,
      optimizationSuggestions: survey.sheepCountingSurvey.optimizationSuggestions.trim() || undefined,
      priceRange: survey.sheepCountingSurvey.priceRange.trim() || undefined,
      stationaryVersionInterest: survey.sheepCountingSurvey.stationaryVersionInterest || undefined
    }
  }

  return payload.interestedProduct ? payload : undefined
}
```

如果需要过滤空数组和空对象，可在后端接入阶段统一处理。第一阶段以 UI 原型清晰为主。

第一阶段是否启用该函数由实现者决定：

- 如果后端接口未接收该字段，默认不提交。
- 如果只为了调试，可在 `console.debug` 中查看，但上线前不要保留调试输出。

---

## 推荐组件实现

可以在 `PreorderDiscountForm.vue` 内实现局部区块，避免过早抽象。

如果模板过长，可拆为：

```text
components/preorder/PreorderFeedbackSurvey.vue
```

拆分条件：

- Survey 区块模板超过 120 行。
- 选项渲染逻辑影响主表单可读性。
- 后续需要复用到其他活动页。

第一版更推荐直接在 `PreorderDiscountForm.vue` 内实现，便于快速调整和回退。

---

## 数据提交策略

### 第一阶段

默认不提交到后端。

原因：

- 当前领导只需要先看官网 UI。
- 后端和后台尚未补齐字段，不应让接口契约提前漂移。
- 防止后端严格校验时因为未知字段导致提交失败。

### 第二阶段

领导确认后，由 `BACKEND-027` 增加接口字段：

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

官网再把 `buildProductFeedbackSurvey()` 返回值合入提交 payload。

---

## 实施步骤

1. 确认 `E:\nuxt-moxton` 工作区干净。
2. 从当前 `master` 创建开发分支或直接在当前分支试做。
3. 打开 `components/preorder/PreorderDiscountForm.vue`。
4. 在 `pages/preorder-discount.vue` 中调整首屏 Hero 横幅、主标题、副标题和权益清单。
5. 移除或替换首屏固定有效期 `December 31, 2026` 展示。
6. 在 `components/preorder/PreorderDiscountForm.vue` 新增 survey 状态、产品触发字段和两组产品专属问题配置。
7. 在牧场信息区块之后插入产品反馈区块。
8. 实现 `interestedProduct` 单选触发逻辑。
9. 实现羊毛直径分析仪问题组的多选、单选和自由文本输入。
10. 实现羊只计数相机问题组的多选、单选和自由文本输入。
11. 价格区间题使用输入框，不使用固定选项。
12. 补齐 `i18n/locales/en.ts` 和 `i18n/locales/zh.ts` 文案。
13. 确认表单提交不携带未知字段，或提交前明确注释为后续启用。
14. 运行 `pnpm type-check`。
15. 运行 `pnpm dev`，检查 `/preorder-discount?source=home_preorder`。
16. 分别截图：首屏 Hero、未选择产品、选择羊毛分析仪、选择羊只计数相机、选择 Both、移动端。

---

## 验收标准

- [ ] `/preorder-discount?source=home_preorder` 页面正常打开。
- [ ] 顶部横幅显示 `EXCLUSIVE PRE-LAUNCH SURVEY OFFER`。
- [ ] 主标题显示 `Help Us Shape the Next Generation of Livestock Testing Tools`。
- [ ] 副标题使用新的用户反馈和 15% 折扣码文案。
- [ ] 副标题中的 `15%` 有高亮。
- [ ] 权益清单展示新的两条权益。
- [ ] 首屏不再展示 `Valid until December 31, 2026`。
- [ ] 页面不再写死 2026 年底有效期。
- [ ] Survey 区块出现在预约表单内部，位置不突兀。
- [ ] Survey 不以弹窗、遮罩、跳转页形式出现。
- [ ] Survey 全部问题非必填。
- [ ] 用户不填写 Survey 也能正常提交预约。
- [ ] 选择 `Wool Diameter Analyzer` 后只展示羊毛直径分析仪专属问题。
- [ ] 选择 `Sheep Counting Camera` 后只展示羊只计数相机专属问题。
- [ ] 选择 `Both` 后同时展示两组产品专属问题。
- [ ] 选择 `Not sure yet` 后不展示产品专属问题。
- [ ] 两个产品的价格区间题均为自由文本输入。
- [ ] 基础必填字段校验保持不变。
- [ ] 牧场字段校验保持不变。
- [ ] 产品选择弹窗行为保持不变。
- [ ] Survey 选项点击后有明确选中态。
- [ ] 多选题支持选择多个选项并可取消。
- [ ] 移动端选项文字不溢出、不重叠。
- [ ] 开放反馈输入框不影响提交按钮显示。
- [ ] 中英文文案均已补齐。
- [ ] `pnpm type-check` 通过。
- [ ] 页面可截图给领导评审。

---

## 回退方案

由于 `nuxt-moxton` 当前已经做过全量提交，第一阶段建议保持改动集中在少量文件：

- `components/preorder/PreorderDiscountForm.vue`
- `i18n/locales/en.ts`
- `i18n/locales/zh.ts`
- 如需类型预留，才修改 `types/shop.ts`

如果领导不认可：

1. 直接回退上述文件中 Survey 相关代码。
2. 如果独立拆了 `PreorderFeedbackSurvey.vue`，删除该组件文件。
3. 不需要动后端和后台。
4. 不需要数据库回滚。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| Survey 太长导致用户放弃预约 | 按产品条件展示；`Both` 场景使用清晰分组，全部非必填 |
| 用户误以为必须填写 Survey 才能领折扣 | 标题和说明弱化“问卷”感，不展示必填星号 |
| 视觉与当前页面不一致 | 沿用现有表单卡片、按钮、橙色选中态 |
| 后端未接收字段导致提交失败 | 第一阶段默认不提交 Survey 字段 |
| 后续字段名混乱 | 使用 `woolAnalyzerSurvey` 和 `sheepCountingSurvey` 分组命名 |
| 与测试计划概念混淆 | Survey 文案只讲产品需求，测试计划 checkbox 保持独立 |
| 用户填写价格格式不一致 | 价格区间按自由文本保存，后台只展示原文，不做数值统计 |
| 有效期口径回退到年底 | 前端移除固定日期，后端/API 文档明确永久有效或 `expiresAt = null` |

---

## 相关文档

- [预售预约优惠码 API](../../../02-api/preorder-discounts.md)
- [预约页牧场信息字段位置与测试计划勾选调整](./SHOP-FE-020-preorder-ranch-fields-position-adjustment.md)
- [后端保存预约反馈 Survey 字段](../backend/BACKEND-027-preorder-product-feedback-survey-fields.md)
- [后台展示预约反馈 Survey](../admin-frontend/ADMIN-FE-019-preorder-product-feedback-survey-display.md)

