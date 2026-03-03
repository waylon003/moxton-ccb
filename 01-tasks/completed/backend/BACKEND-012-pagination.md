# Tech-Spec: 修复分页参数不合规返回400

**任务ID:** BACKEND-012
**父任务:** BACKEND-011
**创建时间:** 2026-03-02
**状态:** 准备开发
**角色:** 后端工程师
**项目:** moxton-lotapi (E:\moxton-lotapi)
**优先级:** P1
**技术栈:** Node.js + Koa + TypeScript + Prisma + MongoDB

---

## 执行上下文（强约束）

- **Task File = 唯一执行输入源**：派遣消息可能是短文本，必须以本任务文件为准，不得依赖派遣消息补充细节。
- **角色定义**：`E:\moxton-ccb\.claude\agents\backend.md`
- **协议文件**：`E:\moxton-ccb\.claude\agents\protocol.md`
- **工作目录**：`E:\moxton-lotapi`
- **开始后 60 秒内**：必须 `report_route(status="in_progress")`
- **执行中每 90~120 秒**：发送一次 `in_progress` 心跳
- **遇阻塞 2 分钟内**：`report_route(status="blocked", body="blocker_type=...;question=...;attempted=...;next_action_needed=...")`
- **完成后必须**：`report_route(status="success|fail|blocked", body=变更文件+命令+测试结果)`

---

## 概述

### 问题陈述

当前分页接口在收到不合规的分页参数时（如负数、非数字、超出范围等），返回 HTTP 200 而不是 400。这违反了 REST API 设计规范，应该返回 400 Bad Request 表示客户端请求参数错误。

### 解决方案

在所有分页接口的控制器层添加分页参数校验逻辑：
1. 校验 pageNum 和 pageSize 是否为正整数
2. 校验 pageSize 是否超过最大限制（如 100）
3. 校验失败时返回 400 状态码和错误信息

### 范围

**包含:**
- `GET /orders/user` 分页参数校验
- `GET /offline-orders/user` 分页参数校验
- 其他分页接口的校验

**不包含:**
- 前端修改
- 数据库查询逻辑修改

---

## 当前问题分析

### 分页接口列表

| 接口 | 控制器文件 | 当前行为 | 期望行为 |
|------|-----------|---------|---------|
| GET /orders/user | `src/controllers/orderController.ts` | 参数不合规返回 200 | 返回 400 |
| GET /offline-orders/user | `src/controllers/offlineOrderController.ts` | 参数不合规返回 200 | 返回 400 |

### 不合规参数示例

- `pageNum=-1` (负数)
- `pageNum=abc` (非数字)
- `pageSize=0` (零或负数)
- `pageSize=9999` (超出最大限制)

---

## 技术方案

### Step 1: 创建分页参数校验工具函数

**文件**: `src/utils/pagination.ts` (新建或修改现有文件)

```typescript
/**
 * 分页参数校验结果
 */
export interface PaginationValidationResult {
  valid: boolean
  pageNum: number
  pageSize: number
  error?: string
}

/**
 * 默认分页配置
 */
export const DEFAULT_PAGINATION = {
  PAGE_NUM: 1,
  PAGE_SIZE: 10,
  MAX_PAGE_SIZE: 100
}

/**
 * 校验分页参数
 * @param pageNum 页码参数
 * @param pageSize 每页数量参数
 * @returns 校验结果
 */
export function validatePagination(
  pageNum: unknown,
  pageSize: unknown
): PaginationValidationResult {
  // 转换为数字
  const numPageNum = Number(pageNum)
  const numPageSize = Number(pageSize)

  // 校验 pageNum
  if (pageNum !== undefined && pageNum !== '') {
    if (isNaN(numPageNum) || !Number.isInteger(numPageNum)) {
      return {
        valid: false,
        pageNum: DEFAULT_PAGINATION.PAGE_NUM,
        pageSize: DEFAULT_PAGINATION.PAGE_SIZE,
        error: 'pageNum must be a valid integer'
      }
    }
    if (numPageNum < 1) {
      return {
        valid: false,
        pageNum: DEFAULT_PAGINATION.PAGE_NUM,
        pageSize: DEFAULT_PAGINATION.PAGE_SIZE,
        error: 'pageNum must be greater than or equal to 1'
      }
    }
  }

  // 校验 pageSize
  if (pageSize !== undefined && pageSize !== '') {
    if (isNaN(numPageSize) || !Number.isInteger(numPageSize)) {
      return {
        valid: false,
        pageNum: numPageNum || DEFAULT_PAGINATION.PAGE_NUM,
        pageSize: DEFAULT_PAGINATION.PAGE_SIZE,
        error: 'pageSize must be a valid integer'
      }
    }
    if (numPageSize < 1) {
      return {
        valid: false,
        pageNum: numPageNum || DEFAULT_PAGINATION.PAGE_NUM,
        pageSize: DEFAULT_PAGINATION.PAGE_SIZE,
        error: 'pageSize must be greater than or equal to 1'
      }
    }
    if (numPageSize > DEFAULT_PAGINATION.MAX_PAGE_SIZE) {
      return {
        valid: false,
        pageNum: numPageNum || DEFAULT_PAGINATION.PAGE_NUM,
        pageSize: DEFAULT_PAGINATION.PAGE_SIZE,
        error: `pageSize must not exceed ${DEFAULT_PAGINATION.MAX_PAGE_SIZE}`
      }
    }
  }

  return {
    valid: true,
    pageNum: numPageNum || DEFAULT_PAGINATION.PAGE_NUM,
    pageSize: numPageSize || DEFAULT_PAGINATION.PAGE_SIZE
  }
}
```

