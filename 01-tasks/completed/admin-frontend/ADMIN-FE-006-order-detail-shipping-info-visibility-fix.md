# ADMIN-FE-006：在线订单详情物流信息展示修复

- 日期：2026-02-25
- 角色：admin-frontend
- 项目：moxton-lotadmin
- 优先级：P0

## 背景
当前订单详情页中，物流信息卡片仅在 `order.status === 'SHIPPED'` 时显示。
当订单状态为 `DELIVERED`（已完成）时，即使已有物流单号/物流公司，也会被整块隐藏。

## 问题定义
- 运营和客服在“已完成”订单中无法查看物流信息。
- 用户看到订单完成，但后台无法快速核对物流轨迹。

## 任务范围
- 仅调整前端详情页物流信息展示逻辑。
- 不在本任务中改后端接口。
- 保持现有“可编辑状态限制”不被放宽。

## 实现要求
1. 物流信息模块在 `SHIPPED` 与 `DELIVERED` 两种状态都可见。
2. 有 `metadata.trackingNumber/carrier/shippingNotes` 时正常展示。
3. 无物流数据时显示明确空态提示，不隐藏模块。
4. 保留现有按钮权限规则，避免误开放编辑入口。
5. 缺失字段统一显示 `-`，避免空白行。

## 验收标准
- 已发货、已完成订单均可看到物流信息卡片。
- 发货/确认收货/取消按钮逻辑无回归。
- 不影响详情抽屉其他模块展示。

## 参考
- `E:\moxton-lotadmin\src\views\online-order\modules\online-order-detail.vue`
- `E:\moxton-lotadmin\src\service\api\order.ts`

## 依赖
- 建议与 BACKEND-006 联动，确保详情接口返回 `metadata`。
