# 订单管理 API 文档

## 概述

Moxton Lot API 的订单系统支持**混合模式**，同时允许游客和登录用户下单。

**核心特性**:
- ✅ 游客下单: 无需注册即可购买
- ✅ 登录用户下单: 完整订单历史管理
- ✅ 结构化地址: 支持 Google Places 集成
- ✅ 标准化响应: 使用 `OrderTransformer` 统一响应格式

**认证模式**:
- `optionalAuthMiddleware`: 支持游客和登录用户
- `authMiddleware`: 仅登录用户
- `adminMiddleware`: 仅管理员

## 统一响应格式

所有订单 API 使用 `OrderTransformer` 标准化响应:

```typescript
interface OrderResponseDTO {
  id: string                    // 订单数据库 ID
  orderNo: string              // 订单号 (例如: ORD17660554764519925)
  customer: {                   // 客户信息
    name: string
    email: string | null
    phone: string | null
    company?: string
    isGuest: boolean           // true=游客订单, false=用户订单
  }
  address: {                    // 收货地址（结构化）
    addressLine1: string
    addressLine2?: string
    city: string
    state: string
    postalCode: string
    country: string
    countryCode: string
    fullAddress?: string        // 完整地址字符串
    district?: string           // 区域（可选）
  } | null
  amount: {                     // 金额信息
    total: number              // 订单总金额
    currency: string           // 货币代码 (AUD, USD, etc.)
  }
  items: [{                     // 订单项列表
    product: {
      id: string
      name: string
      image?: string           // 商品主图
    }
    quantity: number           // 购买数量
    unitPrice: number         // 商品单价
    subtotal: number          // 小计金额
  }]
  status: string               // 订单状态 (PENDING, PAID, CONFIRMED, SHIPPED, DELIVERED, CANCELLED)
  timestamps: {                // 时间戳
    created: string           // ISO 8601 格式
    updated: string           // ISO 8601 格式
  }
  remarks?: string             // 订单备注
}
```

## 订单状态

| 状态 | 说明 | 可执行操作 |
|------|------|-----------|
| `PENDING` | 待支付 | 取消、支付 |
| `PAID` | 已支付 | - |
| `CONFIRMED` | 已确认 | 发货（管理员） |
| `SHIPPED` | 已发货 | 确认收货（管理员） |
| `DELIVERED` | 已送达 | - |
| `CANCELLED` | 已取消 | - |

### 订单状态流转

```
PENDING (待支付)
  ↓ (支付成功)
PAID (已支付)
  ↓ (支付 Webhook 自动流转)
CONFIRMED (已确认)
  ↓ (管理员发货)
SHIPPED (已发货)
  ↓ (管理员确认收货)
DELIVERED (已送达)

PENDING → CANCELLED (用户取消)
```

---

## 用户端点

### 创建订单

**POST** `/orders`

**认证**: Optional (支持游客和登录用户)

**请求头**:
```
X-Guest-ID: <guest-session-id>  // 游客必填
```

**请求体**:
```json
{
  "items": [                     // ✅ 正确字段名
    {
      "productId": "clx1234567892",
      "quantity": 2,
      "price": 1299.00           // 商品单价
    }
  ],
  "guestInfo": {                 // 游客必填，登录用户可省略
    "name": "张三",
    "email": "guest@example.com",
    "phone": "+86-13800138000",
    "company": "测试公司"
  },
  "shippingInfo": {              // 收货信息（简单格式）
    "consignee": "李四",
    "phone": "+86-13900139000",
    "address": "北京市朝阳区XXX街道XXX号"
  },
  "remarks": "请尽快发货"
}
```

**字段验证**:
- `items`: 必填，数组类型，至少包含一个商品
- `items[].productId`: 必填，商品 ID
- `items[].quantity`: 必填，数量 > 0
- `items[].price`: 必填，单价 > 0
- `guestInfo.phone`: 游客订单必填
- `shippingInfo`: 可选，简单地址格式

**响应**:
```json
{
  "code": 201,
  "message": "Order created successfully",
  "data": {
    "id": "cmjbbtyw30000vf8g6bbietki",
    "customer": {
      "name": "张三",
      "email": "guest@example.com",
      "phone": "+86-13800138000",
      "company": "测试公司",
      "isGuest": true
    },
    "address": null,             // 简单地址格式不创建详细地址记录
    "amount": {
      "total": 2598.00,
      "currency": "AUD"
    },
    "items": [
      {
        "product": {
          "id": "clx1234567892",
          "name": "iPhone 15",
          "image": "https://example.com/image1.jpg"
        },
        "quantity": 2,
        "unitPrice": 1299.00,
        "subtotal": 2598.00
      }
    ],
    "status": "PENDING",
    "timestamps": {
      "created": "2025-12-18T10:00:00.000Z",
      "updated": "2025-12-18T10:00:00.000Z"
    },
    "remarks": "请尽快发货"
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": true
}
```

