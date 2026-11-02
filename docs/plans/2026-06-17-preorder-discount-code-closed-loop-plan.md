# 预售预约领取产品优惠代码闭环开发计划

**创建时间:** 2026-06-17
**最后更新:** 2026-06-27
**状态:** 开发计划已调整，等待继续执行

---

## 1. 当前最新业务口径

官网后续会在后台新增两款预售产品，暂称：

- 数羊摄像头
- 羊毛测量仪

这两款产品会在后台管理系统中设置为 `PREORDER` 预售模式。预售产品可以在官网商品列表和详情页展示，但暂时不能线上购买。

当前方案已经从“商品卡片点击立即预约进入单产品预约页”调整为“固定预约页统一收集信息”：

1. 商品列表中的预售产品按钮显示灰色禁用文案“即将上线”。
2. 商品详情页中的预售产品按钮也显示灰色禁用文案“即将上线”。
3. 首页原“联系我们”入口改为“立即预约”。
4. 首页“立即预约”跳转固定页面 `/preorder-discount?source=home_preorder`。
5. `/preorder-discount` 页面完整还原 `E:\discount-code-form-prototype` 的预约表单 UI。
6. 页面中的 `Products Eligible for This Offer` 产品展示区读取后台配置为 `PREORDER` 的商品。
7. 产品展示区只做展示，不做勾选。
8. 用户填写表单后点击 `Send My Discount Code`。
9. 前端先校验表单字段，校验通过后弹出产品选择弹窗。
10. 弹窗中展示预售产品缩略图和产品名称。
11. 用户至少选择 1 个产品，当前预计最多 2 个产品。
12. 前端提交 `productIds` 给后端。
13. 后端按产品拆分生成优惠码：一个产品一条预约记录、一个产品一个优惠码、一封产品对应邮件。
14. 优惠码只通过邮件发送，页面成功态不展示优惠码。

本阶段不做：

- 结账时使用优惠码抵扣。
- 视频展示。
- 活动 CMS。
- 独立优惠码规则后台。
- 强制用户登录。

---

## 2. 当前项目状态

### 2.1 `moxton-lotapi`

路径：

```text
E:\moxton-lotapi
```

已存在能力：

- `Product.purchaseMode` 已存在。
- `Product.metadata` 已存在。
- `PreorderDiscountLead` 模型已存在。
- `POST /preorder-discounts/claim` 已存在，但当前代码仍是单 `productId`。
- `EmailService` 已接入 Resend。
- 后台预约列表、详情、重发接口路由已存在雏形。
- 商品接口已支持 `metadata` 解析和保存。
- 购物车和订单已有对非 `ONLINE` 商品的服务端拦截基础。

主要缺口：

- 预约提交接口需要从单 `productId` 改为 `productIds`。
- 多产品提交后需要按产品拆分 lead/code/email。
- 建议增加 `submissionId`，把同一次表单提交下的多条 lead 关联起来。
- 邮件模板需要最终确认视觉和文案。
- 后台接口字段需要按多产品提交后的 lead 粒度再验一遍。

### 2.2 `moxton-lotadmin`

路径：

```text
E:\moxton-lotadmin
```

已存在能力：

- 产品表单已支持 `purchaseMode`。
- 产品表单已支持 `metadata.preorder`。
- 产品表单中当前仍保留 `videoUrl` 字段。

当前口径：

- `videoUrl` 字段可以保留，不需要返工删除。
- 本阶段官网预约页不使用视频字段。

主要缺口：

- 预约优惠码名单页面未看到完整实现。
- 预约详情页面未看到完整实现。
- 预约邮件重发操作未看到完整实现。

### 2.3 `nuxt-moxton`

路径：

```text
E:\nuxt-moxton
```

已完成或已调整方向：

- `nuxt-moxton` 最近改动主要是静态文案，功能没有变化。
- 商品购买模式展示任务 `SHOP-FE-016` 已完成，但业务口径已调整为预售商品显示“即将上线”，不从商品入口跳预约页。

