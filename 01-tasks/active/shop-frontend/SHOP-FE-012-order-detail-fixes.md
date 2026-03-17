# Tech-Spec: 订单详情页缺陷修复

**任务ID:** SHOP-FE-012
**创建时间:** 2026-03-09
**状态:** 准备开发
**角色:** 独立站前端工程师
**项目:** nuxt-moxton (E:\nuxt-moxton)
**优先级:** P1
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia + Reka UI + UnoCSS

---

## 执行上下文（强约束）

- **Task File = 唯一执行输入源**：派遣消息可能是短文本，必须以本任务文件为准，不得依赖派遣消息补充细节。
- **工作目录**：`E:\nuxt-moxton`
- **必读文档**：
  - `E:\nuxt-moxton\CLAUDE.md`
  - `E:\nuxt-moxton\AGENTS.md`
  - `E:\moxton-ccb\02-api\orders.md` - 订单API文档
- **开始后 60 秒内**：必须 `report_route(status="in_progress")`
- **执行中每 90~120 秒**：发送一次 `in_progress` 心跳
- **遇阻塞 2 分钟内**：`report_route(status="blocked", body="blocker_type=...;question=...;attempted=...;next_action_needed=...")`
- **完成后必须**：`report_route(status="success|fail|blocked", body=变更文件+命令+测试结果)`
- **QA 后端基地址**：`http://localhost:3033`（Health: `/health`）
- **注意**：不要使用 `http://0.0.0.0:3033`（不可达），必须使用 `localhost`。

---

## 概述

### 问题陈述

订单详情页存在以下3个缺陷：
1. **商品明细信息不全**：当前只显示商品名称和图片，缺少单价、数量、单项总价
2. **收货地址未显示**：页面没有展示订单的收货地址信息
3. **去支付跳转错误**：点击"去支付"按钮跳转到了独立的 payment 页面，应跳转到 checkout 单页多步骤流程的 payment step

**QA 补充发现（第一轮 QA 后）**：
4. **订单列表页跳转不一致**：订单列表页（`pages/account/orders/index.vue`）的"去支付"按钮仍指向旧的 `/payment` 路由
5. **500 错误未本地化**：`composables/api/orders.ts` 中的 `getOrderById` 失败时返回固定英文文案，中文环境下应使用 i18n 本地化

### 解决方案

修改订单详情页组件，正确渲染后端 API 返回的完整订单数据：
1. 在商品列表中增加显示 `unitPrice`、`quantity`、`subtotal`
2. 添加收货地址区域，显示 `address.fullAddress`
3. 修正**订单详情页**"去支付"按钮的路由跳转逻辑，改为跳转到 `/checkout?step=payment&orderId=<id>`
4. 修正**订单列表页**"去支付"按钮的路由跳转逻辑，统一使用 `/checkout?step=payment&orderId=<id>`
5. 修复 API 错误处理，使用 i18n 本地化错误文案

### 范围 (包含/排除)

**包含:**
- 订单详情页商品明细UI修复（显示单价/数量/小计）
- 订单详情页收货地址显示区域
- 订单详情页"去支付"按钮路由跳转逻辑修复
- **订单列表页"去支付"按钮路由跳转修复**（新增）
- **API 错误文案本地化**（新增）

**不包含:**
- 后端API修改（后端已提供完整数据）
- Checkout流程本身的改动

---

## 开发上下文

### 现有实现

订单详情页位于：`pages/account/orders/[id].vue` 或类似路径

后端API已提供完整数据（参考 `E:\moxton-ccb\02-api\orders.md`）：
```typescript
interface OrderResponseDTO {
  id: string
  orderNo: string
  customer: { name, email, phone, isGuest }
  address: {
    addressLine1, addressLine2, city, state, postalCode, country, countryCode,
    fullAddress  // <-- 使用这个字段显示完整地址
  } | null
  amount: { total, currency }
  items: [{
    product: { id, name, images: string[] }
    quantity: number      // <-- 购买数量
    unitPrice: number     // <-- 商品单价
    subtotal: number      // <-- 单项总价
  }]
  status: string
  timestamps: { created, updated }
}
```

### API 调用

- **获取订单详情**: `GET /orders/:id` (登录用户) 或 `GET /orders/guest/orders/:id` (游客)
- **认证头**: `Authorization: Bearer <token>` 或 `X-Guest-ID: <guest-id>`