---

### 🔥 购物车结算（推荐使用 - 结构化地址）

**POST** `/orders/checkout`

**认证**: Optional (支持游客和登录用户)

**请求头**:
```
X-Guest-ID: <guest-session-id>  // 游客必填
```

**功能**:
- 从购物车直接结算创建订单
- 自动计算总金额
- 支持完整结构化地址
- 自动创建 `OrderAddress` 记录
- 使用 Google Maps 格式化地址

**请求体**:
```json
{
  "guestInfo": {                 // 游客必填，登录用户可省略
    "name": "李四",
    "email": "guest@example.com",
    "phone": "+86-13900139000",
    "company": "测试公司"
  },
  "shippingAddress": {           // 结构化地址信息
    "addressLine1": "123 Main Street",
    "addressLine2": "Apt 4B",    // 可选
    "city": "Sydney",
    "state": "NSW",
    "postalCode": "2000",
    "country": "Australia",
    "countryCode": "AU",
    "district": "Sydney CBD",    // 可选
    "placeId": "ChIJrTLr-GyuEmsRBfyf1GDH_oQ"  // 可选，Google Places ID
  },
  "remarks": "请包装仔细"
}
```

**地址验证规则**:
- `addressLine1`: 必填
- `city`: 必填
- `country`: 必填
- 其他字段: 可选

**响应**:
```json
{
  "code": 201,
  "message": "Order created successfully with optimized structure",
  "data": {
    "id": "cmjbbtyw30000vf8g6bbietki",
    "customer": {
      "name": "李四",
      "email": "guest@example.com",
      "phone": "+86-13900139000",
      "company": "测试公司",
      "isGuest": true
    },
    "address": {
      "addressLine1": "123 Main Street",
      "addressLine2": "Apt 4B",
      "city": "Sydney",
      "state": "NSW",
      "postalCode": "2000",
      "country": "Australia",
      "countryCode": "AU",
      "fullAddress": "123 Main Street, Apt 4B, Sydney NSW 2000, Australia"
    },
    "amount": {
      "total": 2598.00,
      "currency": "AUD"
    },
    "items": [
      {
        "product": {
          "id": "clx1234567892",
          "name": "iPhone 15",
          "image": "https://example.com/image1.jpg"
        },
        "quantity": 2,
        "unitPrice": 1299.00,
        "subtotal": 2598.00
      }
    ],
    "status": "PENDING",
    "timestamps": {
      "created": "2025-12-18T10:00:00.000Z",
      "updated": "2025-12-18T10:00:00.000Z"
    },
    "remarks": "请包装仔细"
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": true
}
```

**注意**:
- 不需要提供 `items` 字段（从购物车获取）
- 不需要提供 `totalAmount` 字段（系统自动计算）
- 只结算购物车中 `selected=true` 的商品
- 创建订单后会创建 `OrderAddress` 记录用于物流管理

---

### 获取用户订单列表

**GET** `/orders/user`

**认证**: Required (仅登录用户)

**请求头**:
```
Authorization: Bearer <token>
```

**查询参数**:
- `pageNum` (可选): 页码，默认 1
- `pageSize` (可选): 每页数量，默认 10
- `status` (可选): 订单状态筛选

**响应**:
```json
{
  "code": 200,
  "message": "Success",
  "data": {
    "list": [
      {
        "id": "cmjbbtyw30000vf8g6bbietki",
        "customer": {
          "name": "李四",
          "email": "user@example.com",
          "phone": "+86-13900139000",
          "isGuest": false
        },
        "amount": {
          "total": 2598.00,
          "currency": "AUD"
        },
        "status": "PENDING",
        "timestamps": {
          "created": "2025-12-18T10:00:00.000Z",
          "updated": "2025-12-18T10:00:00.000Z"
        }
      }
    ],
    "total": 1,
    "pageNum": 1,
    "pageSize": 10,
    "totalPages": 1
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": true
}
```

---

### 获取订单详情

**GET** `/orders/:id`

**认证**: Required (仅登录用户)

**权限**: 用户只能查看自己的订单

**请求头**:
```
Authorization: Bearer <token>
```

**响应**: 返回完整的 `OrderResponseDTO` 格式

---

### 取消订单

**PUT** `/orders/:id/cancel`

**认证**: Optional (支持游客和登录用户)

**请求头**:
```
X-Guest-ID: <guest-session-id>  // 游客必填
Authorization: Bearer <token>    // 登录用户必填
```

**权限验证**:
- 登录用户: 只能取消自己的订单
- 游客: 通过 X-Guest-ID 验证订单归属（解析 metadata.guestId）

**限制**: 只能取消 `PENDING` 状态的订单

