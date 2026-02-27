# ADMIN-FE-007：在线订单操作历史展示规范化

- 日期：2026-02-25
- 角色：admin-frontend
- 项目：moxton-lotadmin
- 优先级：P0

## 背景
当前操作历史时间线依赖固定 action 映射，并直接显示后端返回 `notes`。
已出现：
- `SHIPPING_INFO_UPDATED` 枚举值直接暴露在 UI；
- `Payment completed successfully via Stripe webhook` 英文文案直接展示。

## 问题定义
- 前端对“新事件类型/未知枚举”兼容不足。
- 用户可见文案缺乏本地化和产品语义。

## 任务范围
- 优化历史时间线的 action 与 notes 渲染策略。
- 与后端新契约对齐，同时兼容历史旧数据。

## 实现要求
1. 增加 action 映射兜底文案，避免直接裸显示枚举值。
2. 支持“物流补充/修改”类事件的友好展示。
3. 对支付 webhook 相关历史展示做本地化处理（优先读 reasonCode/metadata）。
4. 历史旧记录继续可读，不引入不可见数据。
5. 不改变时间线排序和颜色语义。

## 验收标准
- 时间线不再出现未翻译的 `SHIPPING_INFO_UPDATED`。
- 支付回调相关记录展示为中文业务文案。
- 旧数据记录仍可正常浏览。

## 参考
- `E:\moxton-lotadmin\src\views\online-order\modules\online-order-history.vue`
- `E:\moxton-lotadmin\src\service\api\order.ts`

## 依赖
- 与 BACKEND-007 联动。
