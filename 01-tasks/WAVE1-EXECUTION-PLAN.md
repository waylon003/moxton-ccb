# WAVE1 EXECUTION PLAN

## 目标
执行当前未完成开发任务：BACKEND-014、BACKEND-015、SHOP-FE-012、SHOP-FE-013，并按依赖顺序完成 QA 验证。

## 依赖分析
- SHOP-FE-013 依赖 BACKEND-014 完成并通过 QA，且 API 文档同步状态为 synced。
- SHOP-FE-012 依赖本机 `http://localhost:3033/health` 可用（BACKEND-016 提供运行态）。
- BACKEND-015 与 BACKEND-014 无直接依赖，可并行推进。

## 波次编排

### Wave 1（并行开发）
**范围**：BACKEND-014 + BACKEND-015 + SHOP-FE-012

1) BACKEND-014（后端）
- QA 驳回点：
  - `validateNoActivePayment()` 未考虑 `expiresAt`，导致“查询后创建”链路仍被阻断。
  - `npm run build` 失败需区分 baseline 与本次引入。
- 目标：修复过期支付意图判定；完成 build gate 归因说明（pre-existing vs 本次引入）。

2) BACKEND-015（后端）
- QA 驳回点：/health 与 /version 响应结构不符合公开契约。
- 目标：修复 health/version 响应结构为标准 envelope；保留 uuid ESM require 修复。

3) SHOP-FE-012（商城前端）
- QA 阻塞点：接口返回与任务契约不一致，需兼容映射；QA 还要求 checkout payment step 能基于 orderId 恢复订单摘要。
- 目标：在 `getOrderById` 或订单详情页取值处做兼容映射；保留已完成的“去支付”跳转与 i18n 修复，并满足订单摘要恢复。

**调度方式**：
- 依次执行 requeue → dispatch（同一时刻只发一条 dispatch 指令）。
- 三个任务可并行执行（由 worker pool 自行并行）。

**Wave 1 QA Gate**：
- 两个任务开发完成后分别 dispatch-qa。

**Doc-updater 触发点**：
- BACKEND-014 QA 成功将触发 doc-updater；需确认 api-doc-sync-state 为 synced 才能进入 Wave 2。

### Wave 2（依赖完成后）
**范围**：SHOP-FE-013

- 前置条件：BACKEND-014 QA 通过且 doc sync 已完成。
- 目标：新增 `getOrderPayment`，修改 `CheckoutPayment.vue` 支付意图初始化逻辑，完善错误处理与 i18n。

**Wave 2 QA Gate**：
- SHOP-FE-013 开发完成后 dispatch-qa。

## 执行命令（待用户确认后执行）
> 仅列出计划命令，实际执行需按顺序逐条运行。

- BACKEND-014
  - requeue: `teamlead-control.ps1 -Action requeue -TaskId BACKEND-014 -TargetState assigned -RequeueReason "qa_fix"`
  - dispatch: `teamlead-control.ps1 -Action dispatch -TaskId BACKEND-014`
  - dispatch-qa: `teamlead-control.ps1 -Action dispatch-qa -TaskId BACKEND-014`

- BACKEND-015
  - requeue: `teamlead-control.ps1 -Action requeue -TaskId BACKEND-015 -TargetState assigned -RequeueReason "qa_fix"`
  - dispatch: `teamlead-control.ps1 -Action dispatch -TaskId BACKEND-015`
  - dispatch-qa: `teamlead-control.ps1 -Action dispatch-qa -TaskId BACKEND-015`

- SHOP-FE-012
  - requeue: `teamlead-control.ps1 -Action requeue -TaskId SHOP-FE-012 -TargetState assigned -RequeueReason "qa_fix"`
  - dispatch: `teamlead-control.ps1 -Action dispatch -TaskId SHOP-FE-012`
  - dispatch-qa: `teamlead-control.ps1 -Action dispatch-qa -TaskId SHOP-FE-012`

- SHOP-FE-013（依赖完成后）
  - dispatch: `teamlead-control.ps1 -Action dispatch -TaskId SHOP-FE-013`
  - dispatch-qa: `teamlead-control.ps1 -Action dispatch-qa -TaskId SHOP-FE-013`

## 完成条件
- BACKEND-014、SHOP-FE-012、SHOP-FE-013 均通过 QA。
- API 文档同步状态满足前端派遣门槛。

## 风险点与处理
- 若出现 pending approval request：必须先处理审批，再继续派遣。
- 若 build gate 失败为 baseline：由后端 worker 以 blocked 回报并说明范围，不在本任务内强行修复。
- SHOP-FE-012 若出现 localhost:3033 不可达：先保障 BACKEND-016 运行态（必要时 requeue BACKEND-016 并 dispatch 维持服务），再重新派遣 QA。
