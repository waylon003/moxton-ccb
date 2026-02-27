## 🛍️ 商品 API

### 获取商品列表

**GET** `/products`

**查询参数**:
- `pageNum` (可选): 页码，默认1
- `pageSize` (可选): 每页数量，默认10
- `keyword` (可选): 搜索关键词
- `categoryId` (可选): 分类ID
- `minPrice` (可选): 最低价格
- `maxPrice` (可选): 最高价格
- `status` (可选): 商品状态(1:上架, 0:下架)
- `sortBy` (可选): 排序字段，默认`createdAt`，支持`createdAt`, `price`, `name`, `stock`
- `sortOrder` (可选): 排序方向，默认`desc`，支持`asc`, `desc`
- `includeDisabledCategories` (可选): 是否包含禁用分类下的商品 (false:仅启用分类, true:包含禁用分类)，默认false，仅管理员可使用true

**权限说明**:
- 默认行为 (false或未设置): 仅返回启用分类下的商品，适用于Nuxt商城前台
- 管理员权限(true): 需要管理员角色，返回所有分类下的商品，适用于Soybin Admin后台管理

**排序功能 (v1.1.0 新增)**:
- 💰 **价格排序**: `sortBy=price&sortOrder=asc` 按价格从低到高
- 📝 **名称排序**: `sortBy=name&sortOrder=asc` 按名称A-Z
- 📦 **库存排序**: `sortBy=stock&sortOrder=desc` 按库存从高到低
- 🕒 **创建时间排序**: `sortBy=createdAt&sortOrder=desc` (默认，按创建时间降序)

**排序示例**:
```
GET /products?sortBy=price&sortOrder=asc
GET /products?sortBy=name&sortOrder=desc
GET /products?sortBy=stock&sortOrder=desc
GET /products?categoryId=cat123&sortBy=price&sortOrder=asc
```

**示例请求**:
```
GET /products?pageNum=1&pageSize=10&categoryId=clt123456789&minPrice=100&maxPrice=1000&keyword=传感器
GET /products?pageNum=1&pageSize=10&includeDisabledCategories=true  // 管理员专用
```

**响应**:
```json
{
  "code": 200,
  "message": "Products retrieved successfully",
  "data": {
    "list": [
      {
        "id": "clt123456789",
        "name": "智能温度传感器",
        "description": "高精度温度监测传感器",
        "content": "<h1>智能温度传感器产品详情</h1><p>采用高精度数字传感器，适用于各种环境监测场景。</p><ul><li>精度：±0.5℃</li><li>工作温度：-40~85℃</li><li>供电：DC 5V</li><li>通信：I2C/SPI</li></ul>",
        "price": 299.99,
        "originalPrice": 399.99,
        "stock": 100,
        "images": ["https://example.com/image1.jpg", "https://example.com/image2.jpg"],
        "specifications": "{\"精度\":\"±0.5℃\",\"工作温度\":\"-40~85℃\",\"供电\":\"DC 5V\"}",
        "status": 1,
        "category": {
          "id": "clt123456788",
          "name": "智能传感器",
          "status": 1
        },
        "hasPrice": true,         // 🆕 新增：判断商品是否有价格，false=咨询商品, true=购买商品
        "tags": ["热销", "新品", "推荐"], // 🏷️ 新增：商品标签数组，无标签时为null
        "createdAt": "2025-12-03T10:00:00.000Z"
      }
    ],
    "total": 50,
    "pageNum": 1,
    "pageSize": 10,
    "totalPages": 5
  },
  "success": true
}
```

### 🔥 价格区分字段说明 (v1.4.0 新增)

#### hasPrice字段
**功能说明**: 所有商品相关API返回的数据中现在包含`hasPrice`字段，用于区分购买型商品和咨询型商品。

**字段定义**:
- `hasPrice: boolean` - `true`表示有价格商品（可购买），`false`表示无价格商品（需咨询）

**前端使用逻辑**:
```javascript
// 商品详情页按钮显示逻辑
if (product.hasPrice) {
  // 有价格商品
  <button onClick={addToCart}>立即购买</button>
  <span>价格: ¥{product.price}</span>
} else {
  // 无价格商品
  <button onClick={showConsultationForm}>立即咨询</button>
  <span>价格: 需报价</span>
}
```

