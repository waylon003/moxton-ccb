# 产品测试计划申请 API

最后更新：2026-06-29

本文档描述 AI Sheep Counting Camera 官方产品测试计划申请的数据提交扩展和后台管理接口。测试计划申请独立于预约优惠码 lead，用于运营导出名单、管理层筛选、后台标记入选并发送资格邮件。

## 基本规则

- 用户通过官网 `/preorder-discount` 预约优惠码时，可选勾选测试计划报名。
- 用户侧不单独新增公开报名接口，第一版复用 `POST /preorder-discounts/claim`。
- 未勾选测试计划时，不创建测试申请。
- 勾选测试计划时，后端创建或更新一条 `ProductTestingApplication`。
- 一次预约选择多个产品时，只创建一条测试申请。
- 同一邮箱同一测试计划按 `normalizedEmail + programKey` 去重。
- 第一版测试计划固定为 `ai_sheep_counting_camera`。
- 后台支持列表、详情、状态更新、备注更新、资格邮件发送和导出。
- 第一版不支持导入管理层筛选结果；预计 5 到 10 个名额，由后台手动搜索和单条操作完成。

## 状态说明

### 申请状态 `status`

| 状态 | 含义 |
|------|------|
| `APPLIED` | 已报名，等待筛选 |
| `SELECTED` | 已入选 |
| `REJECTED` | 未入选 |

### 邮件状态 `notificationStatus`

| 状态 | 含义 |
|------|------|
| `NOT_SENT` | 未发送资格邮件 |
| `SENT` | 资格邮件已发送成功 |
| `FAILED` | 资格邮件发送失败 |

## 用户侧：预约提交扩展

用户侧仍使用：

```http
POST /preorder-discounts/claim
```

完整预约优惠码接口规则见 [preorder-discounts.md](preorder-discounts.md)。

### 未报名测试计划

```json
{
  "firstName": "Morgan",
  "lastName": "Carter",
  "phone": "+61 400 000 000",
  "email": "morgan@example.com",
  "productIds": ["product_a_id"],
  "source": "home_preorder",
  "testingProgramOptIn": false
}
```

### 报名测试计划

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

字段说明：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `testingProgramOptIn` | boolean | 否 | 是否报名产品测试计划，默认 `false` |
| `testingProgram.programKey` | string | 否 | 测试计划标识，默认 `ai_sheep_counting_camera` |
| `testingProgram.ranchName` | string | 否 | 牧场名称 |
| `testingProgram.ranchAddress` | string | 否 | 牧场地址 |
| `testingProgram.sheepCount` | number | 否 | 羊群数量，正整数 |
| `testingProgram.sheepBreed` | string | 否 | 羊只品种 |

说明：

- `testingProgram` 内字段均为非必填。
- 如果 `testingProgramOptIn = true` 但未传 `testingProgram`，后端仍可创建测试申请，牧场字段为空。
- 根级 `ranchName` 和 `address` 用于兼容预约优惠码 lead；测试计划申请以 `testingProgram` 内字段为准。
- 如果 `testingProgram.ranchName` 或 `testingProgram.ranchAddress` 缺失，后端可以回退使用根级 `ranchName` 和 `address`。

### 预约提交响应扩展

勾选测试计划时，预约提交响应的 `data` 中可包含：

```json
{
  "testingApplication": {
    "id": "pta_abc123",
    "programKey": "ai_sheep_counting_camera",
    "status": "APPLIED",
    "duplicate": false
  }
}
```

重复报名响应：

```json
{
  "testingApplication": {
    "id": "pta_existing",
    "programKey": "ai_sheep_counting_camera",
    "status": "APPLIED",
    "duplicate": true
  }
}
```

未勾选测试计划时，`testingApplication` 可以省略或为 `null`。

## 后台：测试申请列表

```http
GET /product-testing-applications/admin
```

认证：必需，`admin` 或 `operator`。

### 查询参数

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

### 响应示例

```json
{
  "code": 200,
  "message": "Success",
  "success": true,
  "data": {
    "list": [
      {
        "id": "pta_abc123",
        "programKey": "ai_sheep_counting_camera",
        "submissionId": "pre_abc123",
        "firstName": "Morgan",
        "lastName": "Carter",
        "phone": "+61 400 000 000",
        "email": "morgan@example.com",
        "ranchName": "Carter Ranch",
        "ranchAddress": "1200 Valley Road",
        "sheepCount": 1200,
        "sheepBreed": "Merino",
        "status": "APPLIED",
        "notificationStatus": "NOT_SENT",
        "notificationRetryCount": 0,
        "selectedAt": null,
        "notifiedAt": null,
        "source": "home_preorder",
        "createdAt": "2026-06-29T10:00:00.000Z",
        "updatedAt": "2026-06-29T10:00:00.000Z"
      }
    ],
    "pageNum": 1,
    "pageSize": 10,
    "total": 1,
    "totalPages": 1
  },
  "timestamp": "2026-06-29T10:00:00.000Z"
}
```

## 后台：测试申请详情

```http
GET /product-testing-applications/admin/:id
```

认证：必需，`admin` 或 `operator`。

### 响应示例