**请求体**:
```json
{
  "reason": "不想要了"           // 可选
}
```

**响应**:
```json
{
  "code": 200,
  "message": "Order cancelled successfully",
  "data": {
    "orderId": "cmjbbtyw30000vf8g6bbietki",
    "orderNumber": "ORD17660554764519925",
    "status": "CANCELLED",
    "cancelledAt": "2025-12-18T11:00:00.000Z",
    "reason": "不想要了"
  },
  "timestamp": "2025-12-18T11:00:00.000Z",
  "success": true
}
```

---

## 游客端点

### 游客订单列表

**GET** `/orders/guest/orders`

**认证**: Optional (推荐使用 X-Guest-ID)

**请求头**:
```
X-Guest-ID: <guest-session-id>  // 必填
```

**功能**: 基于 X-Guest-ID 获取该游客的所有订单

**查询参数**:
- `pageNum` (可选): 页码，默认 1
- `pageSize` (可选): 每页数量，默认 10
- `status` (可选): 订单状态筛选

**过滤逻辑**:
1. 查询所有 `userId=null` 的订单
2. 解析每个订单的 `metadata.guestId`
3. 只返回 `guestId` 与请求头 `X-Guest-ID` 匹配的订单

**响应**:
```json
{
  "code": 200,
  "message": "Success",
  "data": {
    "list": [
      {
        "id": "cmjbbtyw30000vf8g6bbietki",
        "customer": {
          "name": "李四",
          "email": "guest@example.com",
          "phone": "+86-13900139000",
          "isGuest": true
        },
        "amount": {
          "total": 2598.00,
          "currency": "AUD"
        },
        "status": "PENDING"
      }
    ],
    "total": 1,
    "pageNum": 1,
    "pageSize": 10,
    "totalPages": 1
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": true
}
```

---

### 游客订单详情

**GET** `/orders/guest/orders/:id`

**认证**: Optional

**请求头**:
```
X-Guest-ID: <guest-session-id>  // 必填
```

**权限验证**:
1. 验证订单 `userId=null`（游客订单）
2. 解析订单 `metadata.guestId`
3. 验证 `guestId` 与请求头 `X-Guest-ID` 匹配

**响应**: 返回完整的 `OrderResponseDTO` 格式

---

### 游客订单查询

**GET** `/orders/guest/query`

**认证**: None (无需认证)

**功能**: 游客通过邮箱、电话或订单号查询自己的订单

**查询参数** (至少提供一个):
- `email`: 游客邮箱
- `phone`: 游客电话
- `orderNo`: 订单号

**请求示例**:
```
GET /orders/guest/query?email=guest@example.com&phone=+86-13800138000
```

**响应**:
```json
{
  "code": 200,
  "message": "Guest orders retrieved successfully",
  "data": [
    {
      "id": "cmjbbtyw30000vf8g6bbietki",
      "orderNo": "ORD17660554764519925",
      "customer": {
        "name": "李四",
        "email": "guest@example.com",
        "phone": "+86-13900139000",
        "isGuest": true
      },
      "amount": {
        "total": 2598.00,
        "currency": "AUD"
      },
      "items": [
        {
          "product": {
            "id": "clx1234567892",
            "name": "iPhone 15"
          },
          "quantity": 2,
          "unitPrice": 1299.00,
          "subtotal": 2598.00
        }
      ],
      "status": "PAID",
      "timestamps": {
        "created": "2025-12-18T10:00:00.000Z",
        "updated": "2025-12-18T10:00:00.000Z"
      }
    }
  ],
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": true
}
```

**注意**:
- 最多返回 10 条记录
- 按创建时间倒序排列
- 包含完整的订单项信息

---

## 管理员端点

所有管理员端点使用 `/admin` 前缀，需要管理员权限。

### 获取所有订单

**GET** `/orders/admin`

**认证**: Required + Admin

**请求头**:
```
Authorization: Bearer <admin-token>
```

**查询参数**:
- `pageNum` (可选): 页码，默认 1
- `pageSize` (可选): 每页数量，默认 10
- `status` (可选): 订单状态筛选
- `userId` (可选): 用户 ID 筛选
- `orderNo` (可选): 订单号模糊搜索

