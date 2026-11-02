# Tech-Spec: 产品测试计划申请数据模型与后台接口

**任务ID:** BACKEND-025
**创建时间:** 2026-06-29
**状态:** 待开发
**角色:** 后端工程师
**项目:** moxton-lotapi
**优先级:** P1
**技术栈:** Node.js + Koa + TypeScript + Prisma + MySQL
**QA_LEVEL:** full

---

## 概述

### 问题陈述

官网预售预约页需要新增 AI Sheep Counting Camera 官方产品测试计划报名入口。用户在预约优惠码时可以勾选参加测试计划，并填写牧场详细信息。后续运营会导出申请名单给管理层筛选，再由后台手动搜索入选申请并发送资格邮件。

当前预约优惠码模型 `PreorderDiscountLead` 只负责优惠码领取和邮件发送，不适合承载测试计划筛选、状态标记、资格邮件和管理备注。如果直接把测试计划字段塞进预约优惠码表，会造成以下问题：

- 用户一次预约多个产品时，测试申请信息会随 lead 重复。
- 优惠码发放状态和测试资格筛选状态混在同一张表。
- 后续增加入选、拒绝、资格邮件重发、设备发放等状态时会污染优惠码闭环。

### 解决方案

新增独立数据模型 `ProductTestingApplication`，专门保存产品测试计划申请。

核心规则：

- 用户侧仍通过 `POST /preorder-discounts/claim` 提交预约。
- 请求体新增 `testingProgramOptIn` 和 `testingProgram`。
- 未勾选测试计划时，预约优惠码流程不受影响。
- 勾选测试计划时，后端除创建预约优惠码 lead 外，额外创建或更新一条测试申请。
- 一次预约选择多个产品时，只创建一条测试申请，不按产品重复创建。
- 同一邮箱同一测试计划按 `normalizedEmail + programKey` 去重。
- 后台提供测试申请列表、详情、状态更新、备注更新、资格邮件发送、导出接口。

### 范围

**包含:**

- 新增 `ProductTestingApplication` Prisma 模型和迁移。
- 扩展 `POST /preorder-discounts/claim`，接收测试计划报名字段。
- 勾选测试计划时创建或更新测试申请。
- 新增后台测试申请列表、详情、状态更新、备注更新接口。
- 新增后台发送资格邮件接口。
- 新增测试申请导出接口，支持 CSV 或 Excel。
- 新增测试计划资格邮件模板和发送逻辑。
- 在预约优惠码后台详情中可返回关联的测试申请摘要。

**不包含:**

- 官网页面 UI 实现，详见 `SHOP-FE-019`。
- 后台页面 UI 实现，详见 `ADMIN-FE-017`。
- 管理层 Excel 导入筛选结果。
- 设备发放、物流、数据上传管理。
- 产品测试活动配置后台；本阶段 `programKey` 使用固定值。

---

## 开发上下文

相关现有文件：

- `prisma/schema.prisma`
- `src/controllers/PreorderDiscount.ts`
- `src/models/PreorderDiscountLead.ts`
- `src/routes/preorder-discounts.ts`
- `src/services/EmailService.ts`
- `src/controllers/*`
- `src/models/*`
- `src/routes/index.ts`

建议新增文件：

- `src/controllers/ProductTestingApplication.ts`
- `src/models/ProductTestingApplication.ts`
- `src/routes/product-testing-applications.ts`
- `src/services/ProductTestingEmailService.ts` 或复用现有邮件服务扩展

### 依赖项

- 前置任务：`BACKEND-018`
- 前置任务：`BACKEND-019`
- 前置任务：`BACKEND-023`
- API 文档：`02-api/product-testing-applications.md`

---

## 数据模型

### 新增模型

建议 Prisma 模型：

