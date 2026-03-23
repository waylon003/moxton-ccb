# API 变更日志

## [未发布]

### 2026-03-23

#### 更新 (Changed)
- **系统与诊断** - 基于 `BACKEND-016` 最新 QA 成功与本地 spot check 同步运行探针文档
  - 复核 `GET /health`、`GET /version` 当前仍返回 `200`
  - 补充未知根路由错误示例：`GET /health-not-found` 当前返回标准 `404` JSON 包
  - 刷新 `system.md` 与 `README.md` 中的最后核对时间，并保留旧 `contract-check.json` 指向 `addresses.md` 的历史遗漏说明
  - 依据：`01-tasks/active/backend/BACKEND-016-start-backend-dev-server.md`（QA 摘要）、`05-verification/BACKEND-016/`、2026-03-23 12:40 +08:00 本地 spot check

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