**响应**:
```json
{
  "code": 200,
  "message": "Success",
  "data": {
    "list": [
      {
        "id": "cmjbbtyw30000vf8g6bbietki",
        "orderNo": "ORD17660554764519925",
        "customer": {
          "name": "李四",
          "email": "guest@example.com",
          "phone": "+86-13900139000",
          "isGuest": true
        },
        "address": {
          "addressLine1": "123 Main Street",
          "addressLine2": "Apt 4B",
          "city": "Sydney",
          "state": "NSW",
          "postalCode": "2000",
          "country": "Australia",
          "countryCode": "AU",
          "fullAddress": "123 Main Street, Apt 4B, Sydney NSW 2000, Australia"
        },
        "amount": {
          "total": 2598.00,
          "currency": "AUD"
        },
        "items": [
          {
            "product": {
              "id": "clx1234567892",
              "name": "iPhone 15",
              "image": "https://example.com/image1.jpg"
            },
            "quantity": 2,
            "unitPrice": 1299.00,
            "subtotal": 2598.00
          }
        ],
        "status": "PENDING",
        "timestamps": {
          "created": "2025-12-18T10:00:00.000Z",
          "updated": "2025-12-18T10:00:00.000Z"
        }
      }
    ],
    "total": 1,
    "pageNum": 1,
    "pageSize": 10,
    "totalPages": 1
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": true
}
```

---

### 获取订单详情

**GET** `/orders/admin/:id`

**认证**: Required + Admin

**请求头**:
```
Authorization: Bearer <admin-token>
```

**路径参数**:
- `id` (必填): 订单 ID

**权限**: 管理员可以查看所有订单的详情（不受用户权限限制）

**响应**: 返回完整的 `OrderResponseDTO` 格式
```json
{
  "code": 200,
  "message": "Success",
  "data": {
    "id": "cmjbbtyw30000vf8g6bbietki",
    "orderNo": "ORD17660554764519925",
    "customer": {
      "name": "李四",
      "email": "guest@example.com",
      "phone": "+86-13900139000",
      "company": "测试公司",
      "isGuest": true
    },
    "address": {
      "addressLine1": "123 Main Street",
      "addressLine2": "Apt 4B",
      "city": "Sydney",
      "state": "NSW",
      "postalCode": "2000",
      "country": "Australia",
      "countryCode": "AU",
      "fullAddress": "123 Main Street, Apt 4B, Sydney NSW 2000, Australia",
      "district": "Sydney CBD"
    },
    "amount": {
      "total": 2598.00,
      "currency": "AUD"
    },
    "items": [
      {
        "product": {
          "id": "clx1234567892",
          "name": "iPhone 15",
          "image": "https://example.com/image1.jpg"
        },
        "quantity": 2,
        "unitPrice": 1299.00,
        "subtotal": 2598.00
      }
    ],
    "status": "PENDING",
    "timestamps": {
      "created": "2025-12-18T10:00:00.000Z",
      "updated": "2025-12-18T10:00:00.000Z"
    },
    "remarks": "请包装仔细",
    "metadata": {
      "trackingNumber": "SF1234567890",
      "carrier": "顺丰速运",
      "shippingNotes": "轻拿轻放",
      "deliveryNotes": "放前台",
      "shippedAt": "2026-02-09T10:30:00.000Z",
      "confirmedAt": "2026-02-10T08:15:00.000Z"
    }
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": true
}
```

**注意**:
- 与用户端点 `GET /orders/:id` 不同，此接口不受订单归属限制（仍需 Admin）
- 管理员可以查看任何订单的完整详情
- 使用 `OrderTransformer.transform()` 标准化响应格式
- 包含完整的订单项、地址和客户信息
- `metadata` 为安全解析后的对象；解析失败或无值时返回空对象 `{}`
- 管理端可稳定读取字段：`trackingNumber`、`carrier`、`shippingNotes`、`deliveryNotes`、`shippedAt`、`confirmedAt`
- 鉴权/权限失败场景统一返回 HTTP 200，具体业务错误码通过 `body.code` 表达（401/403）

---

### 管理员发货

**PUT** `/orders/admin/:id/ship`

**认证**: Required + Admin

**限制**: 只能发货 `CONFIRMED` 状态的订单

**错误响应**:
```json
{
  "code": 400,
  "message": "Only CONFIRMED orders can be shipped",
  "timestamp": "2025-12-18T15:00:00.000Z",
  "success": false
}
```

**请求体**:
```json
{
  "trackingNumber": "SF1234567890",    // 快递单号（可选）
  "carrier": "顺丰快递",                // 快递公司（可选）
  "notes": "已发货，请注意查收"         // 备注信息（可选）
}
```

**响应**:
```json
{
  "code": 200,
  "message": "Order shipped successfully",
  "data": {
    "id": "cmjbbtyw30000vf8g6bbietki",
    "orderNo": "ORD17660554764519925",
    "status": "SHIPPED",
    "shippedAt": "2025-12-18T15:00:00.000Z",
    "timestamps": {
      "created": "2025-12-18T10:00:00.000Z",
      "updated": "2025-12-18T15:00:00.000Z"
    },
    "metadata": {
      "trackingNumber": "SF1234567890",
      "carrier": "顺丰快递",
      "shippingNotes": "已发货，请注意查收",
      "shippedBy": "admin-user-id",
      "shippedAt": "2025-12-18T15:00:00.000Z"
    }
  },
  "timestamp": "2025-12-18T15:00:00.000Z",
  "success": true
}
```

