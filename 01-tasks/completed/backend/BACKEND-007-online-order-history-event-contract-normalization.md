# BACKEND-007：在线订单操作历史事件契约规范化

- 日期：2026-02-25
- 角色：backend
- 项目：moxton-lotapi
- 优先级：P0

## 背景
在线订单历史目前把“状态流转事件”和“操作事件”都写在 `action`，并把部分系统内部文案直接写入 `notes`。
已出现问题：
- `SHIPPING_INFO_UPDATED` 与既有 action 集不一致；
- `Payment completed successfully via Stripe webhook` 直接暴露给管理端用户。

## 问题定义
- 事件契约与前端映射不一致，导致展示异常。
- 系统日志语义与用户文案语义混用。

## 任务范围
- 规范 shipping-info 与 payment webhook 两条写历史路径。
- 建立兼容策略，保障旧记录可读。

## 实现要求
1. 明确在线订单历史事件契约：
   - 主 `action` 保持稳定集合；
   - 扩展操作语义放入结构化字段（如 metadata.operation/reasonCode）。
2. shipping-info 更新路径避免无文档新增 action 破坏契约。
3. Stripe webhook 路径不再把内部英文句子作为最终展示 notes。
4. 历史接口对老数据保持兼容展示。
5. 更新 `02-api/orders.md` 中历史 action 与 metadata 说明。

## 验收标准
- 历史接口不再输出未约定 action 造成前端裸显示。
- 支付回调相关记录具备可本地化展示信息（reasonCode/结构化字段）。
- 旧记录可继续显示且不报错。

## 参考
- `E:\moxton-lotapi\src\controllers\Order.ts`
- `E:\moxton-lotapi\src\services\StripePaymentService.ts`
- `E:\moxton-lotapi\src\controllers\Payment.ts`
- `E:\moxton-lotapi\prisma\schema.prisma`

## 依赖
- 与 ADMIN-FE-007 对齐。
