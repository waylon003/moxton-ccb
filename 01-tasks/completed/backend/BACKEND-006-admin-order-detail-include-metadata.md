# BACKEND-006：管理员订单详情接口补全物流 metadata

- 日期：2026-02-25
- 角色：backend
- 项目：moxton-lotapi
- 优先级：P0

## 背景
物流信息已写入订单 `metadata`（trackingNumber、carrier、shippingNotes 等），
但管理员详情接口 `GET /orders/admin/:id` 经过 `OrderTransformer` 后，存在 metadata 透出不完整风险。

## 问题定义
- 前端详情页依赖 `data.metadata.*` 展示物流信息。
- 若接口不返回 metadata，即使数据库有值也无法展示。

## 任务范围
- 修复管理员订单详情返回结构，确保物流 metadata 可用。
- 保持接口兼容，不破坏现有调用方。

## 实现要求
1. 校验 `getAdminOrderDetail` + `OrderTransformer` 输出结构。
2. 返回至少包含以下字段（有值则返回）：
   - `trackingNumber`
   - `carrier`
   - `shippingNotes`
   - `deliveryNotes`
   - `shippedAt`、`confirmedAt`
3. metadata 缺失或解析失败时需安全兜底，不抛异常。
4. 同步更新 `02-api/orders.md` 示例与字段说明（若响应结构调整）。

## 验收标准
- `GET /orders/admin/:id` 可稳定返回 metadata（存在即回传）。
- metadata 为空时接口行为稳定。
- 不影响列表接口与其他订单接口。

## 参考
- `E:\moxton-lotapi\src\controllers\Order.ts`
- `E:\moxton-lotapi\src\transformers\OrderTransformer.ts`
- `E:\moxton-lotapi\src\models\Order.ts`

## 依赖
- 支撑 ADMIN-FE-006。
