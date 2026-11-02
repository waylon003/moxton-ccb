# Moxton 指挥中心项目指令

## 默认运行方式

- 本项目使用 Codex 桌面主会话讨论需求、制定计划、派遣原生子代理和汇总结果。
- 本文件仅适用于当前文档中心。三个业务仓库各有自己的 AGENTS.md，派遣时须显式要求读取。
- 文档默认中文；Windows 命令使用 PowerShell 7：`C:\Program Files\PowerShell\7\pwsh.exe`。
- 先读 `04-projects/CURRENT-ROUND.md`、`01-tasks/STATUS.md` 和相关 active 任务，再按需读 API、现状报告和代码。
- 详细流程见 `03-guides/codex-desktop-workflow.md`。`.claude`、CLAUDE.md、旧 controller 和 route 系统属于历史入口，不加载为当前指挥规则。

## 仓库和角色

| 标识 | 仓库 | 任务目录 | 开发 / QA 角色 |
|------|------|----------|----------------|
| BACKEND | `E:\moxton-lotapi` | `01-tasks/active/backend` | backend-dev / backend-qa |
| ADMIN-FE | `E:\moxton-lotadmin` | `01-tasks/active/admin-frontend` | admin-fe-dev / admin-fe-qa |
| SHOP-FE | `E:\nuxt-moxton` | `01-tasks/active/shop-frontend` | shop-fe-dev / shop-fe-qa |

## 主会话职责

- 用户提出需求后，先明确会影响结果的范围和验收条件，使用现有模板落地任务。仅请求讨论或计划时不执行开发。
- 用户要求执行时，允许主会话派遣开发和独立 QA 子代理，无需逐次重复征求派遣许可；不替用户创建侧栏新聊天。
- 每次派遣传入任务绝对路径、任务 ID、当前 attempt、角色文件、目标工作区、基线提交、既有改动、允许范围和验收要求。
- 工具支持自定义角色时选用 `.codex/config.toml` 中的角色；不支持时要求子代理读取对应 `.codex/agents/*.toml` 的职责。不能假定角色配置已经热加载。
- 主会话唯一维护任务主记录、STATUS 和 CURRENT-ROUND；子代理不得自行推进状态、归档或改其他任务。
- 每个业务仓库默认最多一个开发写入者；不同仓库只有在无依赖时并行。同仓并发先准备独立 worktree，不在共享目录切换分支。
- worktree 不含原工作区未提交内容，必须先形成可恢复基线。不得回退、清理或覆盖来源不明的修改。
- 子代理遇阻塞向父会话说明分类、已尝试动作和所需决策，不自行无限重试或再派下级代理。

## 状态与交付

- 任务 Markdown 是唯一正式状态源：`planned -> ready -> in_progress -> waiting_qa -> qa -> qa_passed -> completed`；阻塞用 `blocked`，中断先核实再续派。
- 原有 active 任务的 `migration_hold` 表示保留需求、等待核实实际代码，不能根据旧“待开发”标题重新实现。
- 新的重试增加 attempt；拒绝旧 attempt 回报。旧 `TASK-LOCKS.json`、route 日志、pane 和 PID 不参与新任务推进。
- 开发交付包含变更文件、执行命令和退出码、结果、证据、未解决问题及跨仓影响。QA 使用新的子代理上下文，验证准确的提交或工作区。
- 证据放 `05-verification/<TASK-ID>/attempt-<N>/`。脱敏摘要放任务目录的 `summary.md`；原始日志、截图、测试身份和客户数据保持本地。
- QA PASS 前运行 `scripts/validate-desktop-result.py` 校验对应任务、attempt 和证据。未执行、环境阻塞或既有失败均须如实记录，不用 smoke 或局部构建冒充完整业务验收。
- QA 通过进入 qa_passed；主会话复核、接口文档同步并记录集成情况后才能 completed。提交、推送和部署分别记录，不自动推送或部署。
- 每轮结束保存最后完成步骤、准确验证命令、剩余事项和下次入口；恢复不能只靠聊天记忆或子代理 ID。

## 项目范围和工作区

- 不修改用户级 `~/.codex` 配置、全局技能、应用设置或其他项目。新增配置只放当前项目 `.codex`。
- 只写任务授权的业务文件和文档。运行态放 `runtime/`，临时证据不散落源码目录。
- 没有明确业务授权，不访问真实客户数据、发信、付款、改生产状态或数据库迁移。
- 不运行旧 bootstrap、dispatch、archive、watcher；不调用旧 MCP 回传。历史脚本保留供追溯，相关说明见 `03-guides/legacy-orchestration.md`。
