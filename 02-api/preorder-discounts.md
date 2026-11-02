# 预售预约优惠码 API

最后更新：2026-07-10

本文档描述官网预售预约优惠码接口与后台管理接口。当前实现来自 `BACKEND-018`、`BACKEND-019`，预约提交已从旧的单 `productId` 升级为 `productIds` 数组。

## 基本规则

- 用户侧预约提交接口不要求登录；登录用户可携带 Bearer Token，后端会记录 `userId`。
- 请求体必须使用 `productIds: string[]`，不再推荐使用旧单字段 `productId`。
- `productIds` 至少 1 个，当前最多 2 个。
- 每个产品必须存在、未删除、已上架，并且 `purchaseMode = PREORDER`。
- 同一邮箱同一产品按 `normalizedEmail + productId` 去重。
- 同一邮箱不同产品可以分别领取。
- 一个产品对应一条 lead、一组优惠码、一封邮件。
- 用户一次选择两个产品时，后端创建两条 lead，并在响应后异步发送两封邮件。
- 每封邮件只展示对应的一个产品名称和该产品优惠码。
- 用户可选勾选 AI Sheep Counting Camera 产品测试计划报名；勾选后后端额外创建或更新一条测试申请。
- 测试计划申请独立保存，不按 `productIds` 拆分，不影响预约优惠码 lead 的一产品一行模型。
- `ranchName`、`address` / `ranchAddress`、`sheepCount`、`sheepBreed` 是预约 lead 的根级牧场字段，无论是否勾选测试计划都会保存到每条预约 lead。
- 牧场地址支持根级结构化字段：`country`、`stateRegion`、`locality`、`postcode`、`formattedAddress`、`placeId`；同一次提交创建多条 lead 时，每条 lead 保存同一组地址字段。
- 地址结构化字段全部非必填。空字符串会保存为 `null`；后端不调用 Google API 二次校验，也不会因为 `stateRegion`、`locality`、`postcode`、`placeId` 为空拒绝提交。
- `productFeedbackSurvey` 是预约页产品反馈问卷，后端会规范化后保存到同一次提交创建的每条 lead；未填写、`null` 或空对象保存为 `null`。
- 新生成的预约优惠码为固定 10 位大写英文字母和数字组合，格式为 `^[A-Z0-9]{10}$`。
- 邮件模板基于 `E:\邮件模版\moxton-discount-email.html`，但当前发信邮件只展示 logo，不展示产品主图；logo 必须使用公网可访问的 `https://` URL。
- 优惠码当前业务口径为永久有效；如接口保留 `expiresAt` 字段，`null` 表示永久有效。前端不要自行推导或写死日期。

## 状态说明

### 聚合状态 `data.status`

| 状态 | 含义 |
|------|------|
| `SENT` | 本次新建 lead 的邮件全部发送成功；用户侧提交接口通常不会同步返回该状态 |
| `PENDING` | 已创建 lead，但仍处于待发送状态 |
| `FAILED` | 本次新建 lead 的邮件全部发送失败；可在后台列表或详情中查看 |
| `PARTIAL_SENT` | 本次新建 lead 中部分邮件发送成功、部分失败；可在后台列表或详情中查看 |
| `PARTIAL_DUPLICATE` | 本次提交中存在重复产品，同时也有新建 lead |
| `DUPLICATE` | 所选产品均已被该邮箱领取；当前实现会以错误响应返回 |

### 逐产品 `items[].status`

| 状态 | 含义 |
|------|------|
| `SENT` | 该产品 lead 的邮件已发送成功 |
| `PENDING` | 该产品 lead 已创建，邮件状态仍为待发送 |
| `FAILED` | 该产品 lead 的邮件发送失败 |
| `DUPLICATE` | 该邮箱已领取过该产品优惠码，未创建新 lead、未自动重发 |

`items[].emailStatus` 对应数据库邮件状态，当前合法值为 `PENDING`、`SENT`、`FAILED`。

## 用户侧：提交预约

```http
POST /preorder-discounts/claim
```

认证：可选。

### 请求体

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
  "sheepCount": 1200,
  "sheepBreed": "Merino",
  "productIds": ["product_a_id", "product_b_id"],
  "source": "home_preorder",
  "testingProgramOptIn": true,
  "testingProgram": {
    "programKey": "ai_sheep_counting_camera",
    "ranchName": "Carter Ranch",
    "ranchAddress": "1200 Valley Road",
    "sheepCount": 1200,
    "sheepBreed": "Merino"
  },
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

