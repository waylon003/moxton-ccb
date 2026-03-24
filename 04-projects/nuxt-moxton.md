---
last_verified: 2026-03-24
verified_against: [SHOP-FE-014, SHOP-FE-013, SHOP-FE-012, BACKEND-014, BACKEND-016, SHOP-FE-011, SHOP-FE-010, SHOP-FE-009, SHOP-FE-008, BACKEND-013, SHOP-FE-001]
---

# nuxt-moxton 项目状态

> **项目**: Moxton 商城前端
> **路径**: `E:\nuxt-moxton`
> **类型**: Nuxt 3 应用
> **端口**: 3666
> **状态**: 🟢 活跃

## 项目概述

Moxton 官方商城前端，基于 Nuxt 3 框架构建的现代化电商平台，支持产品浏览、购物车、Stripe 在线支付、订单历史、用户认证等完整购物流程。

## 技术栈

- **框架**: Nuxt 3.20.1
- **语言**: TypeScript (strict mode)
- **CSS**: UnoCSS with Wind preset
- **状态管理**: Pinia 3.0.4
- **UI组件**: Reka UI (无样式组件) + UnoCSS (原子化样式)
- **动画**: VueUse Motion
- **支付**: @stripe/stripe-js (Stripe Elements)

## 当前运行基线（2026-03-24 / SHOP-FE-014）

- 本地 Nuxt dev server 已恢复为 `http://localhost:3666` 可用状态，可作为当前联调入口
- 首页关键资源 `/_nuxt/builds/meta/dev.json` 已在归档任务 QA 摘要中复核返回 `200`
- 首页已无 manifest/hydration error；正常路径 console 无 error（仍保留 4 条既有 Vue warning）
- 本次为运行环境修复任务，不引入新的 API 依赖或契约变化

## 已实现功能模块

| 模块 | 说明 | 状态 |
|------|------|------|
| 用户认证 | 注册、登录、个人信息管理、修改密码 | ✅ 完成 |
| 商品浏览 | 商品列表、分类筛选、搜索、详情页 | ✅ 完成 |
| 购物车 | 添加/删除/修改数量、游客购物车、登录合并 | ✅ 完成 |
| 结账流程 | 收货地址选择、订单创建 | ✅ 完成 |
| Stripe 支付 | Stripe Elements 卡片表单、支付意图智能复用、失败路径本地化与支付结果跳转 | ✅ 完成 |
| 订单历史 | 用户订单列表、订单详情查看 | ✅ 完成 |
| 咨询订单 | 无价格商品咨询表单提交 | ✅ 完成 |
| 收货地址 | 地址 CRUD、默认地址设置 | ✅ 完成 |
| 通知中心 | 通知列表、标记已读 | ✅ 完成 |
| 导航交互（移动端） | 移动端头像下拉、汉堡菜单精简、悬浮搜索按钮拖拽与搜索弹窗联动 | ✅ 完成 |

### Stripe Elements 集成（详细）

通过 `SHOP-FE-001` + `SHOP-FE-013` 任务实现：

- 安装 `@stripe/stripe-js` SDK
- 重写 `CheckoutPayment.vue` 组件，集成 Stripe Elements 卡片表单
- 支付页初始化顺序固定为：先查 `GET /payments/order/:orderId`，存在 `activePayment` 时直接复用
- 当支付查询因网络异常或 `5xx` 失败时，前端降级调用 `POST /payments/stripe/create-intent`
- 若创建接口返回 `Payment already in progress`，前端会再次查询订单支付记录并优先复用新出现的 `activePayment`
- `403` / `404` / 支付初始化失败场景统一映射为本地化提示，避免直接透出后端英文原文
- 支持游客支付（通过 X-Guest-ID 头关联）
- 使用 `automatic_payment_methods` 配置

## 状态管理 (Pinia Stores)

| Store | 说明 |
|-------|------|
| auth | 用户认证状态、Token 管理 |
| cart | 购物车状态、游客 ID 管理 |
| product | 商品列表、筛选条件 |
| order | 订单状态 |
| notification | 通知状态 |

