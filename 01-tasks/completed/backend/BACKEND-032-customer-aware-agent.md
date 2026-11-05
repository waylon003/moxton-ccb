# 技术任务：客户业务查询与模型合同

**任务ID:** BACKEND-032
**创建时间:** 2026-11-04
**状态:** completed
**执行模式:** codex-desktop
**当前 attempt:** 1
**角色:** backend-dev / backend-qa
**项目:** moxton-lotapi
**优先级:** P1
**QA_LEVEL:** full

## 执行上下文（强约束）

- 工作目录：`E:\moxton-ccb\runtime\worktrees\backend-agent-customer-032`。
- 基线提交：`234a7f5f26745d301fca0eb45ebf5a19e3e98d90`，另有完整已验收未提交基线34项；对应快照 `runtime/agent-customer-round-20261104/snapshots/backend/manifest.json`，哈希和删除状态已复核。
- 依据模板：`01-tasks/templates/tech-spec-backend.md`；规格及计划已获用户批准，细节以批准规格和固定跨仓合同为准。
- 必读：本任务、目标worktree的AGENTS.md、`03-guides/codex-desktop-workflow.md`、对应`.codex/agents/*.toml`、实施计划、`02-api/operations-assistant.md`（旧隐私禁查合同被本轮批准规格替代）。
- 唯一所有权：下列业务文件及本任务证据；同仓仅此开发者。不是独自在代码库工作，不得回退或覆盖其他既有修改，遇到范围外依赖报父会话。
- 允许文件：
  - `src/services/agent/customer-records.ts`
  - `src/services/agent/security.ts`
  - `src/services/agent/tools.ts`
  - `src/services/agent/AgentService.ts`
  - `src/app.ts`
  - `src/utils/logger.ts`
  - `tests/api/agent.spec.ts`
  - `tests/api/agent-customer-records.spec.ts`

- 证据目录：`E:/moxton-ccb/05-verification/BACKEND-032/attempt-1/`。
- 主会话唯一更新正式状态；不得自行归档、提交、推送、部署或再派下级代理。

## 概述与范围

实现已批准实施计划 Task 1 全部要求。允许当前助手业务域客户姓名、联系方式、地址、备注与反馈查询及必要模型处理。有效admin/operator逐次授权、只读、六工具白名单、gpt-6.1-sol、180/190秒、4模型/6工具上限保持。
完整资料只留当前内存；localStorage仅受控摘要。保留浮窗拖动缩放、即时气泡与跨页请求，不修改浮窗容器、路由、其他业务页或schema。
测试只用合成数据/mock数据库及网关，不访问真实客户、线上模型，不迁移、不发信、不支付、不改私有配置。

## 开发上下文与技术方案

实施计划：`E:/moxton-ccb/docs/superpowers/plans/2026-11-04-customer-aware-operations-assistant.md`。
设计规格：`E:/moxton-ccb/docs/superpowers/specs/2026-11-04-customer-aware-operations-assistant-design.md`。
固定合同：CustomerRecord/CustomerFieldKey、historySummary version=1、summary keys与筛选语义均逐字遵守计划；旧响应兼容。跨仓可按固定合同独立开发。无数据库模型变更。

## 实施步骤

1. 核对Git根/HEAD/overlay，运行并记录指定基线检查，先补新行为测试观察真实RED，再实施GREEN。
2. 按计划Task 1逐项实现，覆盖客户输入/输出、受控边界、失败路径与原功能。
3. 完成验证：npm.cmd test；npx.cmd tsc -p tsconfig.json --noEmit --pretty false；npm.cmd run build；git diff --check。保存准确命令、退出码、日志、冻结变更清单与SHA-256。
4. 返回父会话变更/结果/未覆盖范围；独立新上下文QA验证准确工作区、规范符合性及代码质量，运行validator后才可PASS。

## 验收标准

- [x] 批准计划Task 1的行为与边界均有实际证据；无旧隐私禁查残留。
- [x] 必要客户字段确实进入工具/模型与界面；统计来源真实、缓存/日志无客户详情。
- [x] 权限、注入、取消、异常及旧合同兼容通过。
- [x] 全量验证通过；独立QA证据和validator有效。
- [x] 主会话完成跨仓HTTP、实际截图审阅、受控集成和API/指南同步。

## 风险、回退与恢复

仅按本任务清单差异回退至本轮snapshot，不使用reset/clean。私有恢复资料在runtime本地，不输出配置值。

## 状态流转

- 2026-11-04：planned / attempt0 初始化；完整基线保存后 ready，派遣为 in_progress / attempt1 / QA_LEVEL=full。
- 2026-11-05：开发与独立 QA 完成，状态依次推进 waiting_qa → qa → qa_passed；validator `valid=true`。10 个测试文件 271 项通过，全量类型检查、构建及差异检查均退出码 0。合成跨仓 HTTP/浏览器 66 项断言通过；最终只读审查无 Critical/Important/Minor。文档同步与受控集成完成后归档为 completed。
- 集成文件：8 项，哈希、既有 overlay 与私有配置核对见 `runtime/agent-customer-round-20261104/integration-applied.json`；原工作区其他未提交改动全部保留。
- 脱敏摘要：`05-verification/BACKEND-032/attempt-1/summary.md`；独立 QA：`05-verification/BACKEND-032/attempt-1/qa/result.json`；联合证据：`runtime/agent-customer-round-20261104/joint/joint-report.md`；最终代码审查：`runtime/agent-customer-round-20261104/reviews/final-review.md`。
- 限制：未访问真实客户、真实数据库、真实模型或生产环境；未迁移、发信、支付、提交或推送。