**验收**:
- 工具函数可正确校验各种不合规参数
- 返回明确的错误信息

---

### Step 2: 修改订单列表接口

**文件**: `src/controllers/orderController.ts`

找到 `getUserOrders` 方法（或类似名称），添加分页参数校验：

```typescript
import { validatePagination } from '../utils/pagination'

export const getUserOrders = async (ctx: Context) => {
  try {
    const userId = ctx.state.user?.id
    if (!userId) {
      ctx.status = 401
      ctx.body = { code: 401, message: 'Unauthorized', success: false }
      return
    }

    // 获取分页参数
    const { pageNum, pageSize, status } = ctx.query

    // 校验分页参数
    const pagination = validatePagination(pageNum, pageSize)
    if (!pagination.valid) {
      ctx.status = 400
      ctx.body = {
        code: 400,
        message: pagination.error,
        success: false
      }
      return
    }

    // 调用服务层
    const result = await orderService.getUserOrders(userId, {
      pageNum: pagination.pageNum,
      pageSize: pagination.pageSize,
      status: status as string
    })

    ctx.body = {
      code: 200,
      message: 'Success',
      data: result,
      success: true
    }
  } catch (error) {
    ctx.status = 500
    ctx.body = {
      code: 500,
      message: error instanceof Error ? error.message : 'Internal Server Error',
      success: false
    }
  }
}
```

**验收**:
- 不合规的 pageNum/pageSize 返回 400
- 合规的参数正常返回 200 和数据

---

### Step 3: 修改咨询列表接口

**文件**: `src/controllers/offlineOrderController.ts`

同样的修改方式：

```typescript
import { validatePagination } from '../utils/pagination'

export const getUserOfflineOrders = async (ctx: Context) => {
  try {
    const userId = ctx.state.user?.id
    if (!userId) {
      ctx.status = 401
      ctx.body = { code: 401, message: 'Unauthorized', success: false }
      return
    }

    const { pageNum, pageSize } = ctx.query

    // 校验分页参数
    const pagination = validatePagination(pageNum, pageSize)
    if (!pagination.valid) {
      ctx.status = 400
      ctx.body = {
        code: 400,
        message: pagination.error,
        success: false
      }
      return
    }

    const result = await offlineOrderService.getUserOfflineOrders(userId, {
      pageNum: pagination.pageNum,
      pageSize: pagination.pageSize
    })

    ctx.body = {
      code: 200,
      message: 'Success',
      data: result,
      success: true
    }
  } catch (error) {
    ctx.status = 500
    ctx.body = {
      code: 500,
      message: error instanceof Error ? error.message : 'Internal Server Error',
      success: false
    }
  }
}
```

**验收**:
- 不合规参数返回 400
- 合规参数正常返回

---

### Step 4: 检查其他分页接口

检查是否还有其他分页接口需要修改：
- 搜索 `pageNum` 或 `pageSize` 在 `src/controllers/` 目录下的使用
- 为所有分页接口添加校验

**验收**:
- 所有分页接口都有参数校验

---

### Step 5: API 测试验证

使用 curl 或 Postman 测试：

```bash
# 测试负数 pageNum - 应该返回 400
curl -H "Authorization: Bearer <token>" \
  "http://localhost:3033/orders/user?pageNum=-1&pageSize=10"

# 测试非数字 pageNum - 应该返回 400
curl -H "Authorization: Bearer <token>" \
  "http://localhost:3033/orders/user?pageNum=abc&pageSize=10"

# 测试零 pageSize - 应该返回 400
curl -H "Authorization: Bearer <token>" \
  "http://localhost:3033/orders/user?pageNum=1&pageSize=0"

# 测试超大 pageSize - 应该返回 400
curl -H "Authorization: Bearer <token>" \
  "http://localhost:3033/orders/user?pageNum=1&pageSize=9999"

# 测试合规参数 - 应该返回 200
curl -H "Authorization: Bearer <token>" \
  "http://localhost:3033/orders/user?pageNum=1&pageSize=10"
```

**验收**:
- 所有不合规参数返回 400
- 合规参数返回 200 和正确数据

---

## 验收标准

| # | 标准 | 验证方式 |
|---|------|---------|
| 1 | 负数 pageNum 返回 400 | curl/Postman 测试 |
| 2 | 非数字 pageNum 返回 400 | curl/Postman 测试 |
| 3 | 负数/零 pageSize 返回 400 | curl/Postman 测试 |
| 4 | 超过最大限制的 pageSize 返回 400 | curl/Postman 测试 |
| 5 | 合规参数正常返回 200 | curl/Postman 测试 |
| 6 | 错误信息清晰明确 | 响应体检查 |

---

## 相关文件

- `src/controllers/orderController.ts`
- `src/controllers/offlineOrderController.ts`
- `src/utils/pagination.ts` (新建)