**响应示例对比**:

```json
// 有价格商品
{
  "id": "product-001",
  "name": "智能温度传感器",
  "price": 299.99,
  "hasPrice": true,
  "status": 1
}

// 无价格商品（咨询商品）
{
  "id": "product-002",
  "name": "定制化工业设计",
  "price": null,
  "hasPrice": false,
  "status": 1
}
```

**适用范围**: 以下所有商品API都返回`hasPrice`字段：
- `GET /products` - 获取商品列表
- `GET /products/:id` - 获取商品详情
- `GET /products/search` - 搜索商品
- `GET /products/popular` - 获取热门商品
- `GET /products/category/:categoryId` - 根据分类获取商品
- `GET /products/admin/all` - 管理员获取所有商品

**业务场景**:
- 💳 **有价格商品**: 标准电商商品，直接在线购买
- 📞 **无价格商品**: 定制化产品、需要报价的商品、企业采购咨询
- 🔄 **价格区分**: 前端根据hasPrice显示不同按钮和价格信息
- ✨ **统一体验**: 保持一致的API响应格式

**前端集成建议**:
1. 使用`product.hasPrice`判断按钮类型
2. 有价格商品走标准购物车流程
3. 无价格商品跳转到咨询表单
4. 咨询表单使用离线订单API提交

### 🏷️ 商品标签字段说明 (v1.4.1 新增)

#### tags字段
**功能说明**: 所有商品相关API返回的数据中现在包含`tags`字段，为商品提供灵活的标签系统。

**字段定义**:
- `tags: string[] | null` - 商品标签数组，无标签时为`null`

**前端使用逻辑**:
```javascript
// 商品标签显示逻辑
const productTags = product.tags || [];
if (productTags.length > 0) {
  // 有标签，显示标签列表
  productTags.forEach(tag => {
    console.log('标签:', tag);
  });
} else {
  // 无标签，隐藏或显示空状态
  console.log('暂无标签');
}

// 创建/更新商品时的标签数据
const createProductData = {
  name: "商品名称",
  price: 199.99,
  categoryId: "category_id",
  tags: ["热销", "新品", "推荐"] // 标签数组，支持任意字符串
};
```

**支持格式**:
- **数组格式**: `["标签1", "标签2", "标签3"]`
- **逗号分隔**: `"标签1,标签2,标签3"` (自动转换)
- **空值**: `null` 或空数组
- **自动处理**: 过滤空字符串和无效内容

**适用范围**: 以下所有商品API都返回`tags`字段：
- `GET /products` - 获取商品列表
- `GET /products/admin/all` - 管理员获取所有商品
- `GET /products/:id` - 获取商品详情
- `GET /products/search` - 搜索商品
- `GET /products/popular` - 获取热门商品
- `GET /products/category/:categoryId` - 根据分类获取商品
- `POST /products` - 创建商品（支持tags字段）
- `PUT /products/:id` - 更新商品（支持tags字段）

---

### 管理员专用：获取所有商品

**GET** `/products/admin/all`

**认证**: 必需认证 + 管理员权限

**权限说明**:
- 专门为Soybean Admin管理后台设计
- 返回所有商品（包括禁用分类下的商品）
- 不受分类状态影响，完整显示商品列表

**查询参数**:
- `pageNum` (可选): 页码，默认1
- `pageSize` (可选): 每页数量，默认10
- `keyword` (可选): 搜索关键词
- `categoryId` (可选): 分类ID
- `minPrice` (可选): 最低价格
- `maxPrice` (可选): 最高价格
- `status` (可选): 商品状态(1:上架, 0:下架)

**示例请求**:
```
GET /products/admin/all?pageNum=1&pageSize=10&keyword=传感器
Authorization: Bearer <admin_token>
```

**权限检查**:
- 401 Unauthorized: 未提供token
- 403 Forbidden: 非管理员角色

### 搜索商品

**GET** `/products/search`

**查询参数**:
- `keyword` (必需): 搜索关键词
- `pageNum` (可选): 页码，默认1
- `pageSize` (可选): 每页数量，默认10
- `categoryId` (可选): 分类ID
- `minPrice` (可选): 最低价格
- `maxPrice` (可选): 最高价格

