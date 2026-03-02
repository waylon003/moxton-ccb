# Tech-Spec: 修复个人中心接口 500 错误

**任务ID:** BACKEND-011
**创建时间:** 2026-03-02
**状态:** 准备开发
**角色:** 后端工程师
**项目:** moxton-lotapi (E:\moxton-lotapi)
**优先级:** P1
**技术栈:** Node.js + Koa + TypeScript + Prisma + MongoDB

---

## 概述

### 问题陈述

个人中心三个核心接口出现 500 错误，导致用户无法正常访问个人中心功能：
1. **订单列表** `GET /orders/user` - 返回 500
2. **地址列表** `GET /addresses` - 返回 500
3. **咨询列表** `GET /offline-orders/user` - 返回 500

### 解决方案

排查每个接口的控制器、服务和数据库查询层，定位导致 500 错误的具体原因（如空指针、类型错误、Prisma 查询问题等），修复后确保响应格式符合 API 文档定义。

### 范围

**包含:**
- 修复 `/orders/user` 接口 500 错误
- 修复 `/addresses` 接口 500 错误
- 修复 `/offline-orders/user` 接口 500 错误
- 验证修复后的响应格式符合 API 文档

**不包含:**
- 新增接口或功能
- 前端修改
- 性能优化（除非是导致 500 的直接原因）

---

## 开发上下文

### 现有实现位置

| 接口 | 控制器文件 | 服务文件 |
|------|-----------|---------|
| GET /orders/user | `src/controllers/orderController.ts` | `src/services/orderService.ts` |
| GET /addresses | `src/controllers/addressController.ts` | `src/services/addressService.ts` |
| GET /offline-orders/user | `src/controllers/offlineOrderController.ts` | `src/services/offlineOrderService.ts` |

### API 响应格式要求

参考 `E:\moxton-ccb\02-api/` 下的文档：
- `orders.md` - 订单列表分页格式：`{ list, total, pageNum, pageSize, totalPages }`
- `addresses.md` - 地址列表格式：数组
- `offline-orders.md` - 咨询列表分页格式与订单一致

### 依赖项

- 用户认证中间件 (`authMiddleware`) - 这些接口都需要登录
- Prisma Client - 数据库查询
- 现有的服务层方法

---

## 技术方案

### Step 1: 复现和诊断 500 错误

**目标**: 确认每个接口的具体错误信息

**操作**:
1. 启动后端服务 (`pnpm dev` 或 `npm run dev`)
2. 使用 Postman 或 curl 测试三个接口：
   ```bash
   # 需要先登录获取 token
   curl -H "Authorization: Bearer <token>" http://localhost:3033/orders/user?pageNum=1&pageSize=10
   curl -H "Authorization: Bearer <token>" http://localhost:3033/addresses
   curl -H "Authorization: Bearer <token>" http://localhost:3033/offline-orders/user?pageNum=1&pageSize=10
   ```
3. 查看控制台错误堆栈，记录完整的错误信息
4. 检查日志文件（如果有配置的话）

**常见 500 错误原因**:
- Prisma 查询语法错误
- 空值访问（Cannot read property 'xxx' of null/undefined）
- 类型转换错误
- 缺少必要的关联查询（include）
- 数组越界

---

### Step 2: 修复订单列表接口

**目标**: 修复 `GET /orders/user` 500 错误

**文件**: `src/controllers/orderController.ts` 和 `src/services/orderService.ts`

**排查重点**:
1. 检查控制器中是否正确提取 `userId` 从 JWT token
2. 检查 `orderService.getUserOrders()` 方法的 Prisma 查询：
   - 是否正确使用 `where: { userId }`
   - 是否包含必要的 `include`（如 items、product 等关联）
   - 分页参数处理是否正确
3. 检查响应数据格式化是否有空值访问

**预期响应格式**:
```json
{
  "code": 200,
  "message": "Success",
  "data": {
    "list": [...],
    "total": 100,
    "pageNum": 1,
    "pageSize": 10,
    "totalPages": 10
  },
  "success": true
}
```

**验收**:
- `GET /orders/user?pageNum=1&pageSize=10` 返回 200
- 响应包含正确的分页数据结构
- 列表数据包含订单完整信息