主要缺口：

- 需要新增 `/preorder-discount` 固定预约页面。
- 需要把 `E:\discount-code-form-prototype` 迁移成 Nuxt 页面。
- 需要接入后台预售商品列表。
- 需要新增提交前产品选择弹窗。
- 需要接入 `POST /preorder-discounts/claim`。
- 首页“联系我们”需要改成“立即预约”并跳预约页。

---

## 3. 原型字段确认

原型路径：

```text
E:\discount-code-form-prototype
```

关键文件：

```text
E:\discount-code-form-prototype\src\App.jsx
E:\discount-code-form-prototype\src\index.css
```

预约表单字段以原型为准。

必填字段：

- `firstName`
- `lastName`
- `phone`
- `email`

可选字段：

- `ranchName`
- `address`

上下文字段：

- `source`
- `productIds`

明确不属于预约表单字段：

- `productId`
- `videoUrl`
- 产品宣传图字段
- 产品宣传说明字段
- 产品宣传视频字段

页面固定模块：

- Hero
- `Request Your Discount Code` 表单区
- `Products Eligible for This Offer` 产品展示区
- `How It Works`
- 成功态

产品展示区当前要求：

- 使用后台 `PREORDER` 商品列表动态渲染。
- 重点使用商品列表主图，也就是 `product.images[0]`。
- 可以展示商品名称、简短描述、最多 3 个特性标签。
- 不做勾选。
- 不因为选择产品改变页面主视觉。

产品选择弹窗当前要求：

- 点击 `Send My Discount Code` 后出现。
- 出现前必须先通过表单校验。
- 弹窗内展示产品缩略图和产品名称。
- 至少选择一个产品。
- 当前预计可选择一款或两款产品。

---

## 4. 数据和接口设计

### 4.1 产品购买模式

商品购买模式：

```ts
type PurchaseMode = 'ONLINE' | 'INQUIRY_ONLY' | 'PREORDER'
```

含义：

- `ONLINE`：线上购买。
- `INQUIRY_ONLY`：线下咨询。
- `PREORDER`：预售展示，当前不可购买。

官网展示规则：

- `ONLINE`：显示价格、数量、加入购物车或购买按钮。
- `INQUIRY_ONLY`：显示咨询入口。
- `PREORDER`：显示灰色禁用“即将上线”。

首页预约入口：

```text
/preorder-discount?source=home_preorder
```

### 4.2 预约提交接口

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

校验规则：

- `firstName` 必填。
- `lastName` 必填。
- `phone` 必填。
- `email` 必填且格式正确。
- `productIds` 必须是数组。
- `productIds` 至少 1 个。
- 本阶段 `productIds` 最多 2 个。
- `productIds` 中不能有重复 ID。
- 每个产品必须存在。
- 每个产品必须未删除、上架、`purchaseMode = PREORDER`。

处理规则：

- 以 `normalizedEmail + productId` 去重。
- 同一邮箱同一产品只能领取一次。
- 同一邮箱不同产品可以分别领取。
- 一次提交两个产品时创建两条预约记录。
- 每条预约记录有独立优惠码。
- 每条预约记录有独立邮件状态。

推荐响应：

```json
{
  "success": true,
  "data": {
    "status": "SENT",
    "message": "Your preorder discount request has been received.",
    "submissionId": "pre_abc123",
    "items": [
      {
        "productId": "product_a_id",
        "productName": "AI Sheep Counting Camera",
        "leadId": "lead_a_id",
        "status": "SENT",
        "duplicate": false,
        "emailStatus": "SENT"
      }
    ]
  }
}
```

### 4.3 预约记录模型

保留当前 `PreorderDiscountLead` 一产品一行的设计。

建议增加：

```prisma
submissionId String?
@@index([submissionId])
```

原因：

- 用户一次提交可能选两个产品。
- 两条 lead 需要能关联为同一次表单提交。
- 后台排查和后续数据分析更清晰。

