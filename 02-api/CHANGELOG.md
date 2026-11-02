# API 变更日志

## [未发布]

### 2026-06-29

#### 新增 (Added)
- **产品测试计划申请** - 新增 [product-testing-applications.md](product-testing-applications.md)
  - 记录 AI Sheep Counting Camera 官方产品测试计划申请的数据规则
  - 说明用户侧复用 `POST /preorder-discounts/claim`，通过 `testingProgramOptIn` 和 `testingProgram` 提交可选报名信息
  - 记录测试申请后台列表、详情、状态更新、备注更新、资格邮件发送、导出接口
  - 明确第一版不做筛选结果导入，导出表格保留 `applicationId`，由后台手动搜索和单条发送资格邮件

#### 更新 (Changed)
- **预售预约优惠码** - 更新 [preorder-discounts.md](preorder-discounts.md)
  - 请求体补充 `testingProgramOptIn` 和 `testingProgram` 字段说明
  - 成功响应补充 `testingApplication` 摘要说明
  - 接入方说明补充官网和后台与产品测试申请的联动规则
- **API 索引** - 更新 [README.md](README.md)，加入产品测试计划申请文档入口

### 2026-06-28

#### 新增 (Added)
- **预售预约优惠码** - 新增 [preorder-discounts.md](preorder-discounts.md)
  - 记录用户侧 `POST /preorder-discounts/claim`，提交字段以 `productIds: string[]` 为准，不再使用旧单 `productId` 作为推荐提交字段
  - 说明一次提交可选择 1 到 2 个预售产品，后端按“一产品一 lead、一优惠码、一封邮件”处理
  - 记录逐产品 `items[]` 响应结构，以及 `SENT`、`PENDING`、`FAILED`、`DUPLICATE`、`PARTIAL_DUPLICATE`、`PARTIAL_SENT` 状态语义
  - 记录全部重复错误码 `PREORDER_DISCOUNT_ALREADY_CLAIMED`，以及 `productIds` 缺失、超限、邮箱格式错误、产品不存在、产品不是 `PREORDER` 等常见错误
  - 说明优惠码有效期来自后端配置，本次上线配置为 2026 年 12 月 31 日，前端不要自行推导有效期
  - 记录后台 `GET /preorder-discounts/admin/leads`、`GET /preorder-discounts/admin/leads/:id`、`POST /preorder-discounts/admin/leads/:id/resend`
  - 明确后台重发使用原 lead 的原优惠码，不生成新 code，并返回最新邮件状态

#### 更新 (Changed)
- **商品管理** - 更新 [products.md](products.md)
  - `GET /products/admin/all` 增加 `purchaseMode` 查询参数说明
  - 合法值为 `ONLINE`、`INQUIRY_ONLY`、`PREORDER`
  - 补充 `GET /products/admin/all?purchaseMode=PREORDER` 示例和非法值错误响应
- **API 索引** - 更新 [README.md](README.md)，加入预售预约优惠码文档入口

### 2026-03-24

#### 更新 (Changed)
- **订单管理** - 按 `SHOP-FE-012` 归档补齐用户/游客订单详情接口的历史遗漏说明
  - 修正 `GET /orders/:id`、`GET /orders/guest/orders/:id`：当前返回原始订单详情结构，字段以 `items[].price`、顶层 `address` 字符串和 `addresses[]` 为准，不返回 `unitPrice/subtotal`
  - 补充上述两个端点的常见状态码与错误响应示例（`400/403/404/500`）
  - 明确 `OrderResponseDTO` 仅适用于 `POST /orders/checkout` 与管理端订单接口
  - 依据：`01-tasks/completed/shop-frontend/SHOP-FE-012-order-detail-fixes.md`（含 2026-03-20 QA 摘要与历史问题记录）、`E:/nuxt-moxton/05-verification/SHOP-FE-012/shop-fe-qa-order-detail-api-response.json`、`E:/moxton-lotapi/src/controllers/Order.ts`、`E:/moxton-lotapi/src/transformers/OrderTransformer.ts`
