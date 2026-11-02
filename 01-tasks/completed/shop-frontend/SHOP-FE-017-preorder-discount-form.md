# Tech-Spec: 固定预售预约表单页与优惠码提交接入

**任务ID:** SHOP-FE-017
**创建时间:** 2026-06-17
**最后更新:** 2026-06-27
**状态:** 开发完成
**角色:** 独立站前端工程师
**项目:** nuxt-moxton
**优先级:** P1
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia
**QA_LEVEL:** full

---

## 概述

### 问题陈述

官网需要提供一个不要求登录的预售预约页面。用户从首页点击“立即预约”进入固定预约页，填写表单后领取所选预售产品的优惠码。

当前最新业务口径已经调整：

- 预售商品在商品列表和详情页不再跳转预约页，而是显示灰色禁用按钮“即将上线”。
- 预约页只有一个固定页面 `/preorder-discount`，不是 `/preorder-discount?productId=...` 这种单产品页面。
- 页面主体 UI 需要尽量完整还原 `E:\discount-code-form-prototype` 原型。
- 桌面端和移动端都需要对齐原型，不能只完成桌面版。
- 原型中的产品展示区 `Products Eligible for This Offer` 保留为展示区，不做勾选交互。
- 产品选择放在点击 `Send My Discount Code` 后出现的弹窗中完成。
- 本阶段不保留、不展示、不依赖视频字段。

### 解决方案

新增 `/preorder-discount` 固定页面：

1. 页面加载时拉取官网可展示的 `PREORDER` 产品列表。
2. 页面按原型展示 hero、预约表单、产品展示区、`How It Works`。
3. 产品展示区使用后台商品数据动态渲染预售产品，重点使用商品主图、商品名称和简短说明。
4. 用户填写固定表单字段后点击 `Send My Discount Code`。
5. 前端先校验表单字段，通过后打开“选择预约产品”弹窗。
6. 弹窗展示可预约产品的缩略图和产品名称，至少选择 1 个产品，最多选择当前可预约产品数量。本期预计 2 个产品。
7. 用户确认后提交 `POST /preorder-discounts/claim`，请求体包含 `productIds`。
8. 后端按产品拆分生成优惠码并发送邮件。前端成功页不展示优惠码，只提示用户检查邮箱。

### 范围

**包含:**

- 新增 `/preorder-discount` 页面。
- 从 React/Vite 原型迁移视觉和交互到 Nuxt。
- 保留原型固定表单字段。
- 读取 URL 中的 `source`，例如 `home_preorder`。
- 拉取 `purchaseMode = PREORDER` 的商品列表。
- 在 `Products Eligible for This Offer` 区域展示预售产品，不在该区域做勾选。
- 点击 `Send My Discount Code` 后打开产品选择弹窗。
- 弹窗内产品项只展示缩略图、产品名称和选择状态。
- 至少选择 1 个产品才允许确认提交。
- 接入预约提交 API。
- 处理成功、重复、部分重复、邮件失败、网络失败、无预售产品等状态。
- 按原型完成移动端适配，重点保证 hero、表单、产品展示卡和产品视觉区在手机端不溢出、不重叠。

**不包含:**

- 后端接口实现。
- 后台预约名单页面。
- 结账时使用优惠码抵扣。
- 产品宣传视频展示。
- 独立活动 CMS 或活动配置后台。

---

## 开发上下文

### 原型目录

- `E:\discount-code-form-prototype\src\App.jsx`
- `E:\discount-code-form-prototype\src\index.css`

原型关键字段和文案：

- 表单标题：`Request Your Discount Code`
- 提交按钮：`Send My Discount Code`
- 产品展示区标题：`Products Eligible for This Offer`
- 流程区标题：`How It Works`
- 必填字段：`firstName`、`lastName`、`phone`、`email`
- 可选字段：`ranchName`、`address`

原型移动端关键样式：

- `hero-section` 在小屏下高度增加，避免首屏文字和背景图互相挤压。
- `hero-light-wash` 在小屏下从横向遮罩调整为纵向遮罩。
- `product-visual` 在 `max-width: 768px` 时固定高度约 `520px`。
- 数羊摄像头移动端需要主机图和显示屏辅图组合定位，不能简单把两张图顺序堆叠。
- 移动端输入框字号不应低于 `16px`，避免 iOS 聚焦放大。
- 极窄屏下标题和段落必须允许换行，不能横向溢出。