**注意**:
- 只有 `CONFIRMED` 状态的订单可以发货（`PAID` 状态需先通过支付 Webhook 自动流转到 `CONFIRMED`）
- `trackingNumber` 存储在 `metadata` 对象中
- `carrier` 存储在 `metadata` 对象中
- `shippingNotes` 存储在 `metadata` 对象中
- 前端可通过 `data.metadata.trackingNumber` 获取快递单号

---

### 补充/修改物流信息

**PATCH** `/orders/admin/:id/shipping-info`

**认证**: Required + Admin

**描述**: 更新已发货订单的物流信息（物流单号、物流公司、发货备注）。支持部分更新。

**路径参数**:
| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| id | string | 是 | 订单ID |

**请求头**:
| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| Authorization | string | 是 | Bearer Token |
| Content-Type | string | 是 | application/json |

**请求体**:
```json
{
  "trackingNumber": "SF1234567890",    // 物流单号（可选）
  "carrier": "顺丰速运",                // 物流公司（可选）
  "notes": "轻拿轻放"                  // 发货备注（可选）
}
```

**请求示例**:
```bash
# 补充完整物流信息
curl -X PATCH "http://localhost:3000/orders/admin/{id}/shipping-info" \
  -H "Authorization: Bearer {token}" \
  -H "Content-Type: application/json" \
  -d '{"trackingNumber": "SF1234567890", "carrier": "顺丰速运", "notes": "轻拿轻放"}'

# 只修改物流单号
curl -X PATCH "http://localhost:3000/orders/admin/{id}/shipping-info" \
  -H "Authorization: Bearer {token}" \
  -H "Content-Type: application/json" \
  -d '{"trackingNumber": "YT9876543210"}'
```

**限制**:
- 只有 `SHIPPED` 状态的订单可以修改
- `DELIVERED` 状态的订单不允许修改

**错误响应**:
```json
{
  "code": 400,
  "message": "Only SHIPPED orders can update shipping info",
  "timestamp": "2026-02-09T10:00:00.000Z",
  "success": false
}
```

**响应**:
```json
{
  "code": 200,
  "message": "Shipping info updated successfully",
  "data": {
    "id": "cmjbbtyw30000vf8g6bbietki",
    "orderNo": "ORD17660554764519925",
    "status": "SHIPPED",
    "metadata": {
      "trackingNumber": "SF1234567890",
      "carrier": "顺丰速运",
      "shippingNotes": "轻拿轻放"
    }
  },
  "timestamp": "2026-02-09T10:00:00.000Z",
  "success": true
}
```

**注意**:
- 支持部分更新，只修改提供的字段
- 更新后会在订单历史中记录操作
- 物流信息存储在 `metadata` 对象中
- 历史主 `action` 仍为 `SHIPPED`（不新增未约定 action），扩展语义写入 `metadata.operation = "SHIPPING_INFO_UPDATED"`
- 同时写入 `metadata.reasonCode = "ORDER_SHIPPING_INFO_UPDATED"` 供前端本地化展示

---

### 管理员确认收货

**PUT** `/orders/admin/:id/deliver`

**认证**: Required + Admin

**限制**: 只能确认 `SHIPPED` 状态的订单

**错误响应**:
```json
{
  "code": 400,
  "message": "Only SHIPPED orders can be marked as delivered",
  "timestamp": "2025-12-19T10:00:00.000Z",
  "success": false
}
```

**请求体**:
```json
{
  "deliveryNotes": "客户已确认收货",       // 交付备注（可选）
  "proofOfDelivery": "签收照片URL"        // 交付凭证（可选）
}
```

**响应**:
```json
{
  "code": 200,
  "message": "Order delivery confirmed successfully",
  "data": {
    "id": "cmjbbtyw30000vf8g6bbietki",
    "orderNo": "ORD17660554764519925",
    "status": "DELIVERED",
    "deliveredAt": "2025-12-19T10:00:00.000Z",
    "timestamps": {
      "created": "2025-12-18T10:00:00.000Z",
      "updated": "2025-12-19T10:00:00.000Z"
    },
    "metadata": {
      "deliveryNotes": "客户已确认收货",
      "proofOfDelivery": "签收照片URL",
      "confirmedBy": "admin-user-id",
      "confirmedAt": "2025-12-19T10:00:00.000Z"
    }
  },
  "timestamp": "2025-12-19T10:00:00.000Z",
  "success": true
}
```

**注意**:
- `deliveryNotes` 存储在 `metadata` 对象中
- `proofOfDelivery` 存储在 `metadata` 对象中
- 前端可通过 `data.metadata.deliveryNotes` 获取交付备注

