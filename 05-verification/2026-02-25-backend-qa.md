# 2026-02-25 BACKEND QA 验证报告（最终）

- 角色：BACKEND QA（严格按 `E:\moxton-docs\.codex\agents\backend-qa.md` 新版模板执行）
- 代码仓库：`E:\moxton-lotapi`
- 任务：
  - `BACKEND-006-admin-order-detail-include-metadata`
  - `BACKEND-007-online-order-history-event-contract-normalization`
- 身份池：`E:\moxton-docs\05-verification\QA-IDENTITY-POOL.md`
- 报告日期：2026-02-25

## 1) 环境预检（模板步骤 4）

- 命令：
  - `node -e "const {spawnSync}=require('node:child_process');const r=spawnSync(process.execPath,['-v']);console.log(r.error?.code||'OK')"`
- 输出：`EPERM`
- 判定：`ENV_BLOCKED`（模板规则命中）
- 继续执行：按模板继续做非 spawn 路径证据收集与接口验收。

补充可用性检查：
- `node -v` => `v25.6.0`
- `GET http://localhost:3033/health` => `code=200`

## 2) 模板基线执行

1. `npm run build`
- 结果：失败（PowerShell 执行策略拦截 `npm.ps1`）
- 失败分类：`env_blocker`

2. `cmd /c npm run build`（同一基线命令的可执行等价方式）
- 结果：FAIL
- 关键现象：TypeScript 编译错误 242 条（示例：`src/controllers/Cart.ts`, `src/controllers/Order.ts`, `src/routes/*.ts`, `src/services/*.ts`）
- 失败分类：`regression`

3. 自动化优先路径（Vitest）
- MCP 可用性检查：无可用 MCP server（`list_mcp_resources`/`list_mcp_resource_templates` 均为空）
- 回退命令：`cmd /c npm run test:api`
- 结果：FAIL（`spawn EPERM`，Vitest 配置加载阶段被阻断）
- 失败分类：`env_blocker`

## 3) 身份池与登录回退证据

- admin 候选：`admin/admin123` 登录成功（`code=200`）
- user 候选回退链路（符合“同角色失败先回退”规则）：
  1. `demouser/test123` => `code=401`（Invalid credentials）
  2. `testuser2/test123` => `code=200`（Login successful）

## 4) 契约矩阵（含 403、metadata 为空、webhook 结构化）

| 任务 | 用例 | 接口 | 结果 | 关键证据 |
|---|---|---|---|---|
| BACKEND-006 | metadata 存在即回传 | `GET /orders/admin/:id` | PASS | 返回 `trackingNumber/carrier/shippingNotes/deliveryNotes/shippedAt/confirmedAt` |
| BACKEND-006 | metadata 为空时稳定 | `GET /orders/admin/:id` | PASS | `data.metadata = {}`，`code=200` |
| BACKEND-006 | 列表兼容性 | `GET /orders/admin?pageNum=1&pageSize=5` | PASS | `code=200`，`data.list` 为数组 |
| 权限 | 非管理员访问 admin detail | `GET /orders/admin/:id` | PASS | HTTP=200 + `body.code=403`，`Administrator privileges required` |
| 权限 | 未带 token 访问 admin detail | `GET /orders/admin/:id` | PASS | HTTP=200 + `body.code=401`，`No token provided` |
| BACKEND-007 | webhook 结构化契约 | `GET /orders/admin/:id/history` | PASS | 存在 `metadata.source=STRIPE_WEBHOOK`，且 `reasonCode=PAYMENT_STRIPE_SUCCEEDED / ORDER_AUTO_CONFIRMED_AFTER_PAYMENT` |
| BACKEND-007 | 旧 action 兼容归一化 | `GET /orders/admin/:id/history` | PASS | 历史 `SHIPPING_INFO_UPDATED` 回读为 `action=SHIPPED` + `reasonCode=ORDER_SHIPPING_INFO_UPDATED` |

## 5) 失败详情（Expected vs Actual）

1. 命令：`npm run build`
- Expected：命令可执行并进入 TypeScript 编译阶段
- Actual：被 PowerShell 执行策略拦截（`npm.ps1` 无法加载）
- 分类：`env_blocker`

2. 命令：`cmd /c npm run build`
- Expected：`tsc` 通过，退出码 0
- Actual：`tsc` 失败，242 条编译错误，退出码 1
- 分类：`regression`

3. 命令：`cmd /c npm run test:api`
- Expected：Vitest/Supertest 套件执行并给出测试结果
- Actual：Vite/Vitest 启动时报 `spawn EPERM`，无法进入测试执行
- 分类：`env_blocker`

## 6) 下游影响风险（frontend/admin）

1. 当前鉴权语义仍是 HTTP 200 + `body.code`（401/403）；前端需继续按业务码处理权限失败。
2. 仓库整体 TypeScript 基线未通过，存在发布门禁风险；即使 006/007 契约通过，也不满足全局基线质量门槛。

## 7) 证据与清理

- 结构化证据：`E:\moxton-lotapi\qa-backend-006-007-evidence.json`
- 证据生成时间（UTC）：`2026-02-25T14:14:51.894Z`
- QA 临时样本清理复核：
  - `orderCount=0`
  - `historyCount=0`

## 8) 最终判定

**FAIL**

- BACKEND-006/007 契约矩阵全部通过。
- 但模板基线 `npm run build`（等价执行 `cmd /c npm run build`）出现真实编译回归（`regression`），按模板最终判定为 **FAIL**（不是 BLOCKED）。

## 9) 协议回传（ROUTE）

```text
[ROUTE]
from: backend-qa
to: team-lead
type: review
task: BACKEND-006,BACKEND-007
body: 合同矩阵通过（含 403、metadata 空对象、webhook 结构化与旧 action 归一化）；基线构建存在 regression（tsc 242 errors）；自动化 test:api 存在 env_blocker（spawn EPERM）；最终判定 FAIL。
[/ROUTE]
```