### 官网建议新增或修改文件

- 新增 `pages/preorder-discount.vue`
- 新增 `composables/api/preorder-discounts.ts`
- 新增或复用商品 API composable，用于拉取 `PREORDER` 产品
- 可能新增 `components/preorder/PreorderDiscountForm.vue`
- 可能新增 `components/preorder/PreorderProductShowcase.vue`
- 可能新增 `components/preorder/PreorderProductSelectModal.vue`
- 修改首页入口，把原“联系我们”改为“立即预约”，跳转 `/preorder-discount?source=home_preorder`
- 修改 `types/shop.ts`
- 修改 `i18n/locales/zh.ts`
- 修改 `i18n/locales/en.ts`

### 依赖项

- 前置任务：`BACKEND-018`
- 前置任务：`BACKEND-019`
- 前置任务：`BACKEND-023`
- 商品购买模式已由 `BACKEND-017` / `ADMIN-FE-010` / `SHOP-FE-016` 建立基础。
- `BACKEND-020` / `ADMIN-FE-013` 已完成，但本任务只使用商品主图和可选描述，不使用视频。
- API 接口文档来源：
  - 预约提交接口以 `../../../02-api/preorder-discounts.md` 为准。
  - 商品列表接口以 `../../../02-api/products.md` 为准。
- 本任务文档中的请求/响应示例只用于说明前端处理意图；正式接入时必须以 `BACKEND-023` 更新后的 `02-api` 文档为最终依据。
- 注意：当前 `products.md` 已明确管理端 `GET /products/admin/all` 支持 `purchaseMode` 筛选；官网公开 `GET /products` 如未在 API 文档中明确支持 `purchaseMode`，官网前端不要假设该筛选一定可用，应按本文“获取可预约产品”中的降级方案先拉取上架商品后本地过滤。

---

## 页面信息架构

### 首屏 Hero

按原型迁移：

- 背景图使用原型视觉资产或迁移到官网静态资源目录。
- 标签：`Exclusive pre-launch offer`
- 主标题突出 `Save 15% On Official Launch`
- 说明文案说明填写信息后通过邮件收到优惠码。
- 三个卖点保留：
  - 邮件接收 15% 优惠码。
  - 可用于指定 Moxton 产品。
  - 有效期到当年 12 月 31 日。

注意：

- 优惠码有效期由后端返回或前端按当年展示，最终以后端记录为准。
- 不要在页面中承诺具体可结账使用时间，只说明正式上线后可用。

### 表单区

按原型迁移字段：

必填：

- `firstName`
- `lastName`
- `phone`
- `email`

可选：

- `ranchName`
- `address`

隐藏上下文：

- `source`

不包含：

- `productId`
- `videoUrl`
- 产品说明字段
- 产品图片字段

### 产品展示区

标题沿用：

```text
Products Eligible for This Offer
```

展示逻辑：

- 页面加载时拉取所有可预约产品。
- 只展示 `purchaseMode = PREORDER` 且上架的产品。
- 本阶段预计展示两个产品：
  - 数羊摄像头
  - 羊毛测量仪
- 不写死产品 ID，不写死产品数量。
- 如果后台后续只配置 1 个预售产品，则展示 1 个。
- 如果后台配置超过 2 个，页面可以正常渲染，但弹窗最大选择数量建议跟随后端规则。

每个展示卡推荐字段：

- 产品名称：`product.name`
- 产品说明：优先 `product.metadata.preorder.description`，否则 `product.description`
- 产品主图：优先 `product.images[0]`
- 若后台已有 `metadata.preorder.heroImage`，可以作为兜底优先级，但当前用户口径是截图区域可以直接用商品列表主图，因此不要强依赖该字段。
- 特性标签：可从 `product.tags` 或 `product.specifications` 取前 3 个；如果没有，使用页面内固定兜底文案。

产品展示区不得承担选择职责：

- 不显示 checkbox。
- 不显示“已选”状态。
- 不在卡片点击时改变选择。
- 不因为用户选择而切换页面宣传图或页面说明。

### 产品选择弹窗

触发时机：

- 用户点击 `Send My Discount Code`。
- 前端先完成表单校验。
- 表单校验通过后再打开弹窗。

弹窗内容：