字段说明：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `firstName` | string | 是 | 名 |
| `lastName` | string | 是 | 姓 |
| `phone` | string | 是 | 联系电话 |
| `email` | string | 是 | 联系邮箱；后端会校验邮箱格式并按小写去重 |
| `ranchName` | string | 否 | 农场名称 |
| `country` | string | 否 | 用户可见国家选择；trim，空字符串保存为 `null`，最大 100 字符 |
| `stateRegion` | string | 否 | Google 解析出的州、领地或地区；trim，空字符串保存为 `null`，最大 100 字符 |
| `locality` | string | 否 | Google 解析出的城市、区镇或 locality；trim，空字符串保存为 `null`，最大 100 字符 |
| `postcode` | string | 否 | Google 解析出的邮编；trim，空字符串保存为 `null`，最大 20 字符 |
| `address` | string | 否 | 用户最终提交的牧场地址文本，可为手填；也兼容根级 `ranchAddress`，优先使用 `address`，最大 500 字符 |
| `ranchAddress` | string | 否 | 牧场地址别名；仅当 `address` 为空时写入预约 lead 的 `address`，最大 500 字符 |
| `formattedAddress` | string | 否 | Google 返回的标准化完整地址；trim，空字符串保存为 `null`，最大 500 字符 |
| `placeId` | string | 否 | Google Place ID；trim，空字符串保存为 `null`，最大 255 字符 |
| `sheepCount` | number 或可转换为整数的 string | 否 | 羊群数量；空值保存为 `null`，填写时必须为 1 到 999999 的正整数 |
| `sheepBreed` | string | 否 | 羊只品种；后端 trim，空字符串保存为 `null`，最大 100 字符，不做枚举限制 |
| `productIds` | string[] | 是 | 预售产品 ID 数组，至少 1 个，当前最多 2 个 |
| `source` | string | 否 | 来源标记，例如 `home_preorder` |
| `testingProgramOptIn` | boolean | 否 | 是否申请参加产品测试计划，默认 `false` |
| `testingProgram` | object | 否 | 测试计划申请信息，仅 `testingProgramOptIn = true` 时处理 |
| `productFeedbackSurvey` | object | 否 | 产品反馈问卷；合法值会保存到每条预约 lead，列表返回摘要，详情返回完整对象 |

`testingProgram` 字段说明见 [product-testing-applications.md](product-testing-applications.md)。其中 `programKey` 第一版固定为 `ai_sheep_counting_camera`，牧场字段均为非必填。`testingProgram` 内未提供的牧场字段会回退使用根级 `ranchName`、`address` / `ranchAddress`、`sheepCount`、`sheepBreed`。

仅手填地址时可以只提交 `country + address`，其他 Google 隐藏字段可省略或传 `null`：

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

`productFeedbackSurvey` 字段说明：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `interestedProduct` | string | 否 | `sheep_counting_camera`、`wool_diameter_analyzer`、`both`、`not_sure` |
| `woolAnalyzerSurvey.prioritizedFeatures` | string[] | 否 | `testing_accuracy`、`testing_speed`、`sample_preparation_efficiency`、`portability`、`price`、`others` |
| `woolAnalyzerSurvey.optimizationSuggestions` | string | 否 | 羊毛直径分析仪优化建议，最大 1000 字符 |
| `woolAnalyzerSurvey.priceRange` | string | 否 | 羊毛直径分析仪价格接受范围，自由文本保存，最大 200 字符 |
| `woolAnalyzerSurvey.intendedUseLocations` | string[] | 否 | `shed`、`race`、`laboratory`、`office`、`research_institution`、`others` |
| `woolAnalyzerSurvey.idealTestingTime` | string | 否 | 理想测试耗时，自由文本保存，最大 200 字符 |
| `woolAnalyzerSurvey.desktopVersionInterest` | string | 否 | `yes_desktop_needed`、`no_portable_enough` |
| `sheepCountingSurvey.prioritizedFeatures` | string[] | 否 | `detection_accuracy`、`portability`、`price`、`others` |
| `sheepCountingSurvey.optimizationSuggestions` | string | 否 | 羊只计数相机优化建议，最大 1000 字符 |
| `sheepCountingSurvey.priceRange` | string | 否 | 羊只计数相机价格接受范围，自由文本保存，最大 200 字符 |
| `sheepCountingSurvey.stationaryVersionInterest` | string | 否 | `yes_stationary_needed`、`no_portable_sufficient` |

校验规则：

