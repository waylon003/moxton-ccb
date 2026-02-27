# 2026-02-25 ADMIN-FE QA 验证报告（最终）

- 角色模板：`E:\moxton-docs\.codex\agents\admin-fe-qa.md`
- 仓库范围：`E:\moxton-lotadmin`
- 任务范围：
  - `E:\moxton-docs\01-tasks\active\admin-frontend\ADMIN-FE-006-order-detail-shipping-info-visibility-fix.md`
  - `E:\moxton-docs\01-tasks\active\admin-frontend\ADMIN-FE-007-online-order-history-event-rendering-normalization.md`
- 报告日期：2026-02-25
- 最终结论：`FAIL`

## 1) 身份池与登录执行记录

- 身份池来源：`E:\moxton-docs\05-verification\QA-IDENTITY-POOL.md`
- 管理员验证账号：`admin` / `admin123`（登录成功）
- 非管理员验证账号：`demouser` / `demo123`（登录成功）
- 同角色失败切换（按要求执行）：
  - `testadmin` / `user123` -> `Invalid credentials`
  - `newadmin` / `user123` -> `Invalid credentials`
  - 切换同角色账号 `demouser` / `demo123` -> 登录成功（继续验证）

## 2) 基线检查（模板要求）

1. `pnpm.cmd typecheck`
- 结果：PASS

2. `pnpm.cmd lint`
- 结果：FAIL
- 关键输出：`✖ 178 problems (102 errors, 76 warnings)`（跨多模块历史问题，非本次 006/007 单点改动）

3. `pnpm.cmd build:test`
- 结果：FAIL
- 关键输出：`failed to load config ... Error: spawn EPERM`

4. 兜底：`pnpm.cmd build`
- 结果：FAIL
- 关键输出：`failed to load config ... Error: spawn EPERM`

5. 自动化补充：`pnpm.cmd test:e2e -- --project=chromium`
- 结果：FAIL
- 关键输出：`Error: spawn EPERM`

## 3) 目标场景与回归验证

说明：
- 后端 `127.0.0.1:3033` 可连通；`5173` 未运行。
- 实际使用运行中的前端 `http://127.0.0.1:9527` 完成 UI 验证。

### 3.1 ADMIN-FE-006（物流信息展示修复）

- [x] `DELIVERED` 状态可见物流卡片
  - 样本：`ORD17706329955327253`、`ORD17706257089536007`
- [x] `SHIPPED` 状态可见物流卡片
  - 样本：通过临时状态切换验证 `ORD17701894979891622`（验证后已恢复）
- [x] 有物流数据时正常展示
  - 样本：`ORD17706329955327253`（物流单号/快递/备注可见）
- [x] 无物流数据时显示空态且不隐藏模块
  - 样本：`ORD17701894979891622`（`暂无物流信息` + `补充物流信息`）
- [x] 缺失字段统一 `-`
  - 样本：`ORD17706257089536007`（快递公司/发货备注/交付备注显示 `-`）
- [x] 按钮权限回归
  - `DELIVERED`：无发货/确认收货/取消按钮
  - `CANCELLED`：无发货/确认收货/取消按钮
  - `SHIPPED`：仅显示 `确认收货`
- [x] 详情其他模块无回归
  - 订单信息/客户信息/地址/商品/备注均正常显示

### 3.2 ADMIN-FE-007（历史事件渲染规范化）

- [x] 时间线未出现裸枚举 `SHIPPING_INFO_UPDATED`
  - 页面全文检索结果：`hasRawShippingEnum=false`
- [x] 支付 webhook 历史中文业务文案
  - `Payment completed successfully via Stripe webhook` 已归一为 `Stripe 支付回调确认支付成功`
  - 自动确认文案显示为 `支付成功后系统自动确认订单`
- [x] 物流更新事件友好可读
  - 展示为 `物流信息已更新` / `更新物流信息: ...`，未裸露枚举
- [x] 历史旧数据可读
  - 旧英文记录如 `Order marked as delivered`、`Carrier: N/A, Tracking: N/A` 仍可见
- [x] 时间线排序与颜色语义无回归
  - 时间顺序检查：`isDescending=true`
  - 类型类名仍与 action 语义一致（`info/success`）

## 4) API 交互与权限边界验证

- 管理员：`/orders/admin` 返回 `200`
- 非管理员（`demouser`, role=`user`）：`/orders/admin` 返回 `403`，消息 `Administrator privileges required`
- 前端非管理员进入在线订单页时：列表为空并提示 `Administrator privileges required`

## 5) 失败项（最终）

### F-BASELINE-001
- 路径/动作：`E:\moxton-lotadmin` 执行 `pnpm.cmd lint`
- 实际结果：失败（102 errors / 76 warnings）
- 影响：基线不通过

### F-BASELINE-002
- 路径/动作：`E:\moxton-lotadmin` 执行 `pnpm.cmd build:test`
- 实际结果：`spawn EPERM`
- 影响：测试构建不可用

### F-BASELINE-003
- 路径/动作：`E:\moxton-lotadmin` 执行 `pnpm.cmd build`
- 实际结果：`spawn EPERM`
- 影响：生产构建不可用

### F-AUTO-004
- 路径/动作：`E:\moxton-lotadmin` 执行 `pnpm.cmd test:e2e -- --project=chromium`
- 实际结果：`spawn EPERM`
- 影响：本地命令行 E2E 自动化不可用（已改用 Playwright MCP 手工回归补齐）

## 6) 复测与数据恢复

- 已执行复测：
  - 关键 006/007 UI 场景在 `9527` 端口下复核通过。
- 为构造 `SHIPPED` 场景做过临时状态变更，已恢复：
  - `ORD17706329955327253` -> 恢复 `DELIVERED`
  - `ORD17701894979891622` -> 恢复 `CANCELLED`

## 7) 执行命令清单（核心）

- `pnpm.cmd typecheck`
- `pnpm.cmd lint`
- `pnpm.cmd build:test`
- `pnpm.cmd build`
- `pnpm.cmd test:e2e -- --project=chromium`
- 多条 `node` 脚本用于：登录链路验证、权限校验、订单历史采样、临时场景构造与恢复
- `microsoft/playwright-mcp` 浏览器操作用于 UI 场景与证据捕获

## 8) 最终 PASS/FAIL

- `FAIL`
- 判定依据：
  - 006/007 目标场景与回归验证已完成，功能层面符合任务预期。
  - 但模板要求的基线检查未通过（`lint`、`build:test`、`build`、`test:e2e` 均失败），不能给出发布级 PASS。