继续保留：

```prisma
@@unique([normalizedEmail, productId])
```

### 4.4 邮件发送

邮件服务：

- 使用 Resend。
- 模板放代码中维护。
- 不依赖 Resend 后台模板。

发送规则：

- 一个产品一封邮件。
- 两个产品两封邮件。
- 每封邮件只包含对应产品的优惠码。
- 邮件中可以放产品图片。
- 产品图片必须是公网 `https://` URL。
- 当前优先使用商品主图 `product.images[0]`。
- 如果没有公网商品主图，可以跳过图片模块。
- 邮件不放视频。

邮件内容：

- 用户称呼。
- 预约产品名称。
- 产品图片，如果可用。
- 优惠码。
- 折扣比例。
- 有效期。
- 支持邮箱。

优惠码有效期：

- 有效期可以配置，不再按提交年份自动推导。
- 本次上线配置为 2026 年 12 月 31 日过期。
- 后端建议通过环境变量或配置项读取，例如 `PREORDER_DISCOUNT_EXPIRES_AT=2026-12-31T23:59:59.999+11:00`。
- 邮件中的有效期文案必须由后端记录的 `expiresAt` 动态格式化，不写死。

邮件模板：

- 视觉模板来源：`E:\邮件模版\moxton-discount-email.html`。
- logo 来源：`E:\邮件模版\moxton-logo.png`，实际发信时必须替换为公网可访问的 `https://` logo URL。
- 模板底部产品区域必须从两个示例产品改成单个动态产品。
- 一个产品对应一个优惠码，一封邮件只展示一个 `productName`。

### 4.5 后台管理接口

后台接口：

```http
GET /preorder-discounts/admin/leads
GET /preorder-discounts/admin/leads/:id
POST /preorder-discounts/admin/leads/:id/resend
```

列表筛选：

- `pageNum`
- `pageSize`
- `keyword`
- `productId`
- `emailStatus`
- `source`
- `submissionId`，可选

后台页面按 lead 粒度展示。

如果用户一次选择两个产品，后台会看到两条记录；如果增加了 `submissionId`，可以看出两条记录来自同一次提交。

---

## 5. 三个项目要做的事情

### 5.1 后端 `moxton-lotapi`

#### BACKEND-018：预约提交接口升级

目标：

- 把 `POST /preorder-discounts/claim` 从单 `productId` 改为 `productIds`。

具体任务：

1. Prisma 增加可选 `submissionId`。
2. controller 请求体新增 `productIds`。
3. 删除或降级旧 `productId` 逻辑。
4. 新增 `productIds` 规范化和校验。
5. 批量查询预售产品。
6. 校验所有产品都是 `PREORDER`。
7. model 新增 `claimMany` 或等价逻辑。
8. 每个产品分别创建 lead/code。
9. 保留重复产品的 existing lead 摘要。
10. 返回逐产品 `items`。
11. 全部重复时返回明确错误。

#### BACKEND-019：邮件发送和后台接口

目标：

- 对 `BACKEND-018` 创建出的每条 lead 逐条发送邮件。
- 提供后台查看和重发能力。

具体任务：

1. 确认 Resend 配置。
2. 完善代码中的邮件模板。
3. 产品图片使用公网 `https://` 校验。
4. claim 后对非重复 lead 逐条调用 `sendDiscountEmail`。
5. 单封邮件失败不影响其他产品。
6. 汇总逐产品邮件状态。
7. 后台列表接口字段对齐。
8. 后台详情接口字段对齐。
9. 重发接口使用原 code，不生成新 code。

### 5.2 管理后台 `moxton-lotadmin`

#### ADMIN-FE-011：预约优惠码名单与详情页

目标：

- 后台运营可以查看预约用户、产品、优惠码和邮件状态。

具体任务：