- 未填写、`null`、空对象均视为未填写，保存为 `null`。
- 未识别字段会被忽略。
- 文本字段会 trim，空字符串忽略；超长返回 validation error。
- 多选字段必须为数组，数组内空字符串会过滤，重复值会按首次出现顺序去重；非法值返回 validation error。
- `interestedProduct = wool_diameter_analyzer` 时只保存 `woolAnalyzerSurvey`；`interestedProduct = sheep_counting_camera` 时只保存 `sheepCountingSurvey`；`both` 可同时保存两组；`not_sure` 或空值会移除产品专属隐藏分组数据。

### 成功响应：提交已接收，邮件待发送

```json
{
  "code": 200,
  "message": "Success",
  "success": true,
  "data": {
    "status": "PENDING",
    "message": "Thanks! Your preorder discount code will be sent to your email shortly.",
    "submissionId": "pre_abc123",
    "items": [
      {
        "productId": "product_a_id",
        "productName": "AI Sheep Counting Camera",
        "leadId": "lead_a_id",
        "status": "PENDING",
        "duplicate": false,
        "emailStatus": "PENDING"
      }
    ],
    "testingApplication": {
      "id": "pta_abc123",
      "programKey": "ai_sheep_counting_camera",
      "status": "APPLIED",
      "duplicate": false
    }
  },
  "timestamp": "2026-06-28T10:00:00.000Z"
}
```

说明：

- 前端不应展示优惠码；优惠码在接口响应后由后端异步发送。
- 用户侧提交接口不等待 Resend 邮件接口完成，成功响应只表示预约 lead 已创建；最终邮件状态以后台列表或详情中的 `emailStatus`、`emailSentAt`、`emailError` 为准。
- `submissionId` 用于关联同一次表单提交下的多条 lead。
- `leadId` 可用于后台排查，不用于用户侧重发。
- 新生成的 `code` 不包含 `MXT` 前缀、产品短码或连字符。
- 未勾选测试计划时，`testingApplication` 可以省略或返回 `null`。

### 成功响应：部分重复

```json
{
  "code": 200,
  "message": "Success",
  "success": true,
  "data": {
    "status": "PARTIAL_DUPLICATE",
    "message": "Thanks! Your preorder discount code will be sent to your email shortly. Some selected products have already been claimed with this email.",
    "submissionId": "pre_abc123",
    "items": [
      {
        "productId": "product_a_id",
        "productName": "AI Sheep Counting Camera",
        "leadId": "existing_lead_id",
        "status": "DUPLICATE",
        "duplicate": true,
        "emailStatus": "SENT"
      },
      {
        "productId": "product_b_id",
        "productName": "AI Wool Diameter Analyzer",
        "leadId": "new_lead_id",
        "status": "PENDING",
        "duplicate": false,
        "emailStatus": "PENDING"
      }
    ],
    "testingApplication": {
      "id": "pta_abc123",
      "programKey": "ai_sheep_counting_camera",
      "status": "APPLIED",
      "duplicate": false
    }
  },
  "timestamp": "2026-06-28T10:00:00.000Z"
}
```

说明：单条邮件异步发送失败不会阻断另一个产品的邮件发送。失败详情可在后台详情接口查看 `emailError`，后台也可以使用重发接口处理失败记录。

### 错误响应：全部重复

```json
{
  "success": false,
  "code": "PREORDER_DISCOUNT_ALREADY_CLAIMED",
  "message": "This email has already claimed discount codes for the selected products.",
  "data": {
    "submissionId": "pre_abc123",
    "items": [
      {
        "productId": "product_a_id",
        "productName": "AI Sheep Counting Camera",
        "leadId": "existing_lead_id",
        "status": "DUPLICATE",
        "duplicate": true,
        "emailStatus": "SENT"
      }
    ]
  }
}
```

当前实现对全部重复使用 HTTP `400`。

### 常见校验错误

缺少 `productIds`：

```json
{
  "code": 400,
  "message": "Validation Error",
  "success": false,
  "data": {
    "errors": ["productIds is required"]
  },
  "timestamp": "2026-06-28T10:00:00.000Z"
}
```

`productIds` 为空：

```json
{
  "code": 400,
  "message": "Validation Error",
  "success": false,
  "data": {
    "errors": ["At least one product must be selected"]
  }
}
```

`productIds` 超过上限：

```json
{
  "code": 400,
  "message": "Validation Error",
  "success": false,
  "data": {
    "errors": ["No more than 2 products can be selected"]
  }
}
```

邮箱格式错误：

```json
{
  "code": 400,
  "message": "Validation Error",
  "success": false,
  "data": {
    "errors": ["Invalid email format"]
  }
}
```

产品不存在、已下架或已删除：