- 标题：建议 `Select products`
- 说明：建议 `Choose at least one product to receive your discount code.`
- 产品列表：每项只展示缩略图、产品名称、选择状态。
- 缩略图来源：`product.images[0]`，没有则使用占位图。
- 不展示长说明、不展示视频、不展示复杂营销内容。

选择规则：

- 至少选择 1 个产品。
- 本期最多预计选择 2 个产品，因为只有两款预售产品。
- 如果产品列表只有 1 个，则只允许选择 1 个。
- 如果后端明确限制 `productIds` 最大长度为 2，前端也应限制最多 2 个。
- 未选择产品时确认按钮禁用，并显示清晰提示。

提交按钮状态：

- 弹窗确认提交时显示 loading。
- 提交中禁用关闭和重复提交，或关闭时明确不继续发送。
- 提交失败后允许用户重试，不清空表单。

---

## API 接入

接口来源：

- 预约提交：`../../../02-api/preorder-discounts.md`
- 商品列表：`../../../02-api/products.md`

接入规则：

- 以前置任务 `BACKEND-023` 更新后的 API 文档为准。
- 本节示例仅用于说明页面需要处理的业务状态，不作为最终字段契约。
- 若任务文档示例和 `02-api` 文档不一致，按 `02-api` 文档调整前端类型、请求参数和响应处理。
- 当前 `../../../02-api/products.md` 明确写到 `purchaseMode` 筛选的是管理端 `GET /products/admin/all`；如果后端没有继续补充公开 `GET /products` 的 `purchaseMode` 查询参数，官网实现应使用公开 `GET /products` 获取上架商品后在前端过滤 `purchaseMode === 'PREORDER'`。

### 获取可预约产品

优先复用现有商品列表接口。

推荐查询方式：

```http
GET /products?purchaseMode=PREORDER&status=1
```

如果后端现有列表接口暂不支持 `purchaseMode` 筛选：

- 前端可先拉取上架产品后本地过滤 `purchaseMode === 'PREORDER'`。
- 但正式实现建议后端支持筛选，避免商品量增加后不必要的数据传输。

前端需要兼容：

- `purchaseMode` 缺失：不要当成预售产品。
- `metadata` 为对象。
- `metadata` 为 JSON 字符串。
- `images` 为数组。
- `images` 为逗号分隔字符串。

### 提交预约

```http
POST /preorder-discounts/claim
```

请求体：

```json
{
  "firstName": "Morgan",
  "lastName": "Carter",
  "phone": "+61 400 000 000",
  "email": "morgan@example.com",
  "ranchName": "Carter Ranch",
  "address": "1200 Valley Road",
  "productIds": ["product_a_id", "product_b_id"],
  "source": "home_preorder"
}
```

成功响应建议：

```json
{
  "success": true,
  "data": {
    "status": "COMPLETED",
    "message": "Your preorder discount request has been received.",
    "items": [
      {
        "productId": "product_a_id",
        "productName": "AI Sheep Counting Camera",
        "status": "SENT",
        "emailStatus": "SENT"
      }
    ]
  }
}
```

前端不依赖响应里的优惠码展示。优惠码只通过邮件发送。

### 重复和部分成功

同一邮箱重复预约同一产品时，后端可能返回：

- 整体失败：所有选择产品都已领取过。
- 部分成功：A 已领取过，B 首次领取成功。

前端建议支持 `items` 级别状态：

```ts
type PreorderClaimItemStatus = 'SENT' | 'PENDING' | 'FAILED' | 'DUPLICATE'
```

展示策略：

- 全部成功或邮件发送中：展示成功页，提示检查邮箱。
- 部分重复但有新邮件发送：展示成功页，并提示部分产品此前已经领取过。
- 全部重复：展示表单错误提示，说明该邮箱已领取过所选产品优惠码。
- 邮件失败但线索保存成功：展示“预约已提交，但邮件暂时发送失败，我们会稍后处理或请联系支持”。

---

## 校验规则

### 表单校验

- `firstName`：必填，trim 后不能为空。
- `lastName`：必填，trim 后不能为空。
- `phone`：必填，只允许数字、空格、括号、加号、短横线；去除非数字后长度建议 7 到 20。
- `email`：必填，基础邮箱格式校验。
- `ranchName`：可选，trim。
- `address`：可选，trim。

### 产品选择校验