**示例请求**:
```
GET /products/search?keyword=温度传感器&categoryId=clt123456788
```

### 获取商品详情

**GET** `/products/:id`

**响应**:
```json
{
  "code": 200,
  "message": "Product retrieved successfully",
  "data": {
    "id": "clt123456789",
    "name": "智能温度传感器",
    "description": "高精度温度监测传感器，适用于各种环境监测场景",
    "content": "<h1>智能温度传感器产品详情</h1><p>采用高精度数字传感器，适用于各种环境监测场景。</p><ul><li>精度：±0.5℃</li><li>工作温度：-40~85℃</li><li>供电：DC 5V</li><li>通信：I2C/SPI</li></ul>",
    "price": 299.99,
    "originalPrice": 399.99,
    "stock": 100,
    "images": ["https://example.com/image1.jpg", "https://example.com/image2.jpg"],
    "specifications": "{\"精度\":\"±0.5℃\",\"工作温度\":\"-40~85℃\",\"供电\":\"DC 5V\"}",
    "status": 1,
    "category": {
      "id": "clt123456788",
      "name": "智能传感器"
    },
    "hasPrice": true,
    "tags": ["热销", "新品"],
    "createdAt": "2025-12-02T10:00:00.000Z",
    "updatedAt": "2025-12-02T10:00:00.000Z",
    "relatedProducts": [
      {
        "id": "clt123456790",
        "name": "智能湿度传感器",
        "price": 259.99,
        "hasPrice": true,
        "images": ["https://example.com/image3.jpg"]
      }
    ]
  },
  "success": true
}
```

### 获取热门商品

**GET** `/products/popular`

**查询参数**:
- `pageSize` (可选): 数量，默认10

**响应**:
```json
{
  "code": 200,
  "message": "Popular products retrieved successfully",
  "data": [
    {
      "id": "clt123456789",
      "name": "智能温度传感器",
      "price": 299.99,
      "hasPrice": true,
      "images": ["https://example.com/image1.jpg"],
      "category": {
        "id": "clt123456788",
        "name": "智能传感器",
        "status": 1
      }
    }
  ],
  "success": true
}
```

### 根据分类获取商品

**GET** `/products/category/:categoryId`

**认证**: Optional

**查询参数**:
- `pageNum` (可选): 页码，默认1
- `pageSize` (可选): 每页数量，默认10

### 获取相关商品

**GET** `/products/:id/related`

**认证**: Optional

**查询参数**:
- `limit` (可选): 数量，默认5

### 创建商品

**POST** `/products`

**认证**: Required

**请求体**:
```json
{
  "name": "智能温度传感器",
  "description": "高精度温度监测传感器",
  "content": "<h1>产品详情</h1><p>这里是富文本内容</p>",
  "price": 299.99,
  "originalPrice": 399.99,
  "stock": 100,
  "categoryId": "clt123456788",
  "images": ["https://example.com/image1.jpg", "https://example.com/image2.jpg"],
  "specifications": "{\"精度\":\"±0.5℃\",\"工作温度\":\"-40~85℃\"}",
  "tags": ["热销", "新品", "推荐"],
  "status": 1
}
```

**说明**:
- `price` 为 `null` 或 `0` 时创建咨询商品（`hasPrice=false`）
- `price` 大于 `0` 时创建购买商品（`hasPrice=true`）

### 更新商品

**PUT** `/products/:id`

**认证**: Required

**请求体**:
```json
{
  "name": "更新后的商品名称",
  "description": "更新后的描述",
  "content": "<h1>更新后的产品详情</h1><p>新的富文本内容</p>",
  "price": 349.99,
  "stock": 150,
  "status": 1,
  "tags": ["热销"]
}
```

**说明**:
- `price` 设置为 `null` 或空字符串可将商品转为咨询商品
- `price` 设置为大于 `0` 的数值可将商品转为购买商品

### 删除商品

**DELETE** `/products/:id`

**认证**: Required

**说明**: 使用逻辑删除，商品不会从数据库中物理删除