```prisma
model ProductTestingApplication {
  id                 String    @id @default(cuid())
  programKey         String
  submissionId       String?

  firstName          String
  lastName           String
  phone              String
  email              String
  normalizedEmail    String

  ranchName          String?
  ranchAddress       String?   @db.Text
  sheepCount         Int?
  sheepBreed         String?

  status             String    @default("APPLIED")
  notificationStatus String    @default("NOT_SENT")
  notificationError  String?   @db.Text
  notificationRetryCount Int   @default(0)

  selectedAt         DateTime?
  notifiedAt         DateTime?
  adminNotes         String?   @db.Text

  source             String?
  createdAt          DateTime  @default(now())
  updatedAt          DateTime  @updatedAt

  @@unique([normalizedEmail, programKey])
  @@index([programKey])
  @@index([submissionId])
  @@index([status])
  @@index([notificationStatus])
  @@index([createdAt])
  @@map("product_testing_applications")
}
```

### 字段说明

| 字段 | 说明 |
|------|------|
| `programKey` | 测试计划标识，本阶段固定为 `ai_sheep_counting_camera` |
| `submissionId` | 关联预约优惠码同一次提交 |
| `normalizedEmail` | 小写 trim 后邮箱，用于去重和搜索 |
| `ranchAddress` | 牧场地址；不要复用预约优惠码旧字段名 `address` |
| `sheepCount` | 羊群数量，正整数，可为空 |
| `status` | 申请筛选状态 |
| `notificationStatus` | 资格邮件发送状态 |
| `adminNotes` | 后台管理备注 |

### 状态枚举

申请状态：

| 状态 | 含义 |
|------|------|
| `APPLIED` | 已报名，等待筛选 |
| `SELECTED` | 已入选 |
| `REJECTED` | 未入选 |

邮件状态：

| 状态 | 含义 |
|------|------|
| `NOT_SENT` | 未发送资格邮件 |
| `SENT` | 资格邮件已发送成功 |
| `FAILED` | 资格邮件发送失败 |

---

## 用户侧提交扩展

### 请求体扩展

`POST /preorder-discounts/claim` 新增字段：

```json
{
  "firstName": "Morgan",
  "lastName": "Carter",
  "phone": "+61 400 000 000",
  "email": "morgan@example.com",
  "ranchName": "Carter Ranch",
  "address": "1200 Valley Road",
  "productIds": ["product_a_id"],
  "source": "home_preorder",
  "testingProgramOptIn": true,
  "testingProgram": {
    "programKey": "ai_sheep_counting_camera",
    "ranchName": "Carter Ranch",
    "ranchAddress": "1200 Valley Road",
    "sheepCount": 1200,
    "sheepBreed": "Merino"
  }
}
```

规则：

- `testingProgramOptIn` 为可选布尔值。
- 未传或为 `false` 时，不创建测试申请。
- 为 `true` 时，创建或更新测试申请。
- `testingProgram.programKey` 可选；未传时使用固定值 `ai_sheep_counting_camera`。
- `testingProgram` 内字段均为非必填，但如果传入必须做类型和长度校验。
- `ranchName` 和 `address` 仍保留在预约优惠码 lead 中，用于兼容旧后台展示。
- 测试申请中的牧场字段优先使用 `testingProgram` 内字段；如果未传，可回退使用根级 `ranchName` 和 `address`。

### 响应扩展

预约提交成功响应中建议增加测试申请摘要：

```json
{
  "success": true,
  "data": {
    "status": "SENT",
    "submissionId": "pre_abc123",
    "items": [],
    "testingApplication": {
      "id": "pta_abc123",
      "programKey": "ai_sheep_counting_camera",
      "status": "APPLIED",
      "duplicate": false
    }
  }
}
```

说明：

- 未勾选测试计划时，`testingApplication` 可以省略或返回 `null`。
- 重复报名同一测试计划时，`duplicate = true`。
- 前端用户侧不需要展示申请 ID，但可以用于调试。

### 重复报名处理

同一邮箱同一 `programKey` 已有申请时：

