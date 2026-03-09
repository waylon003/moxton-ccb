# Tech-Spec: 修复结账流程与订单支付入口

**任务ID:** SHOP-FE-012
**创建时间:** 2026-03-05
**状态:** 准备开发
**角色:** 独立站前端工程师
**项目:** nuxt-moxton
**优先级:** P0
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia

---

## 执行上下文（强约束）

- **Task File = 唯一执行输入源**：派遣消息可能是短文本，必须以本任务文件为准，不得依赖派遣消息补充细节。
- **工作目录**：`E:\nuxt-moxton`
- **必读文档**：
  - `E:\nuxt-moxton\CLAUDE.md`
  - `E:\nuxt-moxton\AGENTS.md`
  - `E:\moxton-ccb\02-api\orders.md` - 订单接口文档
- **开始后 60 秒内**：必须 `report_route(status="in_progress")`
- **执行中每 90~120 秒**：发送一次 `in_progress` 心跳
- **遇阻塞 2 分钟内**：`report_route(status="blocked", body="blocker_type=...;question=...;attempted=...;next_action_needed=...")`
- **完成后必须**：`report_route(status="success|fail|blocked", body=变更文件+命令+测试结果)`

---

## 概述

### 问题陈述

结账页 Step 1（个人信息）填写完姓名、邮箱、手机号、公司名称和收货地址后，点击"下一步"创建订单，但订单列表中显示的信息不完整。经过深度分析发现以下问题：

1. **结账参数问题**：`stores/checkout.ts` 中的 `createOrder()` 方法传递了多余的 `items` 字段，而 `/orders/checkout` 接口不需要此字段（后端从购物车自动获取）

2. **字段映射问题**：订单列表页 `pages/account/orders/index.vue` 使用的字段名与 API 返回不一致：
   - 前端用 `totalAmount`，API 返回 `amount.total`
   - 前端用 `createdAt`，API 返回 `timestamps.created`

3. **缺少支付入口**：PENDING 状态订单在订单列表页没有"去支付"按钮

### 解决方案

1. **修复结账参数**：移除 `createOrder()` 中的 `items` 字段传递，只保留必要字段
2. **修复字段映射**：更新订单列表页的类型定义和字段访问方式
3. **添加支付入口**：为 PENDING 订单添加"去支付"按钮，跳转到支付页

### 范围 (包含/排除)

**包含:**
- `stores/checkout.ts` - 修复 `createOrder()` 方法
- `pages/account/orders/index.vue` - 修复字段映射，添加支付入口
- `types/order.ts` - 如有需要，更新类型定义

**不包含:**
- 后端接口修改（已确认后端实现正确）
- UI 样式大幅调整

---

## 开发上下文

### 相关文件位置

| 文件 | 用途 |
|------|------|
| `stores/checkout.ts` | checkout store，包含 `createOrder()` 方法 |
| `pages/account/orders/index.vue` | 订单列表页 |
| `types/order.ts` | 订单类型定义 |
| `composables/api/orders.ts` | 订单 API 封装 |

### 关键代码位置

**stores/checkout.ts 第 363-412 行**:
```typescript
async createOrder() {
  // 当前问题：传递了 items 字段
  const checkoutData = {
    items: orderItems,  // ❌ 需要移除
    guestInfo: this.formData.guestInfo,
    shippingAddress: this.formData.shippingAddress,
    remarks: this.formData.remarks
  }
}
```

**pages/account/orders/index.vue 第 11-23 行**:
```typescript
interface AccountOrderItem {
  id: string
  orderNo?: string
  status?: string
  totalAmount?: number   // ❌ 应改为 amount.total
  createdAt?: string     // ❌ 应改为 timestamps.created
  items?: Array<{
    product?: {
      images?: string[]
      name?: string
    }
  }>
}
```

### 依赖项

- API: `POST /orders/checkout` - 购物车结算接口
- API: `GET /orders/user` - 获取用户订单列表

---

## 技术方案

### API 契约

**POST /orders/checkout 正确请求体**:
```json
{
  "guestInfo": {
    "name": "markTest",
    "email": "123456789@qq.com",
    "phone": "0412345678",
    "company": "moxtontest"
  },
  "shippingAddress": {
    "addressLine1": "Lalaguli Drive",
    "addressLine2": "",
    "city": "Toormina",
    "state": "New South Wales",
    "postalCode": "2452",
    "country": "Australia",
    "countryCode": "AU"
  },
  "remarks": "test"
}
```

**GET /orders/user 响应字段映射**:
```typescript
// API 返回结构
{
  amount: { total: number, currency: string }
  timestamps: { created: string, updated: string }
  items: [{ product: { name, images }, quantity, unitPrice, subtotal }]
}
```

### 实施步骤

1. **修复 checkout store**
   - 修改 `stores/checkout.ts` 中的 `createOrder()` 方法
   - 移除 `items` 字段的传递
   - 保持 `guestInfo`, `shippingAddress`, `remarks` 字段

2. **修复订单列表字段映射**
   - 修改 `pages/account/orders/index.vue`
   - 更新 `AccountOrderItem` 接口，匹配 API 返回结构
   - 修改模板中的字段访问：`totalAmount` → `amount.total`
   - 修改模板中的字段访问：`createdAt` → `timestamps.created`

3. **添加支付入口**
   - 在订单列表的 PENDING 状态订单卡片上添加"去支付"按钮
   - 点击按钮跳转到支付页面（如 `/payment?orderId=xxx`）
   - 支付页面需要支持从订单 ID 创建支付意图

4. **测试验证**
   - 完整走一遍结账流程，确认订单能正确创建
   - 检查订单列表数据完整性（商品图片、金额、时间）
   - 测试 PENDING 订单的"去支付"功能

---

## 验收标准

- [ ] 结账流程调用 `/orders/checkout` 时不再传递 `items` 字段
- [ ] 订单创建成功，订单列表能正确显示商品图片
- [ ] 订单列表显示正确的订单金额（`amount.total`）
- [ ] 订单列表显示正确的创建时间（`timestamps.created`）
- [ ] PENDING 状态订单显示"去支付"按钮
- [ ] 点击"去支付"能跳转到支付页面并传递订单 ID

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 字段映射修改影响其他页面 | 检查 `AccountOrderItem` 接口是否在其他地方使用 |
| 支付页面需要支持订单ID参数 | 确认支付页面路由和参数处理方式 |

---

**相关文档:**
- [订单 API 文档](../../02-api/orders.md)
- [项目状态](../../04-projects/nuxt-moxton.md)