### 依赖项

- 无新增依赖
- 使用既有订单API契约

---

## 技术方案

### Step 1: 定位并分析订单详情页

**目标**: 找到订单详情页组件，理解当前实现

**操作**:
1. 查找订单详情页文件：`pages/account/orders/[id].vue` 或类似路径
2. 查看当前商品列表渲染逻辑
3. 查看当前是否有地址显示区域
4. 查看"去支付"按钮的跳转逻辑

**验收**:
- [ ] 确认订单详情页文件位置
- [ ] 确认当前商品列表渲染方式
- [ ] 确认地址是否已渲染但未显示
- [ ] 确认"去支付"按钮当前跳转目标

---

### Step 2: 修复商品明细显示

**目标**: 在商品列表中显示单价、数量、单项总价

**修改内容**:
1. 在商品项渲染区域添加：
   - 单价显示：`item.unitPrice`（格式化货币）
   - 数量显示：`item.quantity`
   - 小计显示：`item.subtotal`（格式化货币）
2. 格式示例：`$99.00 x 2 = $198.00` 或分栏显示

**代码示例**:
```vue
<!-- 商品项 -->
<div class="flex justify-between items-center">
  <div><!-- 商品图片和名称 --></div>
  <div class="text-right">
    <div>${{ formatPrice(item.unitPrice) }} x {{ item.quantity }}</div>
    <div class="font-bold">${{ formatPrice(item.subtotal) }}</div>
  </div>
</div>
```

**验收**:
- [ ] 每个商品项显示单价
- [ ] 每个商品项显示数量
- [ ] 每个商品项显示单项总价（subtotal）

---

### Step 3: 添加收货地址显示

**目标**: 在订单详情页显示收货地址

**修改内容**:
1. 找到合适的位置添加地址显示区域（通常在订单信息或物流信息附近）
2. 显示 `order.address.fullAddress`
3. 处理 `address` 为 null 的情况（显示"未设置"或隐藏）

**代码示例**:
```vue
<div v-if="order.address" class="address-section">
  <h3>收货地址</h3>
  <p>{{ order.address.fullAddress }}</p>
</div>
<div v-else class="address-section text-gray-500">
  <p>暂无收货地址</p>
</div>
```

**验收**:
- [ ] 有地址时显示 fullAddress
- [ ] 无地址时显示占位文案

---

### Step 4: 修复订单详情页"去支付"跳转逻辑

**目标**: 将订单详情页"去支付"按钮跳转到 checkout 的 payment step

**修改内容**:
1. 找到订单详情页"去支付"按钮的点击事件处理（`pages/account/orders/[id].vue`）
2. 将跳转从 `/payment` 或类似路径改为 `/checkout?step=payment&orderId=<orderId>`

**验收**:
- [ ] 订单详情页点击"去支付"跳转到 checkout 页面
- [ ] checkout 页面显示 payment step（第三步）
- [ ] URL 包含 `orderId` 参数用于恢复订单

---

### Step 5: 修复订单列表页"去支付"跳转逻辑（QA补充）

**目标**: 统一订单列表页的"去支付"跳转逻辑

**修改内容**:
1. 找到订单列表页"去支付"按钮（`pages/account/orders/index.vue:155` 附近）
2. 将 `navigateTo('/payment?orderId=...')` 改为 `navigateTo('/checkout?step=payment&orderId=...')`
3. 确保与订单详情页的跳转逻辑一致

**验收**:
- [ ] 订单列表页点击"去支付"跳转到 checkout payment step
- [ ] URL 包含 `step=payment` 和 `orderId` 参数

---

### Step 6: 修复 API 错误文案本地化（QA补充）

**目标**: `getOrderById` 失败时使用本地化错误文案

**修改内容**:
1. 打开 `composables/api/orders.ts` 找到 `getOrderById` 函数
2. 将固定的英文错误文案 `'Failed to get order details'` 改为使用 i18n
3. 在 `i18n/locales/zh.ts` 和 `i18n/locales/en.ts` 中添加新的翻译键：
   - `api.orders.getOrderFailed`: "获取订单详情失败" / "Failed to get order details"
4. 在订单详情页（`pages/account/orders/[id].vue:187`）确保正确显示本地化错误信息