```json
{
  "code": 400,
  "message": "One or more selected products were not found or are unavailable",
  "success": false,
  "data": null
}
```

`sheepCount` 非法：

```json
{
  "code": 400,
  "message": "Validation Error",
  "success": false,
  "data": {
    "errors": ["sheepCount must be a positive integer"]
  }
}
```

产品不是预售模式：

```json
{
  "code": 400,
  "message": "One or more selected products are not available for preorder discount claim",
  "success": false,
  "data": null
}
```

## 后台：预约列表

```http
GET /preorder-discounts/admin/leads
```

认证：必需，`admin` 或 `operator`。

### 查询参数

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `pageNum` | number | 否 | 页码，默认 1 |
| `pageSize` | number | 否 | 每页数量，默认 10 |
| `keyword` | string | 否 | 搜索姓名、邮箱、电话、牧场名称、国家、地区、城市/区镇、邮编、牧场地址、标准化地址、羊只品种、产品名、优惠码 |
| `productId` | string | 否 | 按产品筛选 |
| `emailStatus` | string | 否 | `PENDING`、`SENT`、`FAILED` |
| `source` | string | 否 | 按来源筛选 |
| `submissionId` | string | 否 | 按同一次提交筛选 |

示例：

```http
GET /preorder-discounts/admin/leads?pageNum=1&pageSize=10&emailStatus=SENT&submissionId=pre_abc123
Authorization: Bearer <admin_or_operator_token>
```

### 响应示例

```json
{
  "code": 200,
  "message": "Success",
  "success": true,
  "data": {
    "list": [
      {
        "id": "lead_a_id",
        "submissionId": "pre_abc123",
        "firstName": "Morgan",
        "lastName": "Carter",
        "email": "morgan@example.com",
        "phone": "+61 400 000 000",
        "ranchName": "Carter Ranch",
        "country": "Australia",
        "stateRegion": "New South Wales",
        "locality": "Gollan",
        "postcode": "2820",
        "address": "433 Binginbar Road, Gollan NSW 2820, Australia",
        "formattedAddress": "433 Binginbar Road, Gollan NSW 2820, Australia",
        "placeId": "google_place_id",
        "sheepCount": 1200,
        "sheepBreed": "Merino",
        "source": "home_preorder",
        "productId": "product_a_id",
        "productName": "AI Sheep Counting Camera",
        "code": "7KQ9M2XA4B",
        "discountPercent": 15,
        "expiresAt": null,
        "codeStatus": "ACTIVE",
        "emailStatus": "SENT",
        "emailSentAt": "2026-06-28T10:00:00.000Z",
        "emailRetryCount": 0,
        "productFeedbackSurvey": {
          "interestedProduct": "both",
          "hasWoolAnalyzerSurvey": true,
          "hasSheepCountingSurvey": true,
          "woolPrioritizedFeatures": ["testing_accuracy", "testing_speed"],
          "sheepCountingPrioritizedFeatures": ["detection_accuracy", "portability"],
          "hasOpenText": true
        },
        "createdAt": "2026-06-28T09:59:00.000Z",
        "product": {
          "id": "product_a_id",
          "name": "AI Sheep Counting Camera",
          "purchaseMode": "PREORDER",
          "images": ["https://cdn.example.com/sheep.jpg"],
          "metadata": {
            "preorder": {
              "heroImage": "https://cdn.example.com/sheep-hero.jpg"
            }
          },
          "productImageUrl": "https://cdn.example.com/sheep.jpg"
        }
      }
    ],
    "pageNum": 1,
    "pageSize": 10,
    "total": 1,
    "totalPages": 1
  },
  "timestamp": "2026-06-28T10:00:00.000Z"
}
```

## 后台：预约详情

```http
GET /preorder-discounts/admin/leads/:id
```

认证：必需，`admin` 或 `operator`。

详情返回内容包括：

- 完整表单信息：`firstName`、`lastName`、`phone`、`email`、`ranchName`、`country`、`stateRegion`、`locality`、`postcode`、`address`、`formattedAddress`、`placeId`、`sheepCount`、`sheepBreed`、`source`、`submissionId`。
- 产品信息：`product`、`productId`、`productName`。
- 优惠码信息：`code`、`discountPercent`、`expiresAt`、`codeStatus`。新生成的 `code` 为 10 位大写英文字母和数字组合。
- 产品反馈问卷：`productFeedbackSurvey`，详情返回完整规范化对象；历史记录或未填写时返回 `null`。
- 邮件状态：`emailStatus`、`emailSentAt`、`emailError`、`emailRetryCount`。
- 兑换信息：`redeemedAt`、`orderId`。

