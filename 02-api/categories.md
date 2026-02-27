# 📂 Category API

---

## Table of Contents
- [Tree Structure Endpoints](#tree-structure-endpoints)
- [CRUD Operations](#crud-operations)
- [Batch Operations](#batch-operations)
- [Navigation & Hierarchy](#navigation--hierarchy)
- [Best Practices](#best-practices)

---

## Tree Structure Endpoints

### 获取分类树形结构（管理用）

**GET** `/categories/tree`

**认证**: Optional

**说明**: 返回所有分类节点（包括禁用状态），用于管理后台CRUD操作

**响应**:
```json
{
  "code": 200,
  "message": "All categories tree retrieved successfully",
  "data": [
    {
      "id": "clt123456789",                                    // 分类唯一标识 (Prisma cuid)
      "name": "IoT设备",                                       // 分类名称
      "description": "物联网智能设备",                         // 分类描述
      "parentId": null,                                        // 父分类ID (null表示根分类)
      "level": 1,                                              // 分类层级 (自动计算)
      "sort": 1,                                               // 排序权重 (数字越小越靠前)
      "status": 1,                                             // 状态 (1=启用, 0=禁用)
      "createdAt": "2025-12-03T10:00:00.000Z",                // 创建时间
      "updatedAt": "2025-12-03T10:00:00.000Z",                // 更新时间
      "productCount": 15,                                      // 关联商品数量 (含子分类商品)
      "children": [                                            // 子分类数组
        {
          "id": "clt123456790",
          "name": "智能传感器",
          "description": "各种智能传感器设备",
          "parentId": "clt123456789",
          "level": 2,
          "sort": 1,
          "status": 0,                                         // 禁用状态的分类也会返回
          "createdAt": "2025-12-03T10:00:00.000Z",
          "updatedAt": "2025-12-03T10:00:00.000Z",
          "productCount": 8,
          "children": []
        }
      ]
    }
  ],
  "timestamp": "2025-12-03T10:00:00.000Z",
  "success": true
}
```

---

### 获取分类树形结构（前端显示用）

**GET** `/categories/tree/active`

**认证**: Optional

**说明**: 仅返回启用状态的分类节点，用于前端商城显示/列表选择

**响应**:
```json
{
  "code": 200,
  "message": "Active categories tree retrieved successfully",
  "data": [
    {
      "id": "clt123456789",
      "name": "IoT设备",
      "description": "物联网智能设备",
      "parentId": null,
      "level": 1,
      "sort": 1,
      "status": 1,                                             // 仅返回启用状态的分类
      "createdAt": "2025-12-03T10:00:00.000Z",
      "updatedAt": "2025-12-03T10:00:00.000Z",
      "productCount": 7,                                       // 仅统计启用状态的商品
      "children": []                                           // 仅包含启用状态的子分类
    }
  ],
  "timestamp": "2025-12-03T10:00:00.000Z",
  "success": true
}
```

---

### 获取分类及其商品数量

**GET** `/categories/with-count`

**认证**: Optional

**说明**: 获取所有启用状态的分类及其关联的商品数量（扁平结构，非树形）

**响应**:
```json
{
  "code": 200,
  "message": "Categories with product count retrieved successfully",
  "data": [
    {
      "id": "clt123456789",                                    // 分类唯一标识
      "name": "IoT设备",                                       // 分类名称
      "description": "物联网智能设备",                         // 分类描述
      "parentId": null,                                        // 父分类ID
      "level": 1,                                              // 分类层级
      "sort": 1,                                               // 排序权重
      "status": 1,                                             // 状态 (1=启用, 0=禁用)
      "productCount": 15,                                      // 关联商品数量
      "createdAt": "2025-12-03T10:00:00.000Z",                // 创建时间
      "updatedAt": "2025-12-03T10:00:00.000Z"                 // 更新时间
    }
  ],
  "timestamp": "2025-12-03T10:00:00.000Z",
  "success": true
}
```

**注意**: `productCount` 仅统计启用状态的商品

---

## CRUD Operations

### 获取分类详情

**GET** `/categories/:id`

**认证**: Optional

**路径参数**:
- `id`: 分类ID (string, required)

**响应**:
```json
{
  "code": 200,
  "message": "Category retrieved successfully",
  "data": {
    "id": "clt123456789",
    "name": "IoT设备",
    "description": "物联网智能设备",
    "parentId": null,
    "level": 1,
    "sort": 1,
    "status": 1,
    "createdAt": "2025-12-03T10:00:00.000Z",
    "updatedAt": "2025-12-03T10:00:00.000Z",
    "children": [                                              // 直接子分类列表
      {
        "id": "clt123456790",
        "name": "智能传感器",
        "description": "各种智能传感器设备",
        "parentId": "clt123456789",
        "level": 2,
        "sort": 1,
        "status": 1,
        "createdAt": "2025-12-03T10:00:00.000Z",
        "updatedAt": "2025-12-03T10:00:00.000Z"
      }
    ]
  },
  "timestamp": "2025-12-03T10:00:00.000Z",
  "success": true
}
```

**错误响应**:
- `404`: 分类不存在

---

### 创建分类

**POST** `/categories`

**认证**: Required

**请求体**:
```json
{
  "name": "智能传感器",                                        // 分类名称 (string, required)
  "description": "各种智能传感器设备",                         // 分类描述 (string, optional)
  "parentId": "clt123456789",                                // 父分类ID (string, optional, null表示根分类)
  "sort": 1                                                   // 排序权重 (number, optional, default=0)
}
```

**自动计算规则**:
- `level`: 根据 `parentId` 自动计算
  - 根分类（无 `parentId`）: `level = 1`
  - 子分类: `level = 父分类.level + 1`
- `status`: 默认为 `1` (启用)

**响应**:
```json
{
  "code": 200,
  "message": "Category created successfully",
  "data": {
    "id": "clt123456790",                                    // 新创建的分类ID
    "name": "智能传感器",
    "description": "各种智能传感器设备",
    "parentId": "clt123456789",
    "level": 2,                                              // 自动计算
    "sort": 1,
    "status": 1,                                             // 默认启用
    "createdAt": "2025-12-03T10:00:00.000Z",
    "updatedAt": "2025-12-03T10:00:00.000Z"
  },
  "timestamp": "2025-12-03T10:00:00.000Z",
  "success": true
}
```

**验证规则**:
- `name`: 必填，全局唯一
- `parentId`: 如果提供，必须存在
- 不能创建循环引用（通过移动操作检测）

**错误响应**:
- `500`: 分类名称已存在
- `404`: 父分类不存在

---

### 更新分类

**PUT** `/categories/:id`

**认证**: Required

**路径参数**:
- `id`: 分类ID (string, required)

**请求体**:
```json
{
  "name": "更新后的分类名称",                                 // 分类名称 (string, optional)
  "description": "更新后的描述",                              // 分类描述 (string, optional)
  "sort": 2,                                                  // 排序权重 (number, optional)
  "status": 1,                                                // 状态 (number, optional, 0=禁用, 1=启用)
  "parentId": "clt123456791"                                 // 父分类ID (string, optional)
}
```

**级联更新规则**:
- 更新 `parentId`: 自动重新计算该分类及其所有子分类的 `level`
- 更新 `status`: 自动级联更新所有子分类的 `status`
- 更新 `name`: 不影响子分类

**响应**:
```json
{
  "code": 200,
  "message": "Category updated successfully",
  "data": {
    "id": "clt123456790",
    "name": "更新后的分类名称",
    "description": "更新后的描述",
    "parentId": "clt123456791",
    "level": 2,                                              // 自动重新计算
    "sort": 2,
    "status": 1,
    "updatedAt": "2025-12-03T10:05:00.000Z"
  },
  "timestamp": "2025-12-03T10:05:00.000Z",
  "success": true
}
```

**验证规则**:
- `name`: 如果更新，必须全局唯一（排除自身）
- `parentId`: 不能移动到自己的子分类下（防止循环引用）
- `status`: 必须是 0 或 1

**错误响应**:
- `404`: 分类不存在
- `500`: 分类名称已存在
- `400`: 不能移动到自己的子分类下

---

### 删除分类 ⚠️

**DELETE** `/categories/:id`

**认证**: Required

**路径参数**:
- `id`: 分类ID (string, required)

**说明**:
- 永久删除分类，不可恢复
- 支持级联删除子分类
- 有关联商品时拒绝删除

**安全检查**:
- 检查目标分类及其所有子分类是否有关联商品
- 如果有任何商品关联，删除操作会被拒绝

**响应**:
```json
{
  "code": 200,
  "message": "Category and its subcategories deleted successfully (3 categories removed)",
  "data": {
    "deleted": 3,                                             // 总删除数量（含子分类）
    "cascaded": ["clt123456789"]                            // 发生级联删除的分类ID
  },
  "timestamp": "2025-12-03T10:10:00.000Z",
  "success": true
}
```

**错误响应**:
- `404`: 分类不存在
- `400`: 分类有关联商品，无法删除

---

## Batch Operations

### 批量删除分类 ⚠️

**DELETE** `/categories/batch`

**认证**: Required

**请求体**:
```json
{
  "categoryIds": ["clt123456790", "clt123456791"]           // 分类ID数组 (string[], required, max=20)
}
```

**特性**:
- ✅ **级联删除**: 自动删除所有子分类
- ⚠️ **永久删除**: 数据不可恢复
- ✅ **安全检查**: 检查关联商品，防止数据不一致
- ✅ **事务保证**: 确保数据一致性
- ⚠️ **批量限制**: 最多20个分类（安全考虑）

**响应**:
```json
{
  "code": 200,
  "message": "Batch deletion completed successfully",
  "data": {
    "deleted": 3,                                            // 成功删除的总数量
    "failed": ["clt123456791"],                             // 删除失败的分类ID（有关联商品）
    "cascaded": ["clt123456790"],                           // 发生级联删除的分类ID
    "message": "All categories deleted successfully (including 1 categories with their subcategories)"
  },
  "timestamp": "2025-12-03T10:15:00.000Z",
  "success": true
}
```

**部分成功响应**:
```json
{
  "code": 200,
  "message": "Batch deletion completed with some failures",
  "data": {
    "deleted": 2,
    "failed": ["clt123456791"],
    "cascaded": ["clt123456790"],
    "message": "2 categories deleted successfully, 1 failed (may have associated products)"
  },
  "timestamp": "2025-12-03T10:15:00.000Z",
  "success": true
}
```

**验证规则**:
- `categoryIds`: 必须是非空数组
- 每个ID必须是有效的字符串
- 最多20个ID

**错误响应**:
- `400`: 参数验证失败（超过限制、格式错误等）
- `500`: 批量删除失败

---

### 批量更新分类状态 🆕

**PUT** `/categories/batch/status`

**认证**: Required

**请求体**:
```json
{
  "categoryIds": ["clt123456790", "clt123456791"],          // 分类ID数组 (string[], required, max=50)
  "status": 1                                                // 目标状态 (number, required, 0=禁用, 1=启用)
}
```

**特性**:
- ✅ **级联更新**: 自动更新所有子分类的状态
- ✅ **事务保证**: 确保数据一致性
- ✅ **批量限制**: 最多50个分类
- ✅ **部分失败处理**: 支持部分成功的批量操作响应

**级联更新行为**:
- 禁用父分类时，所有子分类和孙子分类都会被禁用
- 启用父分类时，所有子分类和孙子分类都会被启用
- 返回的 `updated` 数量包含所有受影响的分类（父分类 + 所有子分类）
- 返回的 `cascaded` 数组包含发生了级联更新的父分类ID

**响应**:
```json
{
  "code": 200,
  "message": "All categories status updated to active successfully (including 2 parent categories with their subcategories)",
  "data": {
    "updated": 8,                                            // 总更新数量（含子分类）
    "failed": [],                                           // 更新失败的分类ID
    "cascaded": ["clt123456790", "clt123456791"],          // 发生级联更新的父分类ID
    "status": 1,                                            // 新的状态值
    "message": "All categories status updated to active successfully (including 2 parent categories with their subcategories)"
  },
  "timestamp": "2025-12-03T10:20:00.000Z",
  "success": true
}
```

**部分成功响应**:
```json
{
  "code": 200,
  "message": "Batch status update completed with some failures",
  "data": {
    "updated": 6,
    "failed": ["clt123456792"],                            // 不存在的分类ID
    "cascaded": ["clt123456790"],
    "status": 1,
    "message": "6 categories updated successfully, 1 failed (categories not found)"
  },
  "timestamp": "2025-12-03T10:20:00.000Z",
  "success": true
}
```

**验证规则**:
- `categoryIds`: 必须是非空数组
- `status`: 必须是 0 或 1
- 每个ID必须是有效的字符串
- 最多50个ID

**错误响应**:
- `400`: 参数验证失败（超过限制、status值错误等）
- `500`: 批量更新失败

---

## Navigation & Hierarchy

### 获取子分类

**GET** `/categories/:id/children`

**认证**: Optional

**路径参数**:
- `id`: 父分类ID (string, required)

**说明**: 获取指定分类的直接子分类（仅启用状态）

**响应**:
```json
{
  "code": 200,
  "message": "Children categories retrieved successfully",
  "data": [
    {
      "id": "clt123456790",
      "name": "智能传感器",
      "description": "各种智能传感器设备",
      "parentId": "clt123456789",
      "level": 2,
      "sort": 1,
      "status": 1,                                           // 仅返回启用状态的子分类
      "createdAt": "2025-12-03T10:00:00.000Z",
      "updatedAt": "2025-12-03T10:00:00.000Z"
    }
  ],
  "timestamp": "2025-12-03T10:25:00.000Z",
  "success": true
}
```

**错误响应**:
- `404`: 父分类不存在

---

### 获取分类路径

**GET** `/categories/:id/path`

**认证**: Optional

**路径参数**:
- `id`: 分类ID (string, required)

**说明**: 获取从根分类到指定分类的完整路径（面包屑导航）

**响应**:
```json
{
  "code": 200,
  "message": "Category path retrieved successfully",
  "data": [
    {
      "id": "clt123456789",                                 // 根分类
      "name": "IoT设备",
      "parentId": null,
      "level": 1
    },
    {
      "id": "clt123456790",                                 // 中间分类
      "name": "智能传感器",
      "parentId": "clt123456789",
      "level": 2
    },
    {
      "id": "clt123456791",                                 // 目标分类
      "name": "温度传感器",
      "parentId": "clt123456790",
      "level": 3
    }
  ],
  "timestamp": "2025-12-03T10:30:00.000Z",
  "success": true
}
```

**使用场景**:
- 面包屑导航: `IoT设备 > 智能传感器 > 温度传感器`
- 分类层级显示
- 返回上级导航

---

### 移动分类

**PUT** `/categories/:id/move`

**认证**: Required

**路径参数**:
- `id`: 要移动的分类ID (string, required)

**请求体**:
```json
{
  "newParentId": "clt123456791"                             // 新父分类ID (string, optional, null表示移到根级)
}
```

**说明**:
- 将分类移动到新的父分类下
- 自动重新计算该分类及其所有子分类的 `level`
- 防止循环引用（不能移动到自己的子分类下）

**安全检查**:
- 检查是否会形成循环引用
- 验证新父分类存在

**响应**:
```json
{
  "code": 200,
  "message": "Category moved successfully",
  "data": {
    "id": "clt123456790",
    "name": "智能传感器",
    "parentId": "clt123456791",                            // 新的父分类
    "level": 2,                                            // 自动重新计算
    "updatedAt": "2025-12-03T10:35:00.000Z"
  },
  "timestamp": "2025-12-03T10:35:00.000Z",
  "success": true
}
```

**错误响应**:
- `400`: 不能移动到自己的子分类下（循环引用）
- `404`: 分类不存在或新父分类不存在

---

## Best Practices

### 分类管理策略

#### 1. 启用/禁用分类（推荐）✅

**优点**:
- 数据不丢失，随时可恢复
- 不影响历史数据关联
- 无商品数量限制

**接口**:
- 批量状态管理: `PUT /categories/batch/status`
- 单个更新: `PUT /categories/:id`
- 查看所有: `GET /categories/tree`（包含禁用状态）

**使用场景**:
- 季节性分类（如"夏季商品"）
- 临时缺货的分类
- 测试中的新分类

#### 2. 永久删除（谨慎使用）⚠️

**限制**:
- 有关联商品时无法删除
- 数据永久丢失
- 最多批量删除20个

**接口**:
- 单个删除: `DELETE /categories/:id`
- 批量删除: `DELETE /categories/batch`

**使用场景**:
- 创建错误的测试分类
- 重复的分类（需先处理商品关联）
- 完全不再使用的分类

#### 3. 前端显示

**接口选择**:
- 启用分类树: `GET /categories/tree/active`
- 带商品数量: `GET /categories/with-count`
- 面包屑路径: `GET /categories/:id/path`

#### 4. 级联操作策略

**父级操作影响**:
- 更新父分类状态 → 自动影响所有子分类
- 移动父分类 → 自动重新计算所有子分类的 level
- 删除父分类 → 自动删除所有子分类

**批量操作效率**:
- 使用批量操作管理整个分类树
- 确保同一层级下的分类状态保持一致

---

### 安全检查机制

#### 删除操作 ⚠️ 危险

**检查项**:
- 递归检查目标分类及所有子分类
- 验证是否有关联商品
- 使用事务确保原子性

**限制**:
- 最多20个分类（批量）
- 有关联商品时拒绝删除

#### 状态管理 ✅ 安全

**特性**:
- 通过 `status` 字段控制显示/隐藏
- 不影响数据完整性
- 可随时恢复
- 无关联商品检查限制

---

### 批量操作限制

| 操作类型 | 最大数量 | 安全级别 | 级联行为 |
|---------|---------|---------|---------|
| 删除 | 20个 | 危险 | 级联删除子分类 |
| 状态更新 | 50个 | 安全 | 级联更新子分类状态 |

---

### 错误处理

#### 常见错误码

| 状态码 | 场景 | 示例 |
|-------|------|------|
| 400 | 关联数据阻止删除 | 分类有商品关联 |
| 400 | 循环引用 | 移动到自己的子分类 |
| 404 | 资源不存在 | 分类/父分类不存在 |
| 500 | 服务器错误 | 名称重复（业务逻辑错误） |

#### 部分成功处理

批量操作支持部分成功：
- 返回 `200` 状态码
- 包含成功和失败的详细列表
- 提供失败原因说明

**示例**:
```json
{
  "code": 200,
  "message": "Batch deletion completed with some failures",
  "data": {
    "deleted": 2,
    "failed": ["clt123456791"],
    "message": "2 categories deleted successfully, 1 failed (may have associated products)"
  }
}
```

---

### 数据完整性

#### level 字段自动管理

**规则**:
- 创建时: 根据 `parentId` 自动计算
- 移动时: 自动更新该分类及所有子分类
- 不可手动设置（通过API请求会被忽略）

**计算公式**:
```
level = parent.level + 1
根分类 level = 1
```

#### 商品数量统计

**规则**:
- `productCount`: 仅统计启用状态的商品（`status: 1`）
- 树形结构: 累加所有子分类的商品数量
- 扁平结构: 仅统计直接关联的商品

---

### 性能优化建议

1. **使用缓存**: 分类数据变化不频繁，适合缓存
2. **前端树形渲染**: 使用 `/tree/active` 接口一次性获取完整结构
3. **避免频繁移动**: 移动操作会更新所有子分类的 level
4. **批量操作**: 优先使用批量接口而非循环单个操作

---

## 数据模型

### Category Schema

```typescript
{
  id: string              // Prisma cuid, 自动生成
  name: string            // 分类名称，必填，全局唯一
  description: string?    // 分类描述，可选
  parentId: string?       // 父分类ID，可选（null表示根分类）
  level: number           // 分类层级，自动计算（1, 2, 3...）
  sort: number            // 排序权重，默认0
  status: number          // 状态（0=禁用, 1=启用），默认1
  createdAt: DateTime     // 创建时间，自动生成
  updatedAt: DateTime     // 更新时间，自动更新

  // 关联关系
  children: Category[]    // 子分类数组（查询时包含）
  products: Product[]     // 关联商品数组

  // 计算字段
  productCount: number    // 商品数量（仅启用状态）
}
```

### 关系图

```
Category (1) ----< (N) Category
    |                      |
    | children             | parentId
    v                      v
  子分类                父分类

Category (1) ----< (N) Product
    |
    | products
    v
  商品列表
```

---

## API 总结

### 端点列表

| 方法 | 路径 | 认证 | 说明 |
|-----|------|------|------|
| GET | `/categories/tree` | Optional | 获取所有分类树（含禁用） |
| GET | `/categories/tree/active` | Optional | 获取启用分类树 |
| GET | `/categories/with-count` | Optional | 获取分类及商品数量 |
| GET | `/categories/:id` | Optional | 获取分类详情 |
| POST | `/categories` | Required | 创建分类 |
| PUT | `/categories/:id` | Required | 更新分类 |
| DELETE | `/categories/:id` | Required | 删除分类 |
| DELETE | `/categories/batch` | Required | 批量删除分类 |
| PUT | `/categories/batch/status` | Required | 批量更新状态 |
| GET | `/categories/:id/children` | Optional | 获取子分类 |
| GET | `/categories/:id/path` | Optional | 获取分类路径 |
| PUT | `/categories/:id/move` | Required | 移动分类 |

### 认证说明

- **Required**: 需要 `Authorization: Bearer <token>` 头部
- **Optional**: 可以提供 token，但不强制要求

### 响应格式

所有接口统一响应格式：

```json
{
  "code": 200,              // HTTP状态码
  "message": "Success",     // 响应消息
  "data": {},               // 响应数据
  "timestamp": "ISO 8601",  // 响应时间戳
  "success": true           // 请求是否成功
}
```

---

**最后更新**: 2026-02-04
**文档版本**: 2.0
**验证状态**: ✅ 已验证与代码一致