### 批量删除商品 🆕

**DELETE** `/products/batch`

**认证**: Required + Admin

**请求体**:
```json
{
  "productIds": ["clt123456789", "clt123456790", "clt123456791"]
}
```

**限制**: 一次最多删除20个商品

**响应**:
```json
{
  "code": 200,
  "message": "批量删除完成：成功删除2个商品，失败1个",
  "data": {
    "deleted": 2,
    "failed": ["clt123456791"],
    "total": 3
  },
  "success": true
}
```

**说明**:
- 使用逻辑删除，设置 `isDeleted=true`
- 已关联订单的商品无法删除，会返回在 `failed` 数组中

### 更新库存

**PUT** `/products/:id/stock`

**认证**: Required

**请求体**:
```json
{
  "quantity": 50
}
```

**说明**: quantity 为正数表示增加库存，为负数表示减少库存

### 批量更新库存 ✅ 已修正

**PUT** `/products/batch/stock`

**认证**: Required

**请求体**:
```json
{
  "items": [
    {
      "productId": "clt123456789",
      "quantity": 20
    },
    {
      "productId": "clt123456790",
      "quantity": -10
    }
  ]
}
```

**说明**:
- `quantity` 为正数表示增加库存，为负数表示减少库存
- 使用原子操作确保库存更新的一致性
- 如果库存不足会自动回滚操作

### 🗑️ 恢复已删除商品 🆕

**POST** `/products/:id/restore`

**认证**: Required + Admin

**权限说明**: 仅管理员可恢复已删除的商品

**响应**:
```json
{
  "code": 200,
  "message": "商品恢复成功",
  "data": {
    "id": "clt123456789",
    "name": "智能温度传感器",
    "isDeleted": false,
    "status": 1,
    "updatedAt": "2026-02-04T10:00:00.000Z"
  },
  "success": true
}
```

### 🗑️ 批量恢复商品 🆕

**POST** `/products/batch/restore`

**认证**: Required + Admin

**权限说明**: 仅管理员可批量恢复已删除的商品

**请求体**:
```json
{
  "productIds": ["clt123456789", "clt123456790", "clt123456791"]
}
```

**限制**: 一次最多恢复20个商品

**响应**:
```json
{
  "code": 200,
  "message": "批量恢复完成：成功恢复2个商品，失败0个",
  "data": {
    "restored": 2,
    "failed": [],
    "total": 2
  },
  "success": true
}
```

### 🗑️ 获取已删除商品列表 🆕

**GET** `/products/deleted`

**认证**: Required + Admin

**权限说明**: 仅管理员可查看已删除的商品

**查询参数**:
- `pageNum` (可选): 页码，默认1
- `pageSize` (可选): 每页数量，默认10
- `keyword` (可选): 搜索关键词
- `categoryId` (可选): 分类ID
- `minPrice` (可选): 最低价格
- `maxPrice` (可选): 最高价格
- `sortBy` (可选): 排序字段，默认`updatedAt`
- `sortOrder` (可选): 排序方向，默认`desc`

**说明**:
- 仅返回 `isDeleted=true` 的商品
- 默认按 `updatedAt` 降序排序（最新删除的在前）
- 支持所有商品列表的筛选和排序功能

**示例请求**:
```
GET /products/deleted?pageNum=1&pageSize=10&keyword=传感器
Authorization: Bearer <admin_token>
```

**响应**:
```json
{
  "code": 200,
  "message": "Success",
  "data": {
    "list": [
      {
        "id": "clt123456789",
        "name": "智能温度传感器",
        "description": "高精度温度监测传感器",
        "price": 299.99,
        "originalPrice": 399.99,
        "stock": 100,
        "status": 1,
        "isDeleted": true,
        "deletedAt": "2026-02-04T10:00:00.000Z",
        "images": ["https://example.com/image1.jpg"],
        "category": {
          "id": "clt123456788",
          "name": "智能传感器",
          "status": 1
        },
        "hasPrice": true,
        "tags": ["热销"],
        "updatedAt": "2026-02-04T10:00:00.000Z"
      }
    ],
    "total": 5,
    "pageNum": 1,
    "pageSize": 10,
    "totalPages": 1
  },
  "success": true
}
```