---

### 更新订单状态

**PUT** `/orders/admin/:id/status`

**认证**: Required + Admin

**请求体**:
```json
{
  "status": "CONFIRMED"
}
```

**有效状态**: `PENDING`, `PAID`, `CONFIRMED`, `SHIPPED`, `DELIVERED`, `CANCELLED`

**响应**:
```json
{
  "code": 200,
  "message": "Order status updated successfully",
  "data": {
    "id": "cmjbbtyw30000vf8g6bbietki",
    "orderNo": "ORD17660554764519925",
    "status": "CONFIRMED",
    "lastStatusUpdateAt": "2025-12-18T12:00:00.000Z",
    "timestamps": {
      "created": "2025-12-18T10:00:00.000Z",
      "updated": "2025-12-18T12:00:00.000Z"
    }
  },
  "timestamp": "2025-12-18T12:00:00.000Z",
  "success": true
}
```

---

### 手动清理过期订单

**POST** `/orders/admin/cleanup-expired`

**认证**: Required + Admin

**描述**: 手动触发清理超过 15 天的 PENDING 状态订单（待付款过期订单）。

**请求头**:
| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| Authorization | string | 是 | Bearer Token |

**请求体**: 无

**响应**:
```json
{
  "code": 200,
  "message": "Cleaned up 5 expired orders",
  "data": {
    "cleaned": 5,
    "cutoffDate": "2025-01-25T00:00:00.000Z"
  },
  "timestamp": "2026-02-09T10:00:00.000Z",
  "success": true
}
```

**字段说明**:
| 参数 | 类型 | 说明 |
|------|------|------|
| cleaned | number | 清理的订单数量 |
| cutoffDate | string | 截止日期（ISO 8601 格式），超过此日期的 PENDING 订单会被清理 |

**过期规则**:
- 订单状态为 `PENDING` (待付款)
- 订单创建时间超过 15 天

**定时任务**:
- 每天凌晨 2:00 自动执行清理
- 使用 node-cron 实现
- cron 表达式: `0 2 * * *`

---

### 获取订单操作历史

**GET** `/orders/admin/:id/history`

**认证**: Required + Admin

**描述**: 根据订单ID获取该订单的所有操作历史记录。

**路径参数**:
| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| id | string | 是 | 订单ID |

**响应**:
```json
{
  "code": 200,
  "message": "Order history retrieved successfully",
  "data": [
    {
      "id": "cmjbbtyw30000vf8g6bbietki",
      "orderId": "cmjbbtyw30000vf8g6bbietki",
      "action": "SHIPPED",
      "reasonCode": "ORDER_SHIPPING_INFO_UPDATED",
      "operator": {
        "id": "admin-id-123",
        "username": "admin",
        "nickname": "管理员"
      },
      "notes": "物流信息已更新",
      "metadata": {
        "operation": "SHIPPING_INFO_UPDATED",
        "reasonCode": "ORDER_SHIPPING_INFO_UPDATED",
        "trackingNumber": "SF1234567890",
        "carrier": "顺丰速运",
        "shippingNotes": "轻拿轻放"
      },
      "createdAt": "2026-02-09T10:30:00.000Z"
    },
    {
      "id": "cmjbbtyw30000vf8g6bbietkj",
      "orderId": "cmjbbtyw30000vf8g6bbietki",
      "action": "CONFIRMED",
      "reasonCode": "ORDER_AUTO_CONFIRMED_AFTER_PAYMENT",
      "operator": {
        "id": "admin-id-123",
        "username": "admin",
        "nickname": "管理员"
      },
      "notes": "支付成功后系统自动确认订单",
      "metadata": {
        "fromStatus": "PAID",
        "toStatus": "CONFIRMED",
        "changedBy": "system",
        "source": "STRIPE_WEBHOOK",
        "reasonCode": "ORDER_AUTO_CONFIRMED_AFTER_PAYMENT"
      },
      "createdAt": "2026-02-09T09:00:00.000Z"
    },
    {
      "id": "cmjbbtyw30000vf8g6bbietkk",
      "orderId": "cmjbbtyw30000vf8g6bbietki",
      "action": "PAID",
      "reasonCode": "PAYMENT_STRIPE_SUCCEEDED",
      "operator": null,
      "notes": "支付成功",
      "metadata": {
        "fromStatus": "PENDING",
        "toStatus": "PAID",
        "changedBy": "system",
        "source": "STRIPE_WEBHOOK",
        "reasonCode": "PAYMENT_STRIPE_SUCCEEDED"
      },
      "createdAt": "2026-02-09T08:30:00.000Z"
    },
    {
      "id": "cmjbbtyw30000vf8g6bbietkl",
      "orderId": "cmjbbtyw30000vf8g6bbietki",
      "action": "CREATED",
      "operator": null,
      "notes": "订单创建",
      "metadata": null,
      "createdAt": "2026-02-09T08:00:00.000Z"
    }
  ],
  "timestamp": "2026-02-09T10:30:00.000Z",
  "success": true
}
```

