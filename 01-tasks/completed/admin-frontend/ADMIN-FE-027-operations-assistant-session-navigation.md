# 技术任务：运营助手会话导航与说明文案精简

**任务ID:** ADMIN-FE-027  
**创建时间:** 2026-11-05  
**状态:** completed  
**执行模式:** codex-desktop  
**当前 attempt:** 1  
**角色:** admin-fe-dev  
**项目:** moxton-lotadmin  
**优先级:** P2  
**技术栈:** Vue 3 + TypeScript + SoybeanAdmin + Naive UI  
**QA_LEVEL:** smoke

## 执行上下文

- 工作目录：`E:\moxton-lotadmin`
- 基线提交：`f25449024a7cb63525fae8cbcabfdc7963b52179`；后台原工作区已有多项其他任务改动，本任务开始前均保留，不批量覆盖或回退。
- 允许改动：`src/layouts/modules/operations-assistant/chat-panel.vue`、`src/locales/langs/zh-cn.ts`、`src/locales/langs/en-us.ts`、`src/typings/app.d.ts`、`tests/e2e/operations-assistant.spec.ts`，以及本任务记录和证据。
- 前置依赖：既有运营助手和会话摘要功能已完成；后端当前不支持流式响应。
- 证据目录：`E:\moxton-ccb\05-verification\ADMIN-FE-027\attempt-1\`
- 提交与推送：用户明确要求完成后提交并推送项目工作区；须按来源及文件清单排除生成物和私密文件。

## 问题与方案

当前会话使用下拉框切换，顶部另有“只读查询”标签和说明文字。将会话切换改为可横向滚动的一级标签按钮，保留新建、删除和清空操作；移除截图所示标签与说明。现有后端及客户端使用整段非流式响应，本任务保留此行为。

## 范围

**包含：**

- 以一级菜单式标签切换会话，并清晰显示当前会话。
- 删除“只读查询”标签和其下方说明文字。
- 保持现有会话管理、等待状态、回复卡片及请求生命周期。
- 只运行与本次界面相关的定向 E2E 和必要类型检查。

**不包含：**

- 新增流式协议或修改后端 API。
- 改变权限、数据范围、会话保存规则或其他业务页面。
- 运行与本次改动无关的测试套件。

## 验收标准

- [x] 会话以一级标签形式切换，且可切换回既有会话。
- [x] 截图所示“只读查询”标签和说明不再渲染。
- [x] 新建、删除、清空会话仍可用；整段回复行为不变。
- [x] 定向检查通过，结果及剩余限制写入 attempt 证据。

## 状态记录

- 2026-11-05：设计经用户确认，进入 `in_progress / attempt 1`；开始前已确认三个业务仓有既存改动，逐仓核对提交内容。
- 2026-11-05：一级会话标签已替换下拉选择，目标顶部文案已删除，非流式请求与会话操作不变。定向 Playwright 用例 1/1、`pnpm typecheck`、改动文件 ESLint、`git diff --check` 均通过。主会话复核后按低风险 UI 变更不触发独立 QA，状态 `dev_verified -> completed`。截图：`05-verification/ADMIN-FE-027/attempt-1/ui-session-tabs.png`；摘要：`05-verification/ADMIN-FE-027/summary.md`。
- 同轮按用户指令整理并提交、推送四个项目工作区；生成的测试状态文件与旧构建/报告产物从提交中排除并保存在 CCB 的 `runtime/artifact-backup/2026-11-05/`。