## 依赖的 API

### 后端 API (moxton-lotapi:3033)

联调前默认先检查 `GET /health` 与 `GET /version`，确认本地后端可用；该运行基线已于 2026-03-24 文档同步时再次复核通过。

| API 端点 | 方法 | 用途 |
|---------|------|------|
| `/auth/register` | POST | 用户注册 |
| `/auth/login` | POST | 用户登录 |
| `/auth/profile` | GET/PUT | 用户信息 |
| `/auth/change-password` | POST | 修改密码 |
| `/products` | GET | 商品列表 |
| `/products/:id` | GET | 商品详情 |
| `/categories/tree/active` | GET | 分类树 |
| `/cart/*` | GET/POST/PUT/DELETE | 购物车操作 |
| `/cart/merge` | POST | 合并游客购物车 |
| `/orders` | POST | 创建订单 |
| `/orders/user` | GET | 订单列表 |
| `/orders/:id` | GET | 登录用户订单详情（当前返回 `items[].price`、顶层 `address` 字符串和 `addresses[]`） |
| `/orders/guest/orders` | GET | 游客订单列表 |
| `/orders/guest/orders/:id` | GET | 游客订单详情（返回结构同当前用户订单详情） |
| `/payments/stripe/create-intent` | POST | 在 `activePayment=null` 或支付查询降级时创建支付意图 |
| `/payments/order/:orderId` | GET | 支付页首调接口，用于查询并复用订单活跃支付记录 |
| `/payments/stripe/status/:paymentIntentId` | GET | 查询支付状态 |
| `/addresses` | GET/POST/PUT/DELETE | 收货地址管理 |
| `/addresses/:id/default` | PUT | 设为默认地址 |
| `/notifications/user` | GET | 通知列表 |
| `/notifications/:id/read` | PUT | 标记单条已读 |
| `/notifications/all/read` | PUT | 全部已读 |
| `/notifications/:id` | DELETE | 删除通知 |
| `/offline-orders` | POST | 提交咨询订单 |
| `/offline-orders/guest` | GET | 游客咨询订单列表 |
| `/offline-orders/user` | GET | 用户咨询订单列表 |
| `/offline-orders/user/:id` | GET | 用户咨询订单详情 |
| `/upload/image` | POST | 图片上传 |

## UI 优化记录

- ConsultationModal Material 组件化
- CategorySelect 二级菜单优化（右箭头、自动展开）
- Footer 平板端布局重构（单列居中）
- ProductFilter 平板端横向布局
- ProductCard 高度自适应（移除固定高度，1:1 图片比例）

### 支付链路补充（2026-03-24 / `SHOP-FE-013`）

- `CheckoutPayment.vue` 已落地“先查询后创建”的支付意图解析流程，刷新或返回支付页时优先复用 `activePayment.clientSecret`
- 查询接口在网络异常或 `5xx` 失败时会降级创建新 intent，不阻塞 Stripe Elements 初始化
- 创建接口若返回 `400 Payment already in progress`，前端会立即重查 `GET /payments/order/:orderId` 并复用已存在的活跃 intent
- 支付初始化相关 `403` / `404` / 重复支付错误已映射为中英文产品化文案；依据为 `SHOP-FE-013` QA 摘要与 `E:\nuxt-moxton\components\checkout\CheckoutPayment.vue`

## 最近同步记录（2026-03-24）