**action 枚举值**:
| 值 | 说明 |
|------|------|
| CREATED | 订单创建 |
| PAID | 订单支付 |
| CONFIRMED | 订单确认 |
| SHIPPED | 订单发货 |
| DELIVERED | 订单收货 |
| CANCELLED | 订单取消 |

**字段说明**:
- `operator`: 操作员信息，系统自动操作（如支付）时为 `null`
- `notes`: 操作备注，包含操作的详细信息
- `reasonCode`: 可本地化原因码（可选，建议前端优先使用）
- `metadata`: 结构化对象（`null` 表示无附加信息），用于承载扩展语义，如 `operation`、`source`、状态流转上下文
- 历史主 `action` 返回稳定集合：`CREATED`、`PAID`、`CONFIRMED`、`SHIPPED`、`DELIVERED`、`CANCELLED`
- shipping info 更新不新增 action，而是通过 `metadata.operation = SHIPPING_INFO_UPDATED` + `reasonCode = ORDER_SHIPPING_INFO_UPDATED` 表达
- Stripe webhook 相关记录使用结构化字段：`metadata.source = STRIPE_WEBHOOK`，并配套 `reasonCode`
- 历史读取会兼容旧数据：若旧记录 action 为 `SHIPPING_INFO_UPDATED`，接口返回时会归一化为 `SHIPPED`
- 返回记录按时间倒序排列（最新的操作在前）

---

### 获取订单统计

**GET** `/orders/admin/stats/all`

**认证**: Required + Admin

**查询参数**:
- `userId` (可选): 指定用户的统计

**响应**:
```json
{
  "code": 200,
  "message": "Success",
  "data": {
    "totalOrders": 1250,
    "pendingOrders": 85,
    "paidOrders": 320,
    "shippedOrders": 650,
    "deliveredOrders": 180,
    "cancelledOrders": 15,
    "totalRevenue": 285000.50,
    "averageOrderValue": 228.00
  },
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": true
}
```

---

## 端点汇总

### 用户端点

| 方法 | 路径 | 认证 | 说明 |
|------|------|------|------|
| POST | `/orders` | Optional | 创建订单（简单地址格式） |
| POST | `/orders/checkout` | Optional | 购物车结算（结构化地址） |
| GET | `/orders/user` | Required | 获取用户订单列表 |
| GET | `/orders/:id` | Required | 获取订单详情 |
| PUT | `/orders/:id/cancel` | Optional | 取消订单 |

### 游客端点

| 方法 | 路径 | 认证 | 说明 |
|------|------|------|------|
| GET | `/orders/guest/orders` | X-Guest-ID | 游客订单列表 |
| GET | `/orders/guest/orders/:id` | X-Guest-ID | 游客订单详情 |
| GET | `/orders/guest/query` | None | 游客订单查询（邮箱/电话/订单号） |

### 管理员端点

| 方法 | 路径 | 认证 | 说明 |
|------|------|------|------|
| GET | `/orders/admin` | Admin | 获取所有订单 |
| GET | `/orders/admin/:id` | Admin | 获取订单详情 |
| GET | `/orders/admin/:id/history` | Admin | 获取订单操作历史 |
| POST | `/orders/admin/cleanup-expired` | Admin | 手动清理过期订单 |
| PUT | `/orders/admin/:id/ship` | Admin | 管理员发货 |
| PATCH | `/orders/admin/:id/shipping-info` | Admin | 补充/修改物流信息 |
| PUT | `/orders/admin/:id/deliver` | Admin | 管理员确认收货 |
| PUT | `/orders/admin/:id/status` | Admin | 更新订单状态 |
| GET | `/orders/admin/stats/all` | Admin | 获取订单统计 |

---

## 错误响应

所有错误响应遵循统一格式:

```json
{
  "code": 400,
  "message": "Validation Error",
  "errors": [
    "Order items are required"
  ],
  "timestamp": "2025-12-18T10:00:00.000Z",
  "success": false
}
```

**常见错误码**:
- `400`: 请求参数错误
- `401`: 未授权（缺少 token，HTTP 状态码仍为 200，见 `body.code`）
- `403`: 禁止访问（权限不足，HTTP 状态码仍为 200，见 `body.code`）
- `404`: 订单不存在
- `500`: 服务器错误

---

## 最佳实践

### 1. 前端集成建议

**游客识别**:
```typescript
// 生成或读取游客 ID
let guestId = localStorage.getItem('guest-id')
if (!guestId) {
  guestId = generateGuestId()
  localStorage.setItem('guest-id', guestId)
}

// 所有请求添加 X-Guest-ID 头
axios.defaults.headers.common['X-Guest-ID'] = guestId
```

