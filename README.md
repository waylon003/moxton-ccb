# Moxton 文档与指挥中心

默认使用 **Codex 桌面主会话 + 原生开发/QA 子代理**，协调后端、管理后台和官网商城。任务、接口约定、验证和交接记录保存为项目文件。

## 从这里开始

1. 在 Codex 桌面打开 `E:\moxton-ccb`，进入或新开主会话。
2. 主会话读取 [AGENTS.md](./AGENTS.md)、[当前轮次](./04-projects/CURRENT-ROUND.md) 和 [任务总览](./01-tasks/STATUS.md)。
3. 描述需求并讨论计划；要求执行后，由主会话派遣开发，按任务风险决定是否安排独立 QA，再汇总结果。

例如：“先讨论后台功能并拆分任务”；“执行确认后的任务，按 QA_LEVEL 验证”；“恢复当前轮次，核对实际代码后继续”。

完整约定见 [Codex 桌面工作流](./03-guides/codex-desktop-workflow.md)。不需要启动旧 bootstrap、WezTerm pane、route-monitor 或 notifier。

## 三个业务仓库

| 标识 | 仓库 | 开发 / QA 角色 |
|------|------|----------------|
| BACKEND | `E:\moxton-lotapi` | backend-dev / backend-qa |
| ADMIN-FE | `E:\moxton-lotadmin` | admin-fe-dev / admin-fe-qa |
| SHOP-FE | `E:\nuxt-moxton` | shop-fe-dev / shop-fe-qa |

角色声明仅位于本项目 [.codex/config.toml](./.codex/config.toml)。模型、权限和全局设置不由该文件覆盖。当前客户端未加载角色选择时，派遣指令显式引用对应角色文件。

## 任务和验收

主会话维护任务状态，任务文件是正式记录。开发子代理必须自测并返回证据；只有 `QA_LEVEL=full` 或主会话判断有风险时，才派独立 QA 使用新上下文检查准确工作区与实际证据。

每仓默认一个开发写入者。无依赖的不同仓任务可以并行；同仓并行先保存当前成果并准备独立 worktree。子代理本身不提供文件隔离。

证据放 `05-verification/<TASK-ID>/attempt-<N>/`，脱敏摘要放同任务目录的 `summary.md`。任务使用 `QA_LEVEL=full|smoke|skip`：`full` 必须独立 QA；`smoke` 由主会话按风险决定；`skip` 只做开发自测和主会话复核。触发独立 QA 时才需要以下 QA PASS 合同：

```powershell
python scripts/validate-desktop-result.py --result 05-verification/<TASK-ID>/attempt-1/result.json --task-id <TASK-ID> --attempt 1 --kind backend
```

`--kind` 可用 backend、frontend、workflow。最后一种只验证指挥流程，不替代业务 QA。结果校验不能代替主会话阅读实际证据。

## 项目资料

- [三项目现状复核](./docs/reports/2026-11-02-project-status-review.md)：2026-11-02 的源码、线上探测和质量问题快照。
- [API 文档](./02-api/README.md)：跨仓接口约定。
- [迁移设计](./docs/plans/2026-11-02-codex-desktop-migration-design.md)与[实施记录](./docs/plans/2026-11-02-codex-desktop-implementation.md)。
- [旧编排系统说明](./03-guides/legacy-orchestration.md)：保留的脚本、规则和状态快照如何处理。

原有四个业务 active 任务处于 migration_hold：主要实现已存在，但部分未提交且未完成专项验收。先核对代码，再决定补验收或开发，不按旧标题重复实现。

## 目录和工作区

`01-tasks` 管任务；`02-api` 管接口；`03-guides` 管流程；`04-projects` 管映射和交接；`05-verification` 管验收；`.codex` 管项目角色；`runtime` 管本地运行态和快照。

正式文档、配置、源码和必要素材纳入 Git。客户线索表格、测试身份、部署产物、日志、PID 和本地数据库保持本地。迁移前快照位于 `runtime/migrations/desktop-20261102-172903/`，原有成果基线为 `4e24b15`。

回归检查：`python -m unittest discover -s tests -p test_desktop_workflow.py -v`。

本项目规则影响文档中心及三个业务仓目录内的会话，不修改其他项目或用户级 Codex 配置。已打开会话若仍引用旧规则，应重新开启或明确读取更新后的指令。会话结束前记录进度，下次从文件恢复；关闭应用后的自动续派不在本版范围。
