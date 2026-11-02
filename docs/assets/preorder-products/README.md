# 预售产品后台配置资料包

**来源:** `E:\discount-code-form-prototype`
**整理时间:** 2026-06-27
**用途:** 后台管理系统录入两款真实预售产品时使用。

---

## 使用说明

当前后端商品列表均为测试商品，不应作为官网预约页上线数据。建议先执行测试商品清理任务，再在后台管理系统中重新录入以下两款真实预售产品，并把购买模式设置为 `PREORDER`。

本目录中的图片来自预约页原型，仅作为后台录入商品主图和预约页展示图的候选素材。正式上线前如有更高清、更规范的产品图，可以替换为正式素材。

---

## 产品 1：AI Sheep Counting Camera

后台建议字段：

- 商品名称：`AI Sheep Counting Camera`
- 购买模式：`PREORDER`
- 商品描述：`Real-time sheep counting for smarter pasture management`
- 特性标签：
  - `Fast Recognition`
  - `Portable`
  - `Real-time Monitoring`
- 商品主图建议：`sheep-counting-camera-main.png`
- 辅助展示图：`sheep-counting-display-panel.png`

图片文件：

- `sheep-counting-camera-main.png`
  - 原型来源：`sheep-counting-camera-latest.png`
  - 尺寸：718 x 1254
  - 用途：商品主图、预约页产品展示图、邮件产品图候选
- `sheep-counting-display-panel.png`
  - 原型来源：`sheep-counting-display-panel-cropped.png`
  - 尺寸：274 x 128
  - 用途：预约页产品展示区可选辅助图。后台商品主图通常不需要上传这张。

原型 alt 文案：

```text
Moxton AI sheep counting camera mounted on a portable stand
Black sheep counting display panel with red LED digits 1086
```

---

## 产品 2：AI Wool Diameter Analyzer

后台建议字段：

- 商品名称：`AI Wool Diameter Analyzer`
- 购买模式：`PREORDER`
- 商品描述：`Instant wool micron analysis in the field`
- 特性标签：
  - `Instant Result`
  - `Accurate Data`
  - `Handheld Device`
- 商品主图建议：`wool-diameter-analyzer-main.png`

图片文件：

- `wool-diameter-analyzer-main.png`
  - 原型来源：`wool-analyzer-cropped.png`
  - 尺寸：768 x 1046
  - 用途：商品主图、预约页产品展示图、邮件产品图候选

原型 alt 文案：

```text
Black and orange handheld Moxton wool diameter analyzer
```

---

## 后台录入注意事项

- 两款产品都必须设置 `purchaseMode = PREORDER`。
- 不要设置成 `ONLINE`，否则官网可能出现购买能力。
- 商品主图建议优先使用本目录里的主图文件。
- 如果后台产品表单要求价格，预售产品价格应按现有后台规则处理；购买模式必须以 `PREORDER` 为准，不再通过价格判断是否购买。
- `metadata.preorder.heroImage` 可不填，官网预约页本阶段优先使用商品主图。
- `metadata.preorder.description` 可填同商品描述，也可不填。
- `metadata.preorder.videoUrl` 本阶段不使用。