- **前端归档一致性复核** - `SHOP-FE-014` 仅涉及前端开发环境恢复，无 API 契约变更
  - 已复核 `orders.md`、`payments.md` 与 `system.md`：支付页依赖的接口、字段、状态码、错误示例均无需改动
  - 归档依据已回正到 `01-tasks/completed/shop-frontend/SHOP-FE-014-frontend-dev-env-recovery.md`；任务结论为端口 `3666` dev server 恢复、`/_nuxt/builds/meta/dev.json` 返回 `200`、首页无 manifest/hydration error
  - 本次同步仅补齐文档一致性记录，未新增或删除任何 API 端点
- **系统与诊断** - 按 `BACKEND-015` 归档补齐首次修复依据，并结合 `BACKEND-016` 2026-03-24 最新 QA 成功与本地 spot check 刷新运行探针文档
  - 补记历史遗漏：`BACKEND-015` 首次修复 `GET /health`、`GET /version` 的统一 envelope 与 `X-Request-ID`；`BACKEND-016` 为后续复核任务
  - 归档一致性复核：`BACKEND-016` 任务文件已迁移至 `01-tasks/completed/backend/BACKEND-016-start-backend-dev-server.md`，相关依据引用同步回正
  - 复核 `GET /health`、`GET /version` 当前仍返回 `200`，且响应头继续携带 `X-Request-ID`
  - 复核未知根路由错误示例：`GET /health-not-found` 当前仍返回标准 `404` JSON 包
  - 刷新 `system.md` 与 `README.md` 中的最后核对时间、响应头说明、示例时间戳与错误包字段顺序
  - 清理失效的历史说明：`contract-check.json` 现已与 `system.md` 对齐，不再指向 `addresses.md`
  - 依据：`01-tasks/completed/backend/BACKEND-015-fix-uuid-esm-require.md`（2026-03-20 QA 摘要）、`05-verification/BACKEND-015/curl-health.txt`、`05-verification/BACKEND-015/curl-version.txt`、`01-tasks/completed/backend/BACKEND-016-start-backend-dev-server.md`（2026-03-24 QA 摘要）、`05-verification/BACKEND-016/contract-check.json`、`05-verification/BACKEND-016/failure-path.json`、2026-03-24 16:19 +08:00 本地 spot check

### 2026-03-23

#### 更新 (Changed)
- **系统与诊断** - 基于 `BACKEND-016` 最新 QA 成功与本地 spot check 同步运行探针文档
  - 复核 `GET /health`、`GET /version` 当前仍返回 `200`
  - 补充未知根路由错误示例：`GET /health-not-found` 当前返回标准 `404` JSON 包
  - 刷新 `system.md` 与 `README.md` 中的最后核对时间，并保留旧 `contract-check.json` 指向 `addresses.md` 的历史遗漏说明
  - 依据：`01-tasks/completed/backend/BACKEND-016-start-backend-dev-server.md`（QA 摘要）、`05-verification/BACKEND-016/`、2026-03-23 12:40 +08:00 本地 spot check

### 2026-03-03

#### 更新 (Changed)
- **订单管理** - 补齐 `GET /orders/guest/query` 响应示例中的历史遗漏字段
  - `items[].product` 示例补充 `images: string[]`，与 `OrderResponseDTO` 一致
  - 依据：`01-tasks/completed/backend/BACKEND-013-order-images-format.md`、`01-tasks/completed/shop-frontend/SHOP-FE-008.md`
- **前端归档一致性复核** - `SHOP-FE-009` 仅涉及页面布局调整，无 API 契约变更
  - 已复核 `orders` 与 `offline-orders` 相关接口：字段、状态码、错误示例无需改动
  - 依据：`01-tasks/completed/shop-frontend/SHOP-FE-009.md`
- **认证** - 前端归档一致性复核（`SHOP-FE-010`）
  - 已复核 `POST /auth/login`：请求/响应字段、状态码、错误结构无新增变更
  - 在 `auth.md` 补充说明：`401` 可能返回后端英文 `message`（如 `Invalid credentials`），前端需做本地化提示映射
  - 依据：`01-tasks/completed/shop-frontend/SHOP-FE-010-mobile-nav-refactor.md`、`mcp/route-server/data/route-inbox.json`（`SHOP-FE-010` QA `PASS` 回传）
- **收货地址（前端地址管理页）** - 前端归档一致性复核（`SHOP-FE-011`）
  - 已复核地址相关调用：未新增 API 端点，现有地址契约字段与状态码无变更
  - 在 `addresses.md` 补充说明：地址相关失败路径（如 `500`）前端应展示本地化产品文案，避免直接透传后端原始错误信息
  - 依据：`01-tasks/completed/shop-frontend/SHOP-FE-011-mobile-address-fix.md`、`mcp/route-server/data/route-inbox.json`（`SHOP-FE-011` QA `PASS` 回传）

