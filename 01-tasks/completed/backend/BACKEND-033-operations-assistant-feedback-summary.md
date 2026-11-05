# 技术任务：运营助手问卷统计摘要去重

**任务ID:** BACKEND-033
**创建时间:** 2026-11-05
**状态:** completed
**执行模式:** codex-desktop
**当前 attempt:** 1
**角色:** backend-dev
**项目:** moxton-lotapi
**优先级:** P2
**技术栈:** Node.js + Koa + TypeScript + Prisma + MySQL
**QA_LEVEL:** smoke

## 执行上下文

- 工作目录：`E:\moxton-lotapi`
- 基线：`3369c834ac20b53fbf25f41d643a0cf6f1cb1f18`，开始时工作区干净。
- 允许改动：`src/services/agent/AgentService.ts`、`tests/api/agent.spec.ts`，以及本任务证据和摘要。
- 前置依赖：现有六个只读工具、API 响应结构保持不变；问卷统计可按三个 `groupBy` 维度分别查询。
- 证据目录：`E:\moxton-ccb\05-verification\BACKEND-033\attempt-1\`
- 用户授权本轮完成后提交、推送并清理三个业务项目工作区；此次源代码只改后端和后台，其他项目确认干净即可。

## 问题与方案

同一问卷请求可触发多个分组统计工具。逐工具兜底摘要会重复播报相同提交总数，经过事实校验的模型文本也可能逐行重复。要求模型归并同请求下的分组统计；对完全重复的答复行去重；确定性兜底按共同总数合并，明确下方分布会分开呈现。多选分布数不得相加为提交总数。

## 验收标准

- [x] 三个问卷统计分组拥有共同总数时，兜底只报告一次总数。
- [x] 完全重复的模型答复行不会重复返回。
- [x] 模型系统指令要求合并相关分组统计和避免复述相同总数。
- [x] 对话/API 合同及只读安全边界不变；定向 Vitest 与差异检查通过。

## 状态记录

- 2026-11-05：按用户确认方案开始 attempt 1；预先复核数据源、回答校验/兜底和已有测试。
- 2026-11-05：完成问卷统计合并摘要、模型答复完全重复行去重及自然回答规则。两个定向 Vitest、完整 TypeScript 检查与 `git diff --check` 均通过。主会话复核后按 `QA_LEVEL=smoke` 记录开发验证，状态 `dev_verified -> completed`。摘要见 `05-verification/BACKEND-033/summary.md`。
- 中途第一次兜底断言与最终自然文案不一致，更新为行为断言后通过；数据计算与 API 结构未改。未运行全量后端测试或真实网关联调。