```json
{
  "code": 200,
  "message": "Success",
  "success": true,
  "data": {
    "id": "pta_abc123",
    "programKey": "ai_sheep_counting_camera",
    "submissionId": "pre_abc123",
    "firstName": "Morgan",
    "lastName": "Carter",
    "phone": "+61 400 000 000",
    "email": "morgan@example.com",
    "normalizedEmail": "morgan@example.com",
    "ranchName": "Carter Ranch",
    "ranchAddress": "1200 Valley Road",
    "sheepCount": 1200,
    "sheepBreed": "Merino",
    "status": "APPLIED",
    "notificationStatus": "FAILED",
    "notificationError": "RESEND_API_KEY is not configured",
    "notificationRetryCount": 1,
    "selectedAt": null,
    "notifiedAt": null,
    "adminNotes": "管理层待筛选。",
    "source": "home_preorder",
    "createdAt": "2026-06-29T10:00:00.000Z",
    "updatedAt": "2026-06-29T10:10:00.000Z"
  },
  "timestamp": "2026-06-29T10:10:00.000Z"
}
```

## 后台：更新申请状态

```http
PATCH /product-testing-applications/admin/:id/status
```

认证：必需，`admin` 或 `operator`。

### 请求体

```json
{
  "status": "SELECTED"
}
```

### 响应示例

```json
{
  "code": 200,
  "message": "Application status updated successfully",
  "success": true,
  "data": {
    "id": "pta_abc123",
    "status": "SELECTED",
    "selectedAt": "2026-06-29T10:20:00.000Z",
    "updatedAt": "2026-06-29T10:20:00.000Z"
  }
}
```

规则：

- `status` 必须是 `APPLIED`、`SELECTED`、`REJECTED`。
- 改为 `SELECTED` 时，如果 `selectedAt` 为空，后端设置为当前时间。
- 改为 `REJECTED` 时，不清空邮件状态。

## 后台：更新管理备注

```http
PATCH /product-testing-applications/admin/:id/notes
```

认证：必需，`admin` 或 `operator`。

### 请求体

```json
{
  "adminNotes": "管理层筛选通过，优先联系。"
}
```

### 响应示例

```json
{
  "code": 200,
  "message": "Application notes updated successfully",
  "success": true,
  "data": {
    "id": "pta_abc123",
    "adminNotes": "管理层筛选通过，优先联系。",
    "updatedAt": "2026-06-29T10:25:00.000Z"
  }
}
```

## 后台：发送资格邮件

```http
POST /product-testing-applications/admin/:id/send-selection-email
```

认证：必需，`admin` 或 `operator`。

规则：

- 发送资格邮件代表该申请入选。
- 如果当前 `status` 不是 `SELECTED`，后端自动更新为 `SELECTED`。
- 发送成功后，`notificationStatus = SENT`，`notifiedAt = now`。
- 发送失败后，`notificationStatus = FAILED`，保存 `notificationError`。
- 对 `FAILED` 可以重发。
- 对 `SENT` 再次调用表示重发；前端应做二次确认。

### 成功响应示例

```json
{
  "code": 200,
  "message": "Selection email sent successfully",
  "success": true,
  "data": {
    "id": "pta_abc123",
    "status": "SELECTED",
    "notificationStatus": "SENT",
    "notificationError": null,
    "notificationRetryCount": 1,
    "selectedAt": "2026-06-29T10:30:00.000Z",
    "notifiedAt": "2026-06-29T10:30:00.000Z"
  }
}
```

### 失败响应示例

接口调用本身仍可返回成功 envelope，但 `data.notificationStatus` 表示邮件发送失败：

```json
{
  "code": 200,
  "message": "Selection email sending failed",
  "success": true,
  "data": {
    "id": "pta_abc123",
    "status": "SELECTED",
    "notificationStatus": "FAILED",
    "notificationError": "RESEND_API_KEY is not configured",
    "notificationRetryCount": 2,
    "selectedAt": "2026-06-29T10:30:00.000Z",
    "notifiedAt": null
  }
}
```

## 后台：导出测试申请

```http
GET /product-testing-applications/admin/export
```

认证：必需，`admin` 或 `operator`。

查询参数与列表接口一致：

- `keyword`
- `programKey`
- `status`
- `notificationStatus`
- `createdFrom`
- `createdTo`

导出字段：

| 字段 | 说明 |
|------|------|
| `applicationId` | 测试申请 ID，用于后台准确搜索 |
| `programKey` | 测试计划标识 |
| `status` | 申请状态 |
| `notificationStatus` | 邮件状态 |
| `firstName` | 名 |
| `lastName` | 姓 |
| `email` | 邮箱 |
| `phone` | 电话 |
| `ranchName` | 牧场名称 |
| `ranchAddress` | 牧场地址 |
| `sheepCount` | 羊群数量 |
| `sheepBreed` | 羊只品种 |
| `source` | 来源 |
| `submissionId` | 预约提交 ID |
| `createdAt` | 报名时间 |
| `selectedAt` | 入选时间 |
| `notifiedAt` | 通知时间 |
| `adminNotes` | 管理备注 |

响应：

- 返回 CSV 或 Excel 文件流。
- `Content-Disposition` 中包含文件名。
- 如返回 CSV，建议使用 UTF-8 BOM，避免中文 Excel 打开乱码。

## 预约优惠码详情联动

预约优惠码后台详情接口可以返回关联测试申请摘要：

```json
{
  "testingApplication": {
    "id": "pta_abc123",
    "programKey": "ai_sheep_counting_camera",
    "status": "APPLIED",
    "notificationStatus": "NOT_SENT"
  }
}
```

后台预约优惠码页面只展示入口，不处理测试计划筛选和资格邮件发送。

## 接入方说明

- 官网前端只需要在预约提交中增加 `testingProgramOptIn` 和 `testingProgram`。
- 管理后台通过独立“产品测试申请”页面处理筛选、导出、备注和资格邮件。
- 预约优惠码后台页面只显示测试申请摘要和跳转入口。
