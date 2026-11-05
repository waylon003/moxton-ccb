# Tech-Spec：运营助手三分钟请求预算

**任务ID:** BACKEND-031  
**创建时间:** 2026-11-04  
**状态:** completed
**执行模式:** codex-desktop  
**当前 attempt:** 1  
**角色:** backend-dev / backend-qa  
**项目:** moxton-lotapi  
**优先级:** P1  
**技术栈:** Node.js + Koa + TypeScript + Vitest  
**QA_LEVEL:** full

## 执行上下文

- 工作目录：`E:\moxton-ccb\runtime\worktrees\global-ops-backend-031`，分支 `codex/global-ops-backend-031`。
- 基线提交：`234a7f5f26745d301fca0eb45ebf5a19e3e98d90`。原工作区的未提交后端基线修复与助手完整实现已按 `E:\moxton-ccb\runtime\assistant-round-20261103\integration-applied.json` 精确复制34项（含2项删除），78项集成文件源哈希均已复核；原工作区未改。依赖通过指向原仓 `node_modules` 的本地 junction 复用，不含 `.env` 或密钥。
- 本任务允许改动仅限：`src/services/agent/AgentService.ts`、`tests/api/agent.spec.ts`。API 文档和任务状态由父会话维护。
- 必读：本任务、`E:\moxton-lotapi\AGENTS.md`、`E:\moxton-ccb\03-guides\codex-desktop-workflow.md`、`E:\moxton-ccb\.codex\agents\backend-dev.toml`、`E:\moxton-ccb\02-api\operations-assistant.md` 及实施计划 `docs/superpowers/plans/2026-11-04-global-operations-assistant.md`。
- 固定契约：后端整轮预算180000毫秒，前端预算190000毫秒；模型请求最多4次、工具执行最多6次；不自动重试。
- 证据：`E:\moxton-ccb\05-verification\BACKEND-031\attempt-1\`。计划任务简报位于 `E:\moxton-ccb\.superpowers\sdd\2026-11-04-global-operations-assistant\task-1-brief.md`。
- 开发者不得修改任务状态、STATUS、CURRENT-ROUND、接口文档或其它仓库；不得提交、推送、部署、连接真实模型或访问客户数据；不得派生下级代理。改动留在本任务 worktree，主会话及独立 QA 复核前不集成回原工作区。

## 问题与解决方案

当前 `AgentService` 总预算为90秒，曾有合法复合查询因网关等待接近90秒而触发504。将总时限调整为180秒；同一个 AbortSignal 继续覆盖用户授权、模型调用和数据库工具执行。保持其余限制及取消/失败语义。

## 改动边界

**包含：**

- `LIMITS.timeoutMs` 从90000改为180000。
- 能力接口及其测试反映 `timeoutMs: 180000`。
- 超时测试验证模型调用和授权查询最多等待180秒，预算到期返回504并中止模型请求。
- 无行为变化时不重构其他助手逻辑。

**不包含：**

- 修改模型、工具次数、API路径/包装、取消语义或自动重试策略。
- 修改前端、接口文档、生产配置或数据库。

## 验收

- [ ] 先更新能力与超时行为断言；在旧实现运行定向测试并记录预期 RED。
- [ ] 改动仅限两项授权文件；请求和工具上限未改变。
- [ ] `npm.cmd test -- tests/api/agent.spec.ts` 通过。
- [ ] `npm.cmd test`、`npx.cmd tsc -p tsconfig.json --noEmit --pretty false`、`npm.cmd run build` 退出0。
- [ ] 完整构建仍生成 `dist/app.js`；不运行数据库迁移或真实模型请求。
- [ ] 独立 backend-qa 按 full 验收，保存 contract/network/failure_path/result.json 并运行 validator。

## 交付格式

开发报告记录工作区和基线、允许文件哈希对照、改动、命令/退出码、TDD RED/GREEN 证据、限制。向父会话只回报状态、工作区、测试摘要、疑虑和报告路径；不得自行将任务推进到 QA/PASS。