1. 新增 `src/service/api/preorder-discount.ts`。
2. 新增预约优惠码列表页。
3. 新增详情抽屉或弹窗。
4. 支持 keyword 筛选。
5. 支持产品筛选。
6. 支持邮件状态筛选。
7. 支持来源筛选。
8. 列表展示姓名、邮箱、电话、牧场名、预约产品、来源、邮件状态、提交时间。
9. 详情展示完整表单信息、产品、优惠码、过期时间、邮件状态、失败原因。
10. 如后端增加 `submissionId`，详情或列表中可展示该字段。

#### ADMIN-FE-012：邮件重发操作

目标：

- 后台可以对单条预约记录重发邮件。

具体任务：

1. API service 增加重发接口。
2. 列表操作列增加“重发邮件”。
3. 详情中增加“重发邮件”。
4. 操作前二次确认。
5. 重发中按钮 loading。
6. 成功后刷新当前记录。
7. 失败后展示错误。

#### ADMIN-FE-013：产品预售内容配置

状态：

- 已完成。

当前注意：

- 已有 `videoUrl` 可以保留。
- 官网当前不使用视频。
- 预售产品主图仍以商品图 `images[0]` 为主要来源。

### 5.3 官网 `nuxt-moxton`

#### SHOP-FE-016：购买模式展示

状态：

- 已完成，但业务口径已调整。

当前要求：

1. `ONLINE` 继续支持线上购买。
2. `INQUIRY_ONLY` 继续支持咨询。
3. `PREORDER` 显示灰色禁用“即将上线”。
4. 商品卡片和详情页不跳预约页。
5. 登录入口继续隐藏，不删除登录系统。

#### SHOP-FE-017：固定预约页

目标：

- 用户可以从首页进入预约页，填写表单，选择产品，提交后收到邮件。

具体任务：

1. 新增 `/preorder-discount` 页面。
2. 迁移原型 UI。
3. 拉取 `PREORDER` 商品。
4. 产品展示区使用商品主图展示预售产品。
5. 表单字段按原型实现。
6. 点击 `Send My Discount Code` 后先校验表单。
7. 校验通过后打开产品选择弹窗。
8. 弹窗内至少选择一个产品。
9. 提交 `productIds`。
10. 成功后展示成功态，不展示优惠码。
11. 首页“联系我们”改为“立即预约”。

---

## 6. 推荐执行顺序

当前用户确认：

- 任务 1、2、3 已执行完成。
- `BACKEND-020` 已完成。
- `ADMIN-FE-013` 已完成。
- 邮件服务已经可以发，但最终邮件模板还需要完善。
- 后续 3、4、5、6、7 还未执行开发。

基于当前最新方案，推荐从这里继续：

### 第 1 步：BACKEND-021

清理后端测试商品。

原因：

- 用户已确认当前后端商品列表全是测试商品，不是真实产品。
- 后续官网商店、预约页产品展示、预约弹窗、邮件产品图片都会依赖真实商品数据。
- 必须先清理测试商品，避免后续联调展示错误产品。

交付标准：

- 清理前输出待删除商品清单。
- 当前测试商品被软删除。
- 不做物理删除。
- 官网商品列表不再返回测试商品。
- 后台普通商品列表不再展示测试商品。

### 第 2 步：ADMIN-FE-015

修正后台产品表单的预售模式录入体验。

原因：

- 当前新增商品表单仍显示“预售预约页内容”和“产品宣传视频”，已经不符合固定预约页方案。
- 当前库存数量仍是必填，但预售产品不参与线上购买，库存不应阻塞录入。
- 这一步应在业务方录入真实预售产品之前完成，避免录入时被错误字段干扰。

交付标准：

- `PREORDER` 模式不显示“预售预约页内容”区块。
- `PREORDER` 模式不显示“产品宣传视频”输入。
- `PREORDER` 商品不需要填写库存。
- `PREORDER` 商品提交时库存默认为 `0`。
- `ONLINE` 商品库存校验仍正常。
### 第 3 步：ADMIN-DATA-001

由业务方在后台录入两款真实预售产品。

原因：