---

### Step 3: 修复地址列表接口

**目标**: 修复 `GET /addresses` 500 错误

**文件**: `src/controllers/addressController.ts` 和 `src/services/addressService.ts`

**排查重点**:
1. 检查控制器是否正确获取当前用户 ID
2. 检查 `addressService.getUserAddresses()` 的 Prisma 查询：
   - 是否正确过滤 `where: { userId }`
   - 是否需要添加 `orderBy` 排序
3. 检查是否有默认地址逻辑导致的空值问题

**预期响应格式**:
```json
{
  "code": 200,
  "message": "Success",
  "data": [
    {
      "id": "addr_xxx",
      "userId": "user_xxx",
      "name": "张三",
      "phone": "13800138000",
      "addressLine1": "街道地址",
      "addressLine2": "",
      "city": "北京",
      "state": "北京市",
      "postalCode": "100000",
      "country": "CN",
      "isDefault": true,
      "createdAt": "...",
      "updatedAt": "..."
    }
  ],
  "success": true
}
```

**验收**:
- `GET /addresses` 返回 200
- 返回当前用户的地址列表数组

---

### Step 4: 修复咨询列表接口

**目标**: 修复 `GET /offline-orders/user` 500 错误

**文件**: `src/controllers/offlineOrderController.ts` 和 `src/services/offlineOrderService.ts`

**排查重点**:
1. 检查路由是否正确注册（注意是 `/offline-orders/user` 不是 `/offline-orders`）
2. 检查控制器是否正确解析分页参数
3. 检查 Service 层的 Prisma 查询是否正确过滤当前用户
4. 检查响应数据格式化

**预期响应格式**（与订单列表一致的分页格式）：
```json
{
  "code": 200,
  "message": "Success",
  "data": {
    "list": [...],
    "total": 50,
    "pageNum": 1,
    "pageSize": 10,
    "totalPages": 5
  },
  "success": true
}
```

**验收**:
- `GET /offline-orders/user?pageNum=1&pageSize=10` 返回 200
- 响应包含正确的分页数据结构

---

### Step 5: 全量回归验证

**目标**: 确认所有修复后的接口正常工作

**验证清单**:
1. **订单列表**:
   - [ ] `GET /orders/user?pageNum=1&pageSize=10` → 200
   - [ ] 分页参数正常（pageNum、pageSize）
   - [ ] 状态筛选正常（?status=PENDING）
   - [ ] 响应格式符合 API 文档

2. **地址列表**:
   - [ ] `GET /addresses` → 200
   - [ ] 返回数组格式
   - [ ] 只返回当前用户的地址

3. **咨询列表**:
   - [ ] `GET /offline-orders/user?pageNum=1&pageSize=10` → 200
   - [ ] 分页参数正常
   - [ ] 响应格式符合 API 文档

4. **边界场景**:
   - [ ] 无数据时返回空列表（不是 500）
   - [ ] 未登录访问返回 401（不是 500）
   - [ ] 无效分页参数返回 400（不是 500）

---

## 验收标准

| # | 标准 | 验证方式 |
|---|------|---------|
| 1 | 订单列表接口返回 200 | Postman/curl 调用验证 |
| 2 | 地址列表接口返回 200 | Postman/curl 调用验证 |
| 3 | 咨询列表接口返回 200 | Postman/curl 调用验证 |
| 4 | 所有接口响应格式符合 API 文档 | 对比 02-api/ 文档 |
| 5 | 无 console.error 输出 | 观察服务端日志 |
| 6 | 未登录访问返回 401 | 不带 token 调用验证 |

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 错误难以复现 | 同时查看浏览器 Network 和后端 console 输出 |
| Prisma 查询复杂 | 先简化查询测试，再逐步添加关联 |
| 修复一个破坏另一个 | 每次修复后都运行全量验证 |
| 权限问题 | 确认 authMiddleware 正确注入 userId |

---

## 相关文档

- [Orders API](../../02-api/orders.md)
- [Addresses API](../../02-api/addresses.md)
- [Offline Orders API](../../02-api/offline-orders.md)
- [Auth API](../../02-api/auth.md)
- [项目状态](../../04-projects/moxton-lotapi.md)