### 2026-03-02

#### 更新 (Changed)
- **订单管理 / 咨询订单** - 同步用户分页接口的已验证行为（BACKEND-012）
  - `GET /orders/user` 与 `GET /offline-orders/user` 增加分页参数行为说明
  - 按 `05-verification/BACKEND-012/contract-check.json` 记录：非法 `pageNum/pageSize` 当前仍返回 `200`（尚未返回 `400`）
- **咨询订单** - 修复 `GET /offline-orders/user` 段落的标题与查询参数说明残缺

### 2026-02-25

#### 更新 (Changed)
- **订单管理** - 更新 `GET /orders/admin/:id` 文档与示例
  - 明确管理员详情返回 `metadata` 安全透传字段：`trackingNumber`、`carrier`、`shippingNotes`、`deliveryNotes`、`shippedAt`、`confirmedAt`
  - 明确 `metadata` 解析失败或为空时返回空对象 `{}`
- **订单管理** - 更新 `GET /orders/admin/:id/history` 历史契约说明
  - 主 `action` 维持稳定集合：`CREATED`、`PAID`、`CONFIRMED`、`SHIPPED`、`DELIVERED`、`CANCELLED`
  - shipping info 更新语义通过 `metadata.operation=SHIPPING_INFO_UPDATED` 与 `reasonCode=ORDER_SHIPPING_INFO_UPDATED` 表达
  - 历史回读兼容旧记录：`SHIPPING_INFO_UPDATED` 归一化为 `SHIPPED`
  - webhook 相关历史使用结构化字段 `metadata.source=STRIPE_WEBHOOK` + `reasonCode`
- **鉴权语义** - 补充管理员端权限失败返回约定
  - HTTP 状态码统一为 `200`，权限错误通过 `body.code=401/403` 表达

### 2026-02-09

#### 新增 (Added)
- **订单管理** - 新增 `PATCH /orders/admin/:id/shipping-info` 接口用于补充/修改物流信息
  - 支持部分更新物流单号、物流公司、发货备注
  - 限制：只有 SHIPPED 状态订单可修改，DELIVERED 状态不可修改
  - 更新后会在订单历史中记录操作
- **订单管理** - 新增 `POST /orders/admin/cleanup-expired` 接口用于手动清理过期订单
  - 手动触发清理超过 15 天的 PENDING 状态订单（待付款过期订单）
  - 返回清理数量和截止日期
  - 定时任务：每天凌晨 2:00 自动执行清理（使用 node-cron）
- **订单管理** - 新增 `GET /orders/admin/:id/history` 接口用于获取订单操作历史
  - 支持按订单 ID 查询所有操作记录
  - 返回操作类型 (action)、操作员 (operator)、备注 (notes) 和元数据 (metadata)
  - 操作类型枚举：CREATED, PAID, CONFIRMED, SHIPPED, DELIVERED, CANCELLED
  - 记录按时间倒序排列

#### 变更信息
- **日期**: 2026-02-09
- **变更者**: backend (BACKEND-004)
- **影响**: 订单物流信息补充/修改功能
- **相关文档**: orders.md

---

## 历史版本

### 2025-02-08
- 添加 `GET /orders/admin/:id` 管理员订单详情接口
- 添加 `orderNo` 字段到 `OrderResponseDTO` 接口定义
- 更新管理员订单列表响应：添加完整 `items` 和 `address` 字段
- 更新发货响应：明确 `trackingNumber` 在 `metadata` 对象中
- 更新确认收货响应：明确 `deliveryNotes` 在 `metadata` 对象中
- 更新状态更新响应：添加 `orderNo` 和完整 `timestamps` 字段
- 添加 `district` 字段到地址结构

### 2025-02-04
- 修正创建订单字段名: `list` → `items`
- 修正管理员路径: 添加 `/admin` 前缀
- 更新响应格式以反映 `OrderTransformer` 标准化
- 统一发货字段名: `carrier`, `notes`
- 统一确认收货字段名: `deliveryNotes`
- 添加详细地址验证规则
- 添加权限验证逻辑说明