- 商品数据是后续官网展示和预约联调的基础。
- 录入后可以马上验证商店预售产品展示是否符合预期。
- 固定预约页也需要读取这两款 `PREORDER` 产品。

交付标准：

- 后台录入 `AI Sheep Counting Camera`。
- 后台录入 `AI Wool Diameter Analyzer`。
- 两款商品购买模式都是 `PREORDER`。
- 两款商品都有商品主图。
- 两款商品都有描述。
- 官网商品接口能返回这两款预售商品。

资料位置：

- `docs/assets/preorder-products/README.md`
- `docs/assets/preorder-products/preorder-products.json`

### 第 4 步：SHOP-FE-018

修正官网商店和商品详情页的预售展示。

原因：

- 当前 `nuxt-moxton` 代码里商品卡片和商品详情页仍有旧的 `Reserve Now / 立即预约` 跳转逻辑。
- 当前业务口径要求商店和详情页只显示灰色禁用 `Coming Soon / 即将上线`。
- 录入真实预售产品后，可以直接检查商品卡片和详情页的真实图片、文案和移动端展示。

交付标准：

- 商品卡片 `PREORDER` 产品显示 `Coming Soon / 即将上线`。
- 商品卡片预售按钮灰色禁用，不跳转。
- 商品详情桌面端预售 CTA 灰色禁用，不跳转。
- 商品详情移动端预售 CTA 灰色禁用，不跳转。
- 预售产品主图在商品卡片中不裁掉关键设备主体。

### 第 5 步：BACKEND-022 + ADMIN-FE-014

优化后台商品列表的预售管理体验。

原因：

- 这一步不阻塞录入真实预售产品，但建议尽早补齐，方便后续管理和排查。
- 后台可以按购买模式筛出 `PREORDER` 商品。
- 商品列表中预售产品的价格和库存不再呈现成可购买语义。

交付标准：

- `/products/admin/all` 支持 `purchaseMode` 筛选。
- 后台商品列表搜索区可以筛选“线上购买 / 仅咨询 / 预售预约”。
- 商品列表列名使用“购买模式”，不再叫“商品类型”。
- `PREORDER` 商品价格列显示 `暂不售卖` 或 `-`。
- `PREORDER` 商品库存列显示 `预售` 或 `不适用`。
- 导出 CSV 包含购买模式。

### 第 6 步：BACKEND-018

升级预约提交接口。

原因：

- 固定预约页最终必须提交 `productIds`。
- 如果后端仍是单 `productId`，前端弹窗多选无法接真实接口。
- 数据模型和响应结构会影响 `BACKEND-019`、`SHOP-FE-017`、`ADMIN-FE-011`。

交付标准：

- `POST /preorder-discounts/claim` 支持 `productIds`。
- 可一次提交 1 到 2 个产品。
- 每个产品生成独立 lead 和 code。
- 返回逐产品 `items`。

### 第 7 步：BACKEND-019

完善邮件模板、多产品发送和后台管理接口。

原因：

- `BACKEND-018` 创建多条 lead 后，邮件必须逐条发送。
- 官网成功态需要依赖后端返回每个产品的邮件状态。
- 后台预约名单和重发也依赖这套接口。

交付标准：

- 选 1 个产品发 1 封邮件。
- 选 2 个产品发 2 封邮件。
- 每封邮件包含对应产品图片、单个产品名称、优惠码、有效期。
- 邮件模板基于 `E:\邮件模版\moxton-discount-email.html`。
- 邮件底部产品名称只显示当前优惠码对应的一个产品。
- 后台列表、详情、重发接口可用。

### 第 8 步：BACKEND-023

更新预售预约 API 文档。

原因：

- `BACKEND-018/019/022` 完成后，预约提交、邮件状态、后台预约接口和商品购买模式筛选接口都已稳定。
- `SHOP-FE-017`、`ADMIN-FE-011`、`ADMIN-FE-012` 需要以最新 API 文档为接入依据。
- 必须避免前端继续按旧的单 `productId` 字段或旧邮件状态理解接口。