**创建订单**:
```typescript
// 登录用户
const response = await axios.post('/orders', {
  items: cartItems,
  shippingInfo: {...}
}, {
  headers: { Authorization: `Bearer ${token}` }
})

// 游客
const response = await axios.post('/orders', {
  items: cartItems,
  guestInfo: { name, email, phone },
  shippingInfo: {...}
}, {
  headers: { 'X-Guest-ID': guestId }
})
```

### 2. 订单状态流转

```
PENDING (待支付)
  ↓ (支付成功)
PAID (已支付)
  ↓ (支付 Webhook 自动流转)
CONFIRMED (已确认)
  ↓ (管理员发货)
SHIPPED (已发货)
  ↓ (管理员确认收货)
DELIVERED (已送达)

PENDING → CANCELLED (用户取消)
```

**重要变更**:
- 支付成功后，订单状态从 `PAID` 自动流转到 `CONFIRMED`（通过 Stripe Webhook）
- 只有 `CONFIRMED` 状态的订单可以发货（之前是 `PAID` 状态可发货）
- 发货前必须等待 Webhook 处理完成（通常 2-5 秒）

### 3. 游客订单管理

**游客订单查询流程**:
1. 下单后保存订单号到本地存储
2. 使用 X-Guest-ID 查看订单列表
3. 使用邮箱/电话/订单号查询订单

---

## 更新日志

**2025-02-08**:
- ✅ 添加 `GET /orders/admin/:id` 管理员订单详情接口
- ✅ 添加 `orderNo` 字段到 `OrderResponseDTO` 接口定义
- ✅ 更新管理员订单列表响应：添加完整 `items` 和 `address` 字段
- ✅ 更新发货响应：明确 `trackingNumber` 在 `metadata` 对象中
- ✅ 更新确认收货响应：明确 `deliveryNotes` 在 `metadata` 对象中
- ✅ 更新状态更新响应：添加 `orderNo` 和完整 `timestamps` 字段
- ✅ 添加 `district` 字段到地址结构
- ✅ 验证与实际后端实现 `OrderTransformer` 一致

**2025-02-04**:
- ✅ 修正创建订单字段名: `list` → `items`
- ✅ 修正管理员路径: 添加 `/admin` 前缀
- ✅ 更新响应格式以反映 `OrderTransformer` 标准化
- ✅ 统一发货字段名: `carrier`, `notes`
- ✅ 统一确认收货字段名: `deliveryNotes`
- ✅ 添加详细地址验证规则
- ✅ 添加权限验证逻辑说明

**文档版本**: v2.4
**验证状态**: ✅ 已验证与代码一致 (BACKEND-006 + BACKEND-007)

**2026-02-09**:
- ✅ 新增 `PATCH /orders/admin/:id/shipping-info` - 补充/修改物流信息接口
- ✅ 支持部分更新物流单号、物流公司、发货备注
- ✅ 限制：只有 SHIPPED 状态订单可修改，DELIVERED 状态不可修改
- ✅ 新增 `POST /orders/admin/cleanup-expired` - 手动清理过期订单接口
- ✅ 新增 `GET /orders/admin/:id/history` - 获取订单操作历史接口
- ✅ 订单历史支持 action 枚举：CREATED, PAID, CONFIRMED, SHIPPED, DELIVERED, CANCELLED
- ✅ 订单历史包含操作员信息、备注和元数据
- ✅ 过期订单自动清理功能（15 天 PENDING 状态订单）
- ✅ 定时任务：每天凌晨 2:00 自动执行清理
- ✅ 更新订单状态流转：明确 PAID → CONFIRMED 的自动流转
- ✅ 更新发货接口限制：只有 CONFIRMED 状态可发货
- ✅ 添加发货错误响应说明
- ✅ 添加确认收货错误响应说明
- ✅ 更新最佳实践：说明发货前需等待 Webhook 处理

**2026-02-25**:
- ✅ 管理员订单详情示例补充 `metadata` 安全回传字段：`trackingNumber`、`carrier`、`shippingNotes`、`deliveryNotes`、`shippedAt`、`confirmedAt`
- ✅ 明确 `metadata` 解析失败/缺失时返回空对象 `{}`
- ✅ 明确历史主 `action` 为稳定集合，shipping info 更新通过 `metadata.operation` + `reasonCode` 表达
- ✅ 明确历史回读兼容：旧 `SHIPPING_INFO_UPDATED` 归一化为 `SHIPPED`
- ✅ 明确 webhook 历史结构化字段：`metadata.source` + `reasonCode`
- ✅ 明确权限语义：HTTP 200 + `body.code`（401/403）
