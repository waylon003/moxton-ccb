# Tech-Spec: 商品购买模式字段与服务端拦截

**任务ID:** BACKEND-017
**创建时间:** 2026-06-17
**状态:** 已完成
**角色:** 后端工程师
**项目:** moxton-lotapi
**优先级:** P0
**技术栈:** Node.js + Koa + TypeScript + Prisma + MySQL
**QA_LEVEL:** full

---


## 概述

### 问题陈述

当前商品购买行为主要依赖 `price` / `hasPrice` 推导：有价格显示线上购买，无价格显示咨询。预售预约功能需要第三种模式：产品可展示但不能购买，只能点击“立即预约”。如果只改前端，用户仍可能直接调用购物车或结账接口绕过限制。

### 解决方案

在后端商品模型中新增显式购买模式字段 `purchaseMode`，并在商品接口、创建/更新接口、购物车、订单创建和购物车结账链路中统一使用该字段。

推荐枚举值：

```ts
'ONLINE' | 'INQUIRY_ONLY' | 'PREORDER'
```

### 范围

**包含:**
- `Product` 新增 `purchaseMode` 字段。
- 商品创建/更新接口支持 `purchaseMode`。
- 商品列表、搜索、详情、后台列表返回 `purchaseMode`。
- 保留 `hasPrice` 作为兼容字段。
- 购物车加购拦截非 `ONLINE` 商品。
- 购物车详情过滤非 `ONLINE` 商品。
- 订单创建与购物车结账拦截非 `ONLINE` 商品。

**不包含:**
- 预约发码接口。
- 邮件发送。
- 后台页面开发。
- 官网页面开发。
- 结账优惠码抵扣。

---

## 开发上下文

### 现有实现

重点文件：

- `prisma/schema.prisma`
- `src/controllers/Product.ts`
- `src/models/Product.ts`
- `src/models/Cart.ts`
- `src/controllers/Order.ts`
- `src/routes/products.ts`

当前问题点：

- `ProductController` 与 `ProductModel` 多处重复计算 `hasPrice`。
- `CartModel.getCartDetails` 使用 `price !== null && price > 0` 判断有效购物车商品。
- `CartItemModel.addToCart` 只检查状态和库存。
- `OrderController.createOrder` / `checkoutFromCartWithAddress` 只校验状态、库存、价格。

### 依赖项

无前置开发任务。此任务是后续后台和官网任务的接口基础。

---

## 技术方案

### 数据模型

`Product` 增加字段：

```prisma
purchaseMode String @default("ONLINE")
```

历史兼容策略：

- 未传 `purchaseMode` 时按历史价格逻辑推导：
  - `price > 0` -> `ONLINE`
  - `price` 为空、`null` 或 `0` -> `INQUIRY_ONLY`
- 接口响应继续返回 `hasPrice`，避免旧前端立即失效。

### 业务逻辑

合法值：

```ts
ONLINE
INQUIRY_ONLY
PREORDER
```

服务端拦截：

- `ONLINE`：允许加购、允许订单创建。
- `INQUIRY_ONLY`：不允许加购、不允许线上订单创建。
- `PREORDER`：不允许加购、不允许线上订单创建。

错误信息建议：

```text
Product is not available for online purchase
```

---

## 实施步骤

1. 修改 `prisma/schema.prisma`，新增 `Product.purchaseMode`。
2. 运行/提示需要执行 Prisma generate/db push 或迁移，按仓库现有流程处理。
3. 在产品创建/更新控制器中接收和校验 `purchaseMode`。
4. 在商品响应归一化逻辑中返回 `purchaseMode`，并保留 `hasPrice`。
5. 修改 `CartItemModel.addToCart`，只允许 `ONLINE`。
6. 修改 `CartModel.getCartDetails` 和购物车汇总逻辑，过滤非 `ONLINE` 商品。
7. 修改 `OrderController.createOrder` 与 `checkoutFromCartWithAddress`，结账时再次校验 `ONLINE`。
8. 补充最小 API 测试或脚本验证。

---

## 验收标准

- [ ] 商品创建接口支持 `purchaseMode`。
- [ ] 商品更新接口支持 `purchaseMode`。
- [ ] 商品列表、搜索、详情、后台列表返回 `purchaseMode`。
- [ ] 旧字段 `hasPrice` 仍返回。
- [ ] 未传 `purchaseMode` 的历史商品仍能按原逻辑工作。
- [ ] `PREORDER` 商品不能加入购物车。
- [ ] `INQUIRY_ONLY` 商品不能加入购物车。
- [ ] `PREORDER` 商品不能通过直接订单接口或购物车结账创建线上订单。
- [ ] `ONLINE` 商品原有购物车和结账链路不回归。

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| Prisma Client 未生成导致类型错误 | 按项目既有流程运行 `npm run prisma:generate` |
| 历史商品无 `purchaseMode` | 使用后端默认值和价格推导兼容 |
| 只改 UI 导致接口绕过 | 本任务必须完成购物车和订单服务端拦截 |

---

**相关文档:**
- [开发计划](../../docs/plans/2026-06-17-preorder-discount-code-closed-loop-plan.md)
- [项目状态](../../04-projects/moxton-lotapi.md)