- `preorderProducts.length === 0` 时，不允许提交，页面显示“暂无可预约产品”。
- 弹窗内 `selectedProductIds.length < 1` 时，不允许确认。
- 若后端限制最多 2 个，则 `selectedProductIds.length > 2` 时阻止继续选择，并提示最多选择 2 个。
- 提交前再次确认所有选中 ID 都来自当前 `PREORDER` 产品列表。

---

## 实施步骤

1. 迁移原型图片资源到 Nuxt 项目合适目录。
2. 新增 `/preorder-discount` 页面骨架。
3. 迁移 hero、表单、产品展示区、`How It Works` 的布局和样式。
4. 新增获取预售产品逻辑，过滤 `purchaseMode = PREORDER`。
5. 实现商品图片、名称、说明、标签的归一化 helper。
6. 产品展示区动态渲染预售商品，但不提供选择交互。
7. 实现表单状态、校验和错误提示。
8. 点击 `Send My Discount Code` 时先校验表单，通过后打开产品选择弹窗。
9. 实现产品选择弹窗，至少选择 1 个产品。
10. 新增 `preorder-discounts` API composable。
11. 弹窗确认后提交 `productIds`、表单字段和 `source`。
12. 处理成功、重复、部分重复、邮件失败和网络失败状态。
13. 修改首页入口：把“联系我们”改为“立即预约”，跳转 `/preorder-discount?source=home_preorder`。
14. 补齐中英文文案。
15. 桌面端、平板、移动端自测 UI 不溢出、不重叠。
16. 用真实后端或 mock 数据验证 0 个、1 个、2 个预售产品场景。
17. 使用移动端 viewport 对照原型检查 hero、表单、产品卡、产品视觉区和弹窗。

---

## 验收标准

- [ ] `/preorder-discount` 页面可访问。
- [ ] 页面整体视觉接近原型，包括 hero、表单、产品展示区和流程区。
- [ ] 移动端视觉和布局对齐原型，不只是桌面端接近原型。
- [ ] 首页“立即预约”可以进入 `/preorder-discount?source=home_preorder`。
- [ ] 商品列表和商品详情里的 `PREORDER` 产品仍显示灰色“即将上线”，不跳转预约页。
- [ ] 页面加载后展示后台配置的 `PREORDER` 产品。
- [ ] 产品展示区使用商品主图作为主要产品图。
- [ ] 移动端产品视觉区高度稳定，图片不挤压、不裁断关键产品主体。
- [ ] 数羊摄像头移动端可正确展示主机图和显示屏辅图组合。
- [ ] 产品展示区不显示 checkbox，不承担选择职责。
- [ ] 表单必填校验正确。
- [ ] 邮箱和电话格式校验正确。
- [ ] 表单校验失败时不会打开产品选择弹窗。
- [ ] 表单校验通过后点击 `Send My Discount Code` 会打开产品选择弹窗。
- [ ] 弹窗内只展示产品缩略图、产品名称和选择状态。
- [ ] 未选择任何产品时不能提交。
- [ ] 至少选择 1 个产品后可以提交。
- [ ] 提交请求包含 `productIds` 和 `source`。
- [ ] 成功后不在页面展示具体优惠码。
- [ ] 用户不登录也能提交预约。
- [ ] 邮件失败但保存成功时显示可理解提示。
- [ ] 无预售产品时页面给出合理空状态，并禁用提交路径。
- [ ] 本阶段页面不展示、不读取、不依赖 `videoUrl`。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 原型是 React | 只迁移视觉、交互和字段，不引入 React |
| 后端仍是单 `productId` 接口 | 必须先执行 BACKEND-018，把提交接口改为 `productIds` |
| 商品接口暂不支持 `purchaseMode` 筛选 | 前端先本地过滤，后续补后端筛选 |
| 产品展示图尺寸不一致 | 使用固定比例容器和 `object-fit: contain` |
| 只还原桌面端导致手机端变形 | 必须按原型移动端断点单独验收 |
| 邮件发送部分失败 | 前端按 `items` 展示总体状态，不展示优惠码 |
| 旧文档曾要求视频 | 本阶段明确不使用视频，已有 `videoUrl` 字段可保留但不参与官网预约页 |

---

**相关文档:**

- [开发计划](../../docs/plans/2026-06-17-preorder-discount-code-closed-loop-plan.md)
- [项目状态](../../04-projects/nuxt-moxton.md)