- 不创建新记录。
- 如果现有状态是 `APPLIED`，可以更新联系方式和牧场信息。
- 如果现有状态是 `SELECTED` 或 `REJECTED`，不要覆盖 `status`、`selectedAt`、`notifiedAt`、`notificationStatus`。
- 可以更新 `firstName`、`lastName`、`phone`、`ranchName`、`ranchAddress`、`sheepCount`、`sheepBreed`，但需要保留 `adminNotes`。
- 响应中返回 `duplicate = true`。

---

## 后台 API 设计

### 列表

```http
GET /product-testing-applications/admin
```

认证：必需，`admin` 或 `operator`。

查询参数：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `pageNum` | number | 否 | 页码，默认 1 |
| `pageSize` | number | 否 | 每页数量，默认 10 |
| `keyword` | string | 否 | 搜索姓名、邮箱、电话、牧场名称、牧场地址、羊只品种 |
| `programKey` | string | 否 | 测试计划标识 |
| `status` | string | 否 | `APPLIED`、`SELECTED`、`REJECTED` |
| `notificationStatus` | string | 否 | `NOT_SENT`、`SENT`、`FAILED` |
| `createdFrom` | string | 否 | ISO 日期时间 |
| `createdTo` | string | 否 | ISO 日期时间 |

### 详情

```http
GET /product-testing-applications/admin/:id
```

### 更新状态

```http
PATCH /product-testing-applications/admin/:id/status
```

请求：

```json
{
  "status": "SELECTED"
}
```

规则：

- `APPLIED` 可以改为 `SELECTED` 或 `REJECTED`。
- `SELECTED` 和 `REJECTED` 之间允许手动切换，但要记录 `updatedAt`。
- 改为 `SELECTED` 时，如果 `selectedAt` 为空，设置为当前时间。
- 改为 `REJECTED` 时，不清空已发送邮件状态，避免丢失审计信息。

### 更新备注

```http
PATCH /product-testing-applications/admin/:id/notes
```

请求：

```json
{
  "adminNotes": "管理层筛选通过，优先联系。"
}
```

### 发送资格邮件

```http
POST /product-testing-applications/admin/:id/send-selection-email
```

规则：

- 发送前如果 `status !== SELECTED`，后端可以自动更新为 `SELECTED`，也可以要求前端先标记入选。推荐自动更新为 `SELECTED`，减少后台操作步骤。
- 发送成功后：
  - `status = SELECTED`
  - `notificationStatus = SENT`
  - `notifiedAt = now`
  - `notificationError = null`
- 发送失败后：
  - `status = SELECTED`
  - `notificationStatus = FAILED`
  - `notificationError = 错误原因`
  - `notificationRetryCount += 1`
- 允许对 `FAILED` 状态重发。
- 对已 `SENT` 的申请，再次点击发送应弹出前端确认；后端可允许重发并增加 retry count，或返回明确错误。推荐允许重发，便于纠错。

### 导出

```http
GET /product-testing-applications/admin/export
```

认证：必需，`admin` 或 `operator`。

导出筛选参数与列表接口一致，第一版至少支持：

- `keyword`
- `programKey`
- `status`
- `notificationStatus`
- `createdFrom`
- `createdTo`

导出字段：

- `applicationId`
- `programKey`
- `status`
- `notificationStatus`
- `firstName`
- `lastName`
- `email`
- `phone`
- `ranchName`
- `ranchAddress`
- `sheepCount`
- `sheepBreed`
- `source`
- `submissionId`
- `createdAt`
- `selectedAt`
- `notifiedAt`
- `adminNotes`

说明：

- 必须导出 `applicationId`，便于管理层筛选后后台准确搜索。
- 5 到 10 个名额场景下不做导入筛选结果，后台手动搜索即可。
- 导出格式可以先实现 CSV；如果项目已有 Excel 工具链，可以实现 `.xlsx`。

---

## 邮件模板

新增资格邮件模板，用于通知入选测试计划。

邮件内容要点：