- `SHOP-FE-012`：订单详情页兼容当前订单详情真实返回字段，商品金额从 `items[].price` 读取并由前端计算展示值，不再假设接口直接返回 `unitPrice/subtotal`
- `SHOP-FE-012`：收货地址展示优先读取顶层 `address` 字符串，并兼容 `addresses[0].fullAddress`
- `SHOP-FE-012`：订单详情页与订单列表页的“去支付”统一跳转 `/checkout?step=payment&orderId=<id>`
- `SHOP-FE-012`：checkout payment step 通过 `GET /payments/order/:orderId` 恢复订单摘要；订单详情查询失败时前端展示本地化错误文案
- 接口复核：`GET /orders/:id` 与 `GET /orders/guest/orders/:id` 当前仍返回原始订单记录 + `addresses[]`，`POST /orders/checkout` 与管理端订单接口继续使用标准化 `OrderResponseDTO`
- 历史遗漏补记：项目依赖清单此前未显式列出游客订单列表/详情接口，本次已补齐
- `SHOP-FE-014`：前端开发环境恢复，端口 `3666` 上的 Nuxt dev server 已恢复可用，`/_nuxt/builds/meta/dev.json` 稳定返回 `200`
- `SHOP-FE-014`：首页不再出现 manifest/hydration error；QA 摘要确认 `pnpm type-check`、`pnpm build`、`pnpm test:e2e -- tests/e2e/smoke.spec.ts` 已通过
- 接口复核：`SHOP-FE-014` 未引入新的 API 依赖，继续使用既有 `orders`/`payments`/`system` 契约
- `SHOP-FE-013`：支付页新增支付意图智能复用，刷新页面或返回支付页时优先复用 `GET /payments/order/:orderId` 返回的 `activePayment`
- `SHOP-FE-013`：`GET /payments/order/:orderId` 在网络异常或 `5xx` 失败时，前端会降级调用 `POST /payments/stripe/create-intent`
- `SHOP-FE-013`：若创建接口返回 `400 Payment already in progress`，前端会立即重查支付记录并复用新出现的活跃 intent
- `SHOP-FE-013`：支付初始化失败路径补齐中英文产品化提示，不直接展示后端原始英文错误
- 接口复核：`SHOP-FE-013` 未引入新端点，继续依赖 `BACKEND-014` 提供的订单支付查询契约

- `SHOP-FE-011`：移动端地址管理页优化，标题栏“添加地址”按钮改为固定宽度，避免与“收货地址”标题挤压换行
- `SHOP-FE-011`：地址编辑弹窗改为固定 `80vh`，表单内容区独立滚动，底部“保存/取消”按钮固定可见
- `SHOP-FE-011`：地址失败路径（`500`）前端提示使用中文产品化文案，不直接展示后端原始报错
- 接口复核：`SHOP-FE-011` 未引入新的 API 依赖，继续使用既有地址相关契约
- `SHOP-FE-010`：移动端导航栏重构，新增移动端头像下拉菜单并统一为桌面端同款样式（圆角与阴影一致）
- `SHOP-FE-010`：新增 `FloatingSearchButton` 悬浮搜索入口，默认固定左下角并支持拖拽，点击可打开搜索弹窗
- `SHOP-FE-010`：登录 `401` 失败路径前端提示完成本地化，避免直接展示后端原始英文错误文案
- 接口复核：`SHOP-FE-010` 未引入新的 API 依赖，继续使用既有 `auth`/`cart`/`search` 相关契约
- `SHOP-FE-009`：订单记录页与咨询记录页头部布局修复，标题与状态筛选框恢复同一行显示
- `SHOP-FE-009`：状态筛选下拉框宽度改为自适应，不再占据剩余空间
- `SHOP-FE-008`：订单详情页商品图片读取统一为 `item.product.images?.[0]`，不再依赖旧字段 `item.product.image`
- `SHOP-FE-008`：订单相关页面文本箭头 `<-` / `->` 替换为 `Icon` 组件（`heroicons:arrow-left`、`heroicons:arrow-right`）
- 契约依赖：订单项商品图片字段依赖 `BACKEND-013`（`items.product.images: string[]`）
- 接口复核：`SHOP-FE-009` 未引入新的 API 依赖，继续使用既有订单/咨询接口契约

## 相关文档

- [API 文档](../02-api/)
- [集成指南](../03-guides/)
- [项目协调](./COORDINATION.md)
- [依赖关系](./DEPENDENCIES.md)
