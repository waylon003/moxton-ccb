# BACKEND-005: 订单查询 keyword 参数不生效

**创建时间**: 2025-02-09
**优先级**: 高
**任务类型**: 后端 Bug 修复
**关联项目**: moxton-lotapi

---

## 问题描述

前端在线订单列表的搜索框输入 keyword 后，后端没有处理该参数，导致搜索无结果。

---

## 问题定位

**文件**: `E:\moxton-lotapi\src\controllers\Order.ts`

**方法**: `getAllOrders` (第 961-1009 行)

**当前代码**:
```typescript
getAllOrders = asyncHandler(async (ctx: Context) => {
  const { pageNum = 1, pageSize = 10, status, userId, orderNo } = ctx.query as any

  const where: any = {}
  if (status) {
    where.status = status
  }
  if (userId) {
    where.userId = userId
  }
  if (orderNo) {
    where.orderNo = { contains: orderNo }
  }
  // ❌ 缺少 keyword 参数的处理逻辑
  // ...
})
```

---

## 修复要求

### 1. 获取 keyword 参数

```typescript
const { pageNum = 1, pageSize = 10, status, userId, orderNo, keyword } = ctx.query as any
```

### 2. 添加 keyword 处理逻辑

```typescript
// 如果存在 keyword，添加多字段模糊查询
if (keyword) {
  where.OR = [
    { orderNo: { contains: keyword } },      // 订单号
    { consignee: { contains: keyword } },    // 收货人
    { phone: { contains: keyword } },        // 联系电话
    { address: { contains: keyword } },      // 收货地址
    { guestName: { contains: keyword } },    // 游客姓名
    { guestPhone: { contains: keyword } }    // 游客电话
  ]
}
```

### 3. 与其他条件的组合

注意：如果同时存在 `keyword` 和其他条件（如 `status`），需要正确组合：

```typescript
const where: any = {}

// 状态筛选（AND 条件）
if (status) {
  where.status = status
}

// keyword 搜索（OR 条件，但与 status 是 AND 关系）
if (keyword) {
  where.OR = [
    { orderNo: { contains: keyword } },
    { consignee: { contains: keyword } },
    { phone: { contains: keyword } },
    { address: { contains: keyword } },
    { guestName: { contains: keyword } },
    { guestPhone: { contains: keyword } }
  ]
}

// 最终 SQL 逻辑类似：
// WHERE (status = ?) AND (
//   orderNo LIKE ? OR
//   consignee LIKE ? OR
//   phone LIKE ? OR
//   address LIKE ?
// )
```

---

## 修复后的完整代码

```typescript
getAllOrders = asyncHandler(async (ctx: Context) => {
  const { pageNum = 1, pageSize = 10, status, userId, orderNo, keyword } = ctx.query as any

  const where: any = {}

  // 用户筛选
  if (userId) {
    where.userId = userId
  }

  // 状态筛选
  if (status) {
    where.status = status
  }

  // 订单号精确搜索
  if (orderNo) {
    where.orderNo = { contains: orderNo }
  }

  // keyword 多字段模糊搜索
  if (keyword) {
    where.OR = [
      { orderNo: { contains: keyword } },
      { consignee: { contains: keyword } },
      { phone: { contains: keyword } },
      { address: { contains: keyword } },
      { guestName: { contains: keyword } },
      { guestPhone: { contains: keyword } }
    ]
  }

  // 分页查询
  const [total, orders] = await Promise.all([
    prisma.order.count({ where }),
    prisma.order.findMany({
      where,
      skip: (pageNum - 1) * pageSize,
      take: Number(pageSize),
      orderBy: { createdAt: 'desc' },
      include: {
        user: {
          select: {
            id: true,
            username: true,
            nickname: true
          }
        },
        items: true
      }
    })
  ])

  return ctx.ok({
    total,
    pageNum: Number(pageNum),
    pageSize: Number(pageSize),
    data: orders.map(formatOrder)
  })
})
```

---

## 验收标准

1. ✅ keyword 参数能正确模糊查询订单号
2. ✅ keyword 参数能正确模糊查询收货人
3. ✅ keyword 参数能正确模糊查询联系电话
4. ✅ keyword 参数能正确模糊查询收货地址
5. ✅ keyword 与 status 等其他条件能正确组合查询
6. ✅ keyword 为空时不影响查询

---

## 测试用例

```bash
# 测试1: keyword 搜索订单号
curl "http://localhost:3000/orders/admin?pageNum=1&pageSize=10&keyword=ORD2025"

# 测试2: keyword 搜索收货人
curl "http://localhost:3000/orders/admin?pageNum=1&pageSize=10&keyword=张三"

# 测试3: keyword 搜索电话
curl "http://localhost:3000/orders/admin?pageNum=1&pageSize=10&keyword=13800138000"

# 测试4: keyword + status 组合查询
curl "http://localhost:3000/orders/admin?pageNum=1&pageSize=10&keyword=张三&status=SHIPPED"

# 预期返回符合任一条件（OR）且状态匹配（AND）的订单
```

---

## 前端搜索框位置

**文件**: `E:\moxton-lotadmin\src\views\online-order\modules\online-order-search.vue`
**Placeholder**: "搜索订单号、收货人、电话、地址"
