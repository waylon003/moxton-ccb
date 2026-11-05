# Tech-Spec: 只读运营助手后端

**任务ID:** BACKEND-030
**创建时间:** 2026-11-03
**状态:** completed
**执行模式:** codex-desktop
**当前 attempt:** 2
**角色:** backend-dev / backend-qa
**项目:** moxton-lotapi
**优先级:** P1
**QA_LEVEL:** full

## 上下文与范围

- 目录：`E:\moxton-ccb\runtime\worktrees\backend-assistant`；依赖BACKEND-029及ADMIN-FE-022独立QA通过，父会话派遣前固定新的文件哈希基线。
- 必读：目标AGENTS、角色TOML、桌面工作流、实施计划、`E:\moxton-ccb\02-api\operations-assistant.md`（接口唯一合同）。
- 允许新增Agent路由/控制器/服务/工具与测试、必要配置注册；复用或提取只读查询逻辑，保持旧接口。无schema/迁移/写工具。
- 证据：`05-verification/BACKEND-030/attempt-1/`，开发报告dev-report.md，QA contract/network/failure_path/result.json。不得改文档中心正式记录，契约争议回父会话裁定。

## 要求

完全实现合同的capabilities/chat、六工具、查询/聚合、字段白名单、请求与history校验、角色和用户状态复核、取消与预算、结构化引用/统计。模型固定gpt-6.1-sol，网关Chat Completions使用Node fetch，不引入多Agent/向量库/MCP；配置默认关闭，本地私有env开启。密钥由父会话准备，不输出。

按需编写查询where helper和聚合，不向模型暴露通用DB/HTTP。单轮4模型/6工具/90秒，客户端断开传播AbortSignal，不重试收费调用。同用户1个并发，跨用户互不混淆。可按schema分组也可在服务器安全投影后聚合，但不得把限量页当全集或无限向模型传行；分组≤100，引用最多50，明确结果截断。

回传文本与工具结果都再次限制可发送数据；模型输出不可信，响应引用必须来自本轮实际结果，数字卡片由工具生成；不把模型输出存日志。错误不要落入现有全局errorHandler导致原始body记录：Agent路由应局部处理已知错误并脱敏。

## 验证

用mock先写工具、安全、预算、取消、HTTP权限失败测试；必须覆盖所有六工具、集合统计、null、重复submission、JSON问卷枚举和非法参数。完整npm test/tsc/build退出0。

独立QA通过本地HTTP及Prisma合成记录逐项核对统计。父会话授权本地合成身份/产品/lead/application插入和精确ID清理，不改克隆来的原记录；真实模型仅查询指定合成产品/记录集，不能把客户真实数据送网关。真实请求覆盖完整工具往返。PASS前跑结果校验器。

## 派遣基线

两基线任务独立PASS/校验器通过。助手阶段准确起点按 runtime/assistant-round-20261103/backend-feature-baseline.json 或 admin-feature-baseline.json核对，不按HEAD回退。attempt1证据和开发报告按任务规定。

## 开发交付

开发已冻结9文件manifest；140测试/全量tsc/build/build:full均0，6工具与3合成HTTP/6真实网关请求通过白名单。进入waiting_qa后由主会话派新backend-qa，状态qa/attempt1；证据本任务attempt1/dev-report.md。

## attempt 1 独立QA FAIL及 attempt 2 返修

准确失败记录：`05-verification/BACKEND-030/attempt-1/qa-review/result.json`。三类纯mock复现：phone:紧邻号码/英文Name、first_name、Notes等显式敏感字段可出站（含history）；统计3却允许中文“一百条”回答。最终审查补充证据runtime/assistant-round-20261103/final-code-review.md与final-review-probe。

attempt2只修security.ts、AgentService.ts与相关测试，保留六工具和接口。敏感检查覆盖常见中英文/camelCase/snake_case/分隔形式，不把任意字母:号码当记录ID。日期/规模/真实记录ID继续允许。模型输出同检测并回退；中文数值表述不能绕过来源校验（可对数量/百分比/序数等无法核实文本保守回退，不构建通用事实证明器）。必须先复现失败再修，新增message/history user/assistant、零网关出站、输出回退、合法日期/记录ID及已有分析回归。140+测试、全量tsc/build退出0。新证据仅attempt-2，旧FAIL原样保留。新源码冻结后复核与前端联合验收才可PASS。

## attempt 2开发冻结

仅security/AgentService/tests三文件返修，231全量测试（助手171）/tsc/build/fullbuild均0，9文件新manifest冻结；新QA复核全部缺陷与原功能，不重复attempt1旧证据当新结果。当前qa/attempt2。

## attempt2独立QA PASS

231全量测试、91安全回归、完整tsc/build/fullbuild、原矩阵与新版本真实往返通过；validator valid=true，主会话已读证据和限制。旧attempt1 FAIL完整保留。

## 集成复验与归档

2026-11-04 在集成后的 `E:\moxton-lotapi` 复验：231项测试、全量 TypeScript 检查和默认完整构建均退出0；attempt 2 独立QA及校验器通过。后端私有 `.env` 已启用本地助手并固定 `gpt-6.1-sol`，数据库为本地 `moxton_local`，清理定时任务关闭；生产配置未改。未新增数据库表或执行迁移，现标记 completed。
