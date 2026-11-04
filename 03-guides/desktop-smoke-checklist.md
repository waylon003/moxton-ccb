# 桌面会话恢复检查单

适用于新会话、会话中断和本轮迁移恢复；正式状态由主会话维护。
Windows 命令使用 PowerShell 7：`C:\Program Files\PowerShell\7\pwsh.exe`。

## 入口与基线

- [ ] 读取[根规则](../AGENTS.md)、[当前轮次](../04-projects/CURRENT-ROUND.md)和[状态总览](../01-tasks/STATUS.md)。
- [ ] 打开对应正式任务；本轮迁移已归档为[桌面迁移任务](../01-tasks/completed/coordination/CCB-MIGRATION-001-desktop-workflow.md)，后续任务以当前轮次为准。
- [ ] 按[桌面工作流](./codex-desktop-workflow.md)确认职责、允许文件和验收范围。
- [ ] 在目标工作区执行 `git rev-parse --show-toplevel`，核对准确仓库或 worktree。
- [ ] 执行 `git rev-parse HEAD`，与任务基线核对；本轮文档中心基线为 `4e24b15`。
- [ ] 执行 `git status --short --branch` 和必要差异检查，记录未提交成果，不覆盖来源不明的修改。

## 状态与续派

- [ ] 核对任务执行模式、状态、当前 attempt、最后结果及下次入口；本轮为 attempt 1。
- [ ] 先核实依赖、接口文档和实际产物，确认本次输入包含依赖所需的未提交改动。
- [ ] 遇到 `migration_hold`，先核实实际代码与缺失验收，再由主会话决定入口，不能按旧标题重做。
- [ ] 中断恢复须核对实际产物和仍在执行的工作，不靠聊天记忆、旧子代理 ID 或 running JSON 判断存活。
- [ ] 同一任务只由主会话推进；按[历史入口说明](./legacy-orchestration.md)停用旧 route/controller，不能与原生流程同时推进。
- [ ] 续派须传入任务绝对路径、当前 attempt、角色、工作区、基线、既有改动、允许范围和验收要求。

## 开发交付与按需 QA

- [ ] 开发者直接向父会话回报变更、验证命令与退出码、证据、剩余问题和跨仓影响。
- [ ] 开发者返回自测、类型检查、构建或冒烟命令及退出码、证据、未覆盖场景和剩余风险。
- [ ] 主会话根据 `QA_LEVEL` 和风险决定：`full` 必须独立 QA；`smoke` 可按风险跳过；`skip` 不派 QA。
- [ ] 触发 QA 时，QA 与开发验证同一准确提交或工作区，明确包含的未提交改动；旧 HEAD 不能代表本地交付版本。
- [ ] 触发 QA 时，按任务 ID、attempt 和验收类型运行[结果校验器](../scripts/validate-desktop-result.py)；未触发 QA 时，主会话记录 `dev_verified` 和跳过理由。

## 结束交接

- [ ] 保存最后完成步骤、准确验证命令及退出码、证据路径、剩余事项和下次入口。
- [ ] 由主会话同步任务主记录、STATUS 和 CURRENT-ROUND，保留当前 attempt 的结果。
- [ ] 分别记录任务完成、提交、推送和部署；不默认推送或部署，不凭聊天 success 完成任务。