- 收件人称呼使用 `firstName`。
- 明确用户已入选 AI Sheep Counting Camera 官方测试计划。
- 说明后续会由团队联系设备交付和测试安排。
- 简要说明测试职责：记录现场羊群数据，按要求上传数据，用于模型训练和迭代。
- 不在邮件里承诺现金补贴或额外权益。

建议邮件主题：

```text
You have been selected for the AI Sheep Counting Camera testing program
```

---

## 实施步骤

1. 新增 Prisma 模型 `ProductTestingApplication`。
2. 生成并检查数据库迁移。
3. 新增模型层 `ProductTestingApplication`，封装列表、详情、创建或更新、状态更新、备注更新、导出查询。
4. 扩展 `PreorderDiscount` claim 请求体类型，解析 `testingProgramOptIn` 和 `testingProgram`。
5. 在预约优惠码 claim 成功路径中，按 `submissionId` 创建或更新测试申请。
6. 保证多产品预约时只创建一条测试申请。
7. 新增后台路由 `product-testing-applications` 并注册到路由入口。
8. 实现列表、详情、状态更新、备注更新接口。
9. 实现资格邮件发送服务。
10. 实现发送资格邮件接口。
11. 实现导出接口。
12. 在预约优惠码详情接口中返回关联测试申请摘要。
13. 补充单元测试或 API 测试。
14. 更新 `02-api/product-testing-applications.md` 和 `02-api/preorder-discounts.md`。

---

## 验收标准

- [ ] 未勾选测试计划时，预约优惠码提交流程不受影响。
- [ ] 勾选测试计划时，预约优惠码正常创建，同时创建一条测试申请。
- [ ] 一次预约多个产品时，只创建一条测试申请。
- [ ] 同一邮箱同一测试计划重复报名不会创建重复记录。
- [ ] 重复报名 `APPLIED` 状态时可更新联系方式和牧场信息。
- [ ] 重复报名不会覆盖 `SELECTED`、`REJECTED`、邮件状态和管理备注。
- [ ] 后台列表支持分页。
- [ ] 后台 keyword 可搜索姓名、邮箱、电话、牧场名称。
- [ ] 后台可按申请状态和邮件状态筛选。
- [ ] 后台详情展示完整申请信息。
- [ ] 后台可标记 `SELECTED` 和 `REJECTED`。
- [ ] 后台可保存管理备注。
- [ ] 后台可发送资格邮件。
- [ ] 资格邮件发送成功后状态更新为 `SELECTED` 和 `SENT`。
- [ ] 资格邮件发送失败后状态更新为 `FAILED` 并保留错误原因。
- [ ] `FAILED` 邮件可重发。
- [ ] 导出文件包含 `applicationId` 和完整牧场信息。
- [ ] 预约优惠码详情可看到是否关联测试申请。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 测试申请与优惠码 lead 重复建模 | 测试申请独立成表，优惠码表只保留摘要或关联入口 |
| 多产品预约导致测试申请重复 | 以 `normalizedEmail + programKey` 去重，并在一次 claim 中只创建一次 |
| 重复报名覆盖管理层筛选结果 | 只有 `APPLIED` 状态允许更新申请资料，不覆盖筛选和邮件字段 |
| 邮件发送失败影响状态判断 | 申请状态和邮件状态分离 |
| CSV 中文乱码 | 如导出 CSV，使用 UTF-8 BOM 或项目已有导出规范 |
| 后续需要批量导入筛选结果 | 第一版不做导入，但导出保留 `applicationId` |

---

**相关文档:**

- [产品测试计划申请 API](../../../02-api/product-testing-applications.md)
- [预售预约优惠码 API](../../../02-api/preorder-discounts.md)
- [官网测试计划报名任务](../shop-frontend/SHOP-FE-019-testing-program-opt-in.md)
- [后台产品测试申请任务](../admin-frontend/ADMIN-FE-017-product-testing-applications.md)