### 🏷️ 层级分类名称说明 (v1.1.2 新增)

**功能说明**: 所有商品相关的API返回的分类信息(`category`)现在包含完整的层级结构和状态信息。

**层级结构规则**:
- **一级分类**: 直接显示分类名称，如：`"电动设备"`、`"电子产品"`
- **二级分类**: 显示为`父级分类/子级分类`格式，如：`"电子产品/手机配件"`、`"智能化设备/耗材配件"`
- **多级分类**: 支持无限层级，显示为完整路径，如：`"一级分类/二级分类/三级分类"`

**分类状态管理规则**:
- **category.status**: 分类状态字段(0=禁用, 1=启用)
- **自动过滤**: 禁用分类下的商品不会出现在商品列表、搜索、热门商品等API中
- **详情访问**: 商品详情API仍可访问禁用分类下的商品，返回完整的category信息包含status=0
- **级联控制**: 分类禁用时，所有关联商品自动"下架"(不在列表中显示)，商品启用时可独立控制上架状态

**适用范围**: 以下所有商品API的返回数据中包含完整的`category`对象：
- `GET /products` - 获取商品列表
- `GET /products/admin/all` - 管理员获取所有商品
- `GET /products/:id` - 获取商品详情
- `GET /products/search` - 搜索商品
- `GET /products/popular` - 获取热门商品
- `GET /products/category/:categoryId` - 根据分类获取商品

**特殊说明**:
- 商城API (`GET /products`): 默认仅返回启用分类下的商品
- 管理员API (`GET /products/admin/all`): 返回所有分类下的商品，不受分类状态限制

**响应示例对比**:

```json
// 启用分类下的一级分类商品
{
  "id": "product-001",
  "name": "笔记本电脑",
  "category": {
    "id": "cat-001",
    "name": "电动设备",  // 一级分类，直接显示
    "status": 1  // 启用状态
  }
}

// 启用分类下的二级分类商品
{
  "id": "product-002",
  "name": "智能手机",
  "category": {
    "id": "cat-002",
    "name": "电子产品/手机配件",  // 二级分类，显示层级结构
    "status": 1  // 启用状态
  }
}

// 禁用分类下的商品（仅在商品详情中可见）
{
  "id": "product-003",
  "name": "禁用分类商品",
  "category": {
    "id": "cat-003",
    "name": "禁用测试分类",
    "status": 0  // 禁用状态，该商品不会出现在列表、搜索等API中
  }
}
```

**前端集成建议**:
- 直接显示 `category.name` 即可，无需额外处理
- 使用 `category.status` 判断商品是否可用：status=1 可正常显示，status=0 表示分类已禁用
- 如需显示面包屑导航，可以使用 `/` 分割符解析层级关系
- 分类ID仍然指向具体的子分类，可用于筛选和查询
- **状态检查**: 在显示商品前检查`category.status`，禁用分类下的商品建议显示"暂无可用"或类似提示
- **商品详情**: 即使分类禁用，商品详情API仍可访问，前端可根据category.status决定是否显示购买按钮

---

## 更新日志

### v1.4.2 (2026-02-04)
- ✅ 修正批量更新库存API参数字段名：`list` → `items`
- 🆕 新增恢复单个商品API：`POST /products/:id/restore`
- 🆕 新增批量恢复商品API：`POST /products/batch/restore`
- 🆕 新增获取已删除商品列表API：`GET /products/deleted`

### v1.4.1 (2025-12-05)
- 🏷️ 新增商品标签系统 (`tags` 字段)
- 支持JSON数组和逗号分隔字符串格式

### v1.4.0 (2025-12-05)
- 💰 新增 `hasPrice` 字段，区分购买商品和咨询商品
- 支持价格字段为 `null` 或 `0` 的咨询商品

### v1.1.2 (2025-12-03)
- 🏷️ 新增层级分类名称显示
- 📊 新增分类状态管理
- 🔄 分类状态自动过滤功能

### v1.1.0 (2025-12-02)
- 🔄 新增商品排序功能
- 📊 支持按价格、名称、库存、创建时间排序
- ⬆️⬇️ 支持升序和降序

---
