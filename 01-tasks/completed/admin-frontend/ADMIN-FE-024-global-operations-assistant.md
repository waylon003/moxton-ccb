# Tech-Spec：全局悬浮运营助手

**任务ID:** ADMIN-FE-024  
**创建时间:** 2026-11-04  
**状态:** completed
**执行模式:** codex-desktop  
**当前 attempt:** 2  
**角色:** admin-fe-dev / admin-fe-qa  
**项目:** moxton-lotadmin  
**优先级:** P1  
**技术栈:** Vue 3 + Pinia + Vue Router + SoybeanAdmin + Naive UI + Playwright  
**QA_LEVEL:** full

## 执行上下文

- 工作目录：`E:\moxton-ccb\runtime\worktrees\global-ops-admin-024`，分支 `codex/global-ops-admin-024`。
- 基线提交：`f25449024a7cb63525fae8cbcabfdc7963b52179`。原工作区的运营助手集成、业务源码与 `dist.zip` 按 `E:\moxton-ccb\runtime\assistant-round-20261103\integration-applied.json` 精确复制44项，78项集成文件源哈希均已复核；原工作区未改。依赖通过指向原仓 `node_modules` 的本地 junction 复用，不含 `.env` 或密钥。
- 本任务允许改动：
  - 新增 `src/layouts/modules/operations-assistant/index.vue`、`chat-panel.vue`。
  - 将 `src/views/operations-assistant/labels.ts` 移至新模块目录，并删除 `src/views/operations-assistant/index.vue`。
  - 修改 `src/layouts/base-layout/index.vue`、`src/service/api/operations-assistant.ts`、`src/store/modules/operations-assistant/index.ts`、`tests/e2e/operations-assistant.spec.ts`。
  - 从助手 route 删除所需的 `src/router/elegant/routes.ts`、`imports.ts`、`transform.ts`、`src/typings/elegant-router.d.ts`、`src/router/routes/index.ts` 和两份语言文件。
- 任务外的后台文件和已有 `dist.zip` 必须保留。不要运行会自动修改全仓的 `pnpm lint`；使用 `pnpm exec eslint . --no-fix`。
- 必读：本任务、`E:\moxton-lotadmin\AGENTS.md`、`E:\moxton-ccb\03-guides\codex-desktop-workflow.md`、`E:\moxton-ccb\.codex\agents\admin-fe-dev.toml`、`E:\moxton-ccb\02-api\operations-assistant.md`、批准的设计规格 `docs/superpowers/specs/2026-11-04-global-operations-assistant-design.md` 及计划 `docs/superpowers/plans/2026-11-04-global-operations-assistant.md`。
- 后端契约：总预算180000毫秒，浏览器 API/store 截止时间190000毫秒；模型最多4次、工具最多6次，不自动重试。用户已明确采用全局浮窗并移除旧菜单和旧URL。
- 证据：`E:\moxton-ccb\05-verification\ADMIN-FE-024\attempt-2\`；attempt 1 的 FAIL 证据保留在 `attempt-1`。计划简报：`E:\moxton-ccb\.superpowers\sdd\2026-11-04-global-operations-assistant\task-2-brief.md`。
- 开发者不得改任务状态、STATUS、CURRENT-ROUND、API 文档或其它仓库；不得提交、推送、部署或派生下级代理。改动留在本任务 worktree，主会话及独立 QA 复核前不集成回原工作区。

## 目标与方案

把原独立 `/operations-assistant` 页面改为后台全局悬浮按钮和聊天抽屉。组件挂载于持久的 `BaseLayout`，复用现有 Pinia store/API/安全引用/国际化。业务页面导航和关闭窗口不取消请求；用户显式取消、登出、账号变化或权限撤销仍取消。移除旧菜单、route 和生成 RouteKey。

## 范围

**包含：**

- admin/operator 在后台业务页面打开全局抽屉；普通用户、登录/blank layout 不显示入口。
- 抽屉关闭采用 `display-directive="show"` 保持面板和请求生命周期；导航期间组件不卸载。安全引用关闭抽屉后导航。
- 桌面抽屉约520px，窄屏占满视口；保留会话选择、新建、删除、清空、统计、筛选、引用、取消、错误、中英文。
- 前端 HTTP 与 store 截止时间设为190000；能力 mock 为180000。
- 移除助手独立页面、旧菜单/URL 和生成路由类型；保留 `page.operationsAssistant` 文案。
- 将助手 E2E 截图和证据目标改为本任务 attempt-2，不覆盖 ADMIN-FE-023 证据；attempt-1 的失败和返修证据保留。

**不包含：**

- 改后端源码/API响应结构、数据库结构、商城、生产配置或工具能力。
- 将客户详情写入会话历史，或在导航/隐藏窗时取消请求。
- 旧URL重定向；旧 `/operations-assistant` 进入现有404处理。

## TDD 与验收

- [ ] 新增门控响应 E2E：从现有助手页发起请求，切换到商品页后返回助手页；先观察当前卸载取消请求导致断言失败。之后迁移至全局入口，改为发请求、关抽屉、导航、重开，断言同一响应完成一次并显示。
- [ ] 慢于旧100秒但早于190秒的门控请求可以完成并持久化；190001毫秒到期会中止请求且不保存迟到结果。
- [ ] 显式取消、登出、切换账号、角色撤销仍取消；存储按账号隔离、原7天/10会话/10轮规则保留。
- [ ] 引用仍通过 `safeReference`；点击安全引用关闭面板并打开业务详情，恶意URL不导航。
- [ ] admin/operator 看到入口；普通用户、登录 layout 不显示；旧菜单和路由已不存在，旧URL走404。
- [ ] 中英文、窄屏、加载、不可用、失败和历史测试均通过；console error_count=0，正常请求无未处理5xx。
- [ ] `pnpm exec playwright test tests/e2e/operations-assistant.spec.ts --workers=2 --trace on`、`pnpm typecheck`、`pnpm exec eslint . --no-fix`、`pnpm build:test` 均通过；lint 0 errors，warnings不超过既有82条。
- [ ] 构建/路由生成差异限于授权文件；原有未提交源码和 dist.zip 不丢失。
- [ ] 新上下文 admin-fe-qa full 独立验收，保存 ui/console/network/failure_path/result.json 并运行 validator。

## 交付格式

开发报告列出准确工作区/基线/原有改动、授权文件清单和哈希、TDD RED/GREEN、命令与退出码、截图/trace路径和剩余限制。开发者不得自行改任务主状态。