交付标准：

- 新增 `02-api/preorder-discounts.md`。
- 更新 `02-api/products.md` 中后台商品列表 `purchaseMode` 筛选。
- 更新 `02-api/README.md` 接口索引。
- 更新 `02-api/CHANGELOG.md`。
- 文档明确 `productIds`、逐产品 `items`、有效期配置、单产品单邮件、后台列表/详情/重发接口。

### 第 9 步：SHOP-FE-017

开发固定预约页。

原因：

- 此时真实产品、商店预售展示、预约提交接口、邮件状态和 API 文档都已经稳定。
- 可以直接联调真实接口和真实商品，避免先 mock 后返工。

交付标准：

- `/preorder-discount` 页面完整可访问。
- 桌面端和移动端 UI 基本还原原型。
- 产品展示区动态展示后台 `PREORDER` 商品。
- 产品展示区使用真实商品主图。
- 点击提交后弹窗选择产品。
- 至少选择一个产品。
- 提交后能触发邮件发送。

### 第 10 步：ADMIN-FE-011

做后台预约名单和详情页。

原因：

- 此时已有真实预约数据。
- 列表字段和详情字段可以按后端最终响应开发。

交付标准：

- 后台可查看预约记录。
- 可按关键词、产品、邮件状态、来源筛选。
- 可查看详情。

### 第 11 步：ADMIN-FE-012

做后台重发邮件。

原因：

- 依赖 `ADMIN-FE-011` 的页面。
- 依赖 `BACKEND-019` 的重发接口。

交付标准：

- 列表或详情可以重发。
- 重发有二次确认。
- 重发后刷新状态。

### 第 12 步：联调与验收

完整链路验收：

1. 确认测试商品已清理。
2. 确认后台已录入两款真实预售产品并设置 `PREORDER`。
3. 官网商品列表展示两款预售产品，按钮为“即将上线”。
4. 官网商品详情按钮为“即将上线”。
5. 首页“立即预约”进入预约页。
6. 预约页桌面端和移动端布局对齐原型。
7. 预约页产品展示区显示两款真实预售产品主图。
8. 用户填写表单。
9. 点击 `Send My Discount Code`。
10. 弹窗选择 1 个产品。
11. 提交后收到 1 封邮件。
12. 再用另一个邮箱选择 2 个产品。
13. 提交后收到 2 封邮件。
14. 后台看到对应预约记录。
15. 后台重发邮件可用。

---

## 7. 活跃任务文档

后端：

- `01-tasks/active/backend/BACKEND-021-clean-test-products.md`
- `01-tasks/active/backend/BACKEND-022-admin-product-purchase-mode-filter.md`
- `01-tasks/active/backend/BACKEND-018-preorder-discount-claim-api.md`
- `01-tasks/active/backend/BACKEND-019-preorder-email-and-admin-api.md`
- `01-tasks/active/backend/BACKEND-023-preorder-api-documentation-update.md`
- `01-tasks/active/backend/BACKEND-020-product-preorder-page-content.md`

管理后台：

- `01-tasks/active/admin-frontend/ADMIN-DATA-001-create-real-preorder-products.md`
- `01-tasks/active/admin-frontend/ADMIN-FE-015-product-form-preorder-simplification.md`
- `01-tasks/active/admin-frontend/ADMIN-FE-014-product-list-preorder-management.md`
- `01-tasks/active/admin-frontend/ADMIN-FE-011-preorder-discount-leads-page.md`
- `01-tasks/active/admin-frontend/ADMIN-FE-012-preorder-email-resend.md`
- `01-tasks/active/admin-frontend/ADMIN-FE-013-product-preorder-page-content-config.md`

官网：

- `01-tasks/active/shop-frontend/SHOP-FE-016-purchase-mode-and-preorder-entry.md`
- `01-tasks/active/shop-frontend/SHOP-FE-017-preorder-discount-form.md`
- `01-tasks/active/shop-frontend/SHOP-FE-018-shop-preorder-coming-soon-display.md`