**验收**:
- [ ] 中文环境下显示中文错误文案
- [ ] 英文环境下显示英文错误文案
- [ ] 错误提示不再硬编码

---

### Step 7: 全量回归验证

**目标**: 确保修复不破坏其他功能

**验证清单**:
1. **商品明细**:
   - [ ] 单价、数量、小计显示正确
   - [ ] 价格和数量变化时计算正确

2. **收货地址**:
   - [ ] 有地址时正常显示
   - [ ] 无地址时显示占位文案

3. **去支付跳转**:
   - [ ] PENDING 状态订单显示"去支付"按钮
   - [ ] 点击后正确跳转到 checkout payment step
   - [ ] 非 PENDING 状态不显示"去支付"按钮

4. **边界场景**:
   - [ ] Console 无错误
   - [ ] 移动端显示正常

---

## 验收标准

| # | 标准 | 验证方式 |
|---|------|---------|
| 1 | 商品明细显示单价、数量、单项总价 | 浏览器查看订单详情页 |
| 2 | 收货地址显示 fullAddress | 浏览器查看订单详情页 |
| 3 | 订单详情页"去支付"按钮跳转到 checkout payment step | 点击按钮验证跳转 |
| 4 | **订单列表页"去支付"按钮跳转到 checkout payment step** | 点击按钮验证跳转 |
| 5 | **API 错误使用本地化文案** | 模拟 500 错误查看提示语言 |
| 6 | Console 无错误 | DevTools Console |
| 7 | 移动端显示正常 | 手机/模拟器测试 |

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| checkout step 参数不确定 | 先查看 checkout 页面实际实现再修改 |
| 货币格式化不一致 | 使用项目中已有的价格格式化函数 |
| address 为 null 导致报错 | 添加 v-if 守卫条件 |

---

## 相关文档

- [订单API文档](../../02-api/orders.md) - 包含 OrderResponseDTO 完整结构
- [项目状态](../../04-projects/nuxt-moxton.md)

## QA 阻塞原因（补充，来自 shop-fe-qa）

- 结论：订单详情页在真实环境接口返回与任务文档/`02-api/orders.md` 契约不一致，导致商品明细与收货地址无法按当前取值渲染（显示 `$0.00` / “暂无收货地址”）。
- 现象位置：
  - `pages/account/orders/[id].vue:114` 使用 `item.unitPrice` / `item.subtotal`；模板渲染（约 `:316`）也直接显示这些字段
  - 页面取 `order.address` 作为结构化地址对象使用
- 真实接口返回（证据）：`E:\nuxt-moxton\05-verification\SHOP-FE-012\shop-fe-qa-order-detail-api-response.json`
  - `data.items[].price`（string）
  - 顶层 `data.address`（string）
  - 另有 `data.addresses[]`（数组）
  - 截图：`E:\nuxt-moxton\05-verification\SHOP-FE-012\qa-order-detail-desktop.png`
- 开发修复建议：
  1) 在 `composables/api/orders.ts` 的 `getOrderById`（或订单详情页取值处）做**兼容映射**：优先使用 `unitPrice/subtotal/address.fullAddress`，缺失时 fallback 到 `price` 计算/`address` 字符串/`addresses[0]`。
  2) 保留已通过的修复：两处“去支付”跳转已统一到 `/checkout?step=payment&orderId=...`，以及 500 错误文案已本地化。
     - 证据：`E:\nuxt-moxton\05-verification\SHOP-FE-012\qa-order-detail-failure-zh.png` / `E:\nuxt-moxton\05-verification\SHOP-FE-012\shop-fe-qa-order-detail-failure-en.png`

<!-- AUTO-QA-SUMMARY:BEGIN -->
## QA 摘要（自动回写）

- 最后更新: `2026-03-17T15:39:02+08:00`
- QA Worker: `shop-fe-qa`
- 路由状态: `blocked`
- 回传摘要: blocker_type=env; question=QA required backend health endpoint http://localhost:3033/health is unreachable, should Team Lead start or restore the API service before QA rerun?; attempted=read role_definition + protocol + task_file + CLAUDE.md + AGENTS.md + E:\moxton-ccb\02-api\orders.md + QA identity pool; collected git status --porcelain and git diff --name-...
- 原始证据仍以 `05-verification/` 中的文件为准。
<!-- AUTO-QA-SUMMARY:END -->
