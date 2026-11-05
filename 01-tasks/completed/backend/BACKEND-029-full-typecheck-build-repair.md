# Tech-Spec: 后端全量类型与完整构建修复

**任务ID:** BACKEND-029
**创建时间:** 2026-11-03
**状态:** completed
**执行模式:** codex-desktop
**当前 attempt:** 1
**角色:** backend-dev / backend-qa
**项目:** moxton-lotapi
**优先级:** P1
**QA_LEVEL:** full

## 执行上下文

- 工作目录：`E:\moxton-ccb\runtime\worktrees\backend-assistant`；基线 `234a7f5f26745d301fca0eb45ebf5a19e3e98d90`；快照源码与私有配置已恢复。原工作区不得修改。
- 必读：本任务、目标AGENTS.md、文档中心工作流、`.codex/agents/backend-dev.toml`（QA读backend-qa.toml）、`docs/plans/2026-11-03-operations-assistant-implementation.md`。
- 允许：现有报错模块（Cart/Category/Role/Route/Payment/Inquiry、路由/中间件、types、cleanup/addressValidation）、package/tsconfig、必要测试；不改schema/迁移，不实现助手。
- 快照：`runtime/assistant-round-20261103/`；错误基线：`runtime/audits/backend-028-20261103/full-typecheck.log`。
- 证据：`E:\moxton-ccb\05-verification\BACKEND-029\attempt-1\`，开发报告dev-report.md；QA result.json和contract/network/failure_path证据。不得改任务状态/其他仓文件，不再派子代理，不提交推送。

## 目标与实现要求

修复全部156条全量类型错误，保持strict/noUnused等配置；不加ts-ignore、any批量掩盖、不扩大exclude。统一Koa路由Context类型、补准确第三方声明，修复模型继承与默认导出、缺失Customer导出、Cart重复导出与null、Category父级写入、cacheId变量。Role/Route旧控制器无路由无调用且依赖不存在schema，确认引用后移除，不新增角色表。

默认npm run build编译完整src，生成dist/app.js及路由依赖；保留局部配置仅作历史或专项，不当发布构建。node-cron按已安装版本修复为显式启动；模块导入不调度，本地验收可通过`CLEANUP_JOB_ENABLED=false`关闭，默认生产行为保持原计划但不能误在本地启动清理。

测试先复现相关缺陷再修改。依赖node_modules为原仓junction，不允许通过它安装/改生成客户端；需加@types等时优先准确局部.d.ts，不更改原仓依赖。

## 验收

- npm test、`node node_modules/typescript/bin/tsc -p tsconfig.json --noEmit --pretty false`、默认完整build退出0。
- 构建用任务证据目录outDir隔离输出，确认app.js、routes/index.js。用mock或纯只读HTTP验证实际编译应用可初始化并服务health/version；禁止仅smoke假冒完整路由初始化。
- 回归受影响认证/角色、商品、分类、订单、购物车、支付逻辑（外部服务mock）、定时任务不在import启动、地址缓存参数失败路径。
- 数据库不写，若集成只允许本地3307；显式覆盖邮件/Stripe/Redis，日志放证据目录。记录命令/退出码、文件和跨仓影响。

## 恢复与回退

初始planned/attempt0。父会话推进；删除/回退仅限本任务新增内容，按快照逐项恢复，不批量reset或clean。

## 开发交付与QA

开发者已停止源码写入，25项文件manifest已冻结。开发命令60测试/全量tsc/完整build/23条本地只读HTTP均退出0；证据dev-report.md、source-manifest.json。主会话已接收waiting_qa并派新backend-qa，状态qa/attempt1。未测写入集成不冒充通过。

## 独立QA结果

2026-11-03 attempt1 PASS；60测试/全量tsc/完整build/63HTTP/19mock均0，validator valid=true。主会话已阅读qa-review/result及限制，另同步支付文档与AGENTS构建说明。摘要05-verification/BACKEND-029/summary.md。

## 集成复验与归档

2026-11-04 集成至 `E:\moxton-lotapi` 后复验：`npm test`（231项）、`npx tsc -p tsconfig.json --noEmit --pretty false`、`npm run build` 均退出0；生成 `dist/app.js`。独立QA及结果校验器均通过。未执行数据库迁移、业务写入、提交、推送或部署，现标记 completed。