---

## 8. 最终验收清单

产品模式：

- [ ] 当前测试商品已软删除。
- [ ] 后台已录入 `AI Sheep Counting Camera`。
- [ ] 后台已录入 `AI Wool Diameter Analyzer`。
- [ ] 后台可以设置产品为 `PREORDER`。
- [ ] 后台新增 `PREORDER` 商品时不显示预售预约页内容和产品宣传视频。
- [ ] 后台新增 `PREORDER` 商品时库存不必填。
- [ ] 两款真实预售产品都有商品主图。
- [ ] 两款真实预售产品都有商品描述。
- [ ] 后台商品列表可以按购买模式筛选预售产品。
- [ ] 后台商品列表中预售产品价格/库存展示不产生可购买误解。
- [ ] 官网商品列表预售产品显示“即将上线”。
- [ ] 官网商品列表预售产品按钮灰色禁用且不会跳转预约页。
- [ ] 官网商品详情预售产品显示“即将上线”。
- [ ] 官网商品详情桌面端和移动端预售按钮灰色禁用且不会跳转预约页。
- [ ] 预售产品不能加入购物车。
- [ ] 预售产品不能直接结账。

预约页：

- [ ] 首页“立即预约”跳转 `/preorder-discount?source=home_preorder`。
- [ ] 页面 UI 基本还原原型。
- [ ] 移动端 UI 对齐原型。
- [ ] 产品展示区动态显示后台 `PREORDER` 产品。
- [ ] 产品展示区使用商品主图。
- [ ] 产品展示区显示两款真实预售产品，不显示测试商品。
- [ ] 移动端产品图不溢出、不裁掉关键设备主体。
- [ ] 数羊摄像头移动端组合图展示正常。
- [ ] 产品展示区不做勾选。
- [ ] 表单字段和原型一致。
- [ ] 表单校验正确。
- [ ] 点击提交后弹窗选择产品。
- [ ] 未选择产品不能提交。
- [ ] 至少选择一个产品可以提交。

后端：

- [ ] `productIds` 支持 1 到 2 个产品。
- [ ] 产品必须是 `PREORDER`。
- [ ] 同邮箱同产品去重。
- [ ] 同邮箱不同产品可以分别领取。
- [ ] 一个产品生成一个 code。
- [ ] 两个产品生成两个 code。
- [ ] 优惠码有效期来自配置。
- [ ] 本次上线有效期配置为 2026 年 12 月 31 日。
- [ ] `02-api` 已更新预售预约接口文档。

邮件：

- [ ] 选择 1 个产品发送 1 封邮件。
- [ ] 选择 2 个产品发送 2 封邮件。
- [ ] 邮件包含对应产品名称。
- [ ] 每封邮件只包含一个产品名称，不同时显示两款产品。
- [ ] 邮件包含对应产品优惠码。
- [ ] 邮件包含有效期。
- [ ] 邮件有效期文案由 `expiresAt` 动态格式化，不写死。
- [ ] 邮件模板基于 `E:\邮件模版\moxton-discount-email.html`。
- [ ] 邮件可以展示公网产品图片。
- [ ] 邮件不包含视频。

后台：

- [ ] 后台能查看预约名单。
- [ ] 后台能查看预约详情。
- [ ] 后台能看到优惠码和邮件状态。
- [ ] 后台能重发邮件。
- [ ] 重发不生成新优惠码。

---

## 9. 后续低优先级能力

这些能力可以后续再做，不阻塞本次预售预约发码上线：

- 结账时输入优惠码抵扣。
- 优惠码适用产品校验。
- 优惠码使用状态 `USED` 自动更新。
- 活动后台配置折扣比例和有效期。
- 邮件模板后台可视化配置。
- 同一次提交按 `submissionId` 在后台做聚合视图。
- 官网登录入口恢复。
- 用户登录后把预约记录和 `userId` 关联展示。