### 响应示例

```json
{
  "code": 200,
  "message": "Success",
  "success": true,
  "data": {
    "id": "lead_a_id",
    "submissionId": "pre_abc123",
    "firstName": "Morgan",
    "lastName": "Carter",
    "phone": "+61 400 000 000",
    "email": "morgan@example.com",
    "normalizedEmail": "morgan@example.com",
    "ranchName": "Carter Ranch",
    "country": "Australia",
    "stateRegion": "New South Wales",
    "locality": "Gollan",
    "postcode": "2820",
    "address": "433 Binginbar Road, Gollan NSW 2820, Australia",
    "formattedAddress": "433 Binginbar Road, Gollan NSW 2820, Australia",
    "placeId": "google_place_id",
    "sheepCount": 1200,
    "sheepBreed": "Merino",
    "source": "home_preorder",
    "productId": "product_a_id",
    "productName": "AI Sheep Counting Camera",
    "code": "7KQ9M2XA4B",
    "discountPercent": 15,
    "expiresAt": null,
    "codeStatus": "ACTIVE",
    "emailStatus": "FAILED",
    "emailSentAt": null,
    "emailError": "RESEND_API_KEY is not configured",
    "emailRetryCount": 1,
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
    },
    "product": {
      "id": "product_a_id",
      "name": "AI Sheep Counting Camera",
      "purchaseMode": "PREORDER",
      "status": 1,
      "productImageUrl": "https://cdn.example.com/sheep.jpg"
    },
    "createdAt": "2026-06-28T09:59:00.000Z",
    "updatedAt": "2026-06-28T10:00:00.000Z"
  },
  "timestamp": "2026-06-28T10:00:00.000Z"
}
```

## 后台：重发邮件

```http
POST /preorder-discounts/admin/leads/:id/resend
```

认证：必需，`admin` 或 `operator`。

规则：

- 使用原 lead 的原 `code`。
- 不生成新优惠码。
- 重发成功后更新 `emailStatus = SENT`、`emailSentAt = now`、`emailError = null`。
- 重发失败后更新 `emailStatus = FAILED`、`emailError`，并让 `emailRetryCount += 1`。

### 成功响应示例

```json
{
  "code": 200,
  "message": "Preorder discount email resent successfully",
  "success": true,
  "data": {
    "id": "lead_a_id",
    "emailStatus": "SENT",
    "emailSentAt": "2026-06-28T10:00:00.000Z",
    "emailError": null,
    "emailRetryCount": 1
  },
  "timestamp": "2026-06-28T10:00:00.000Z"
}
```

### 失败响应示例

接口调用本身仍返回成功 envelope，但 `data.emailStatus` 表示邮件发送失败：

```json
{
  "code": 200,
  "message": "Preorder discount email resend failed",
  "success": true,
  "data": {
    "id": "lead_a_id",
    "emailStatus": "FAILED",
    "emailSentAt": null,
    "emailError": "RESEND_API_KEY is not configured",
    "emailRetryCount": 2
  },
  "timestamp": "2026-06-28T10:00:00.000Z"
}
```

## 有效期与前端展示

- 当前业务口径为永久有效。
- 后端不再使用 `PREORDER_DISCOUNT_EXPIRES_AT` 决定预约优惠码有效期；即使旧环境仍配置该变量，新生成的预约优惠码也应写入 `expiresAt = null`。
- 接口中的 `expiresAt = null` 表示永久有效。
- 用户侧提交接口不返回优惠码，也不要求前端展示有效期。
- 后台列表和详情如果展示有效期，应将 `expiresAt = null` 展示为 `Permanent` / `永久有效`。
- 前端不要根据当前年份、提交时间或产品信息自行推导有效期，也不要写死 `2026-12-31`。

## 接入方说明

- 官网前端预约弹窗应提交 `productIds`，并根据 `items[]` 展示逐产品结果。
- 官网前端如支持测试计划报名，应在主表单中提交 `testingProgramOptIn` 和 `testingProgram`，不要放到产品选择弹窗中处理。
- 管理后台可用列表、详情和重发接口处理邮件失败记录。
- 产品测试申请后台应使用 [product-testing-applications.md](product-testing-applications.md) 中的独立接口；预约优惠码后台只展示测试申请摘要和跳转入口。
- `SHOP-FE-017`、`SHOP-FE-019`、`ADMIN-FE-011`、`ADMIN-FE-012`、`ADMIN-FE-017` 接入时以本文档和产品测试计划申请文档为准。
