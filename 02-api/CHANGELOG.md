# API 变更日志

## [未发布]

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
