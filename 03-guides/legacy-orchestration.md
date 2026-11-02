# 旧编排系统保留说明

## 当前边界

默认主指挥已改为 Codex 桌面主会话，使用原生子代理。旧 `.claude`、`CLAUDE.md`、WezTerm 控制器、MCP route、watcher 和任务锁不再管理新任务。

旧脚本和角色先保留，不移动或删除，以便追溯既有任务、证据合同和历史问题。入口变更通过 README、根规则、活动模板和三个业务仓协议完成；本项目 Claude hooks 已清空。旧 README、CLAUDE 规则和索引已归档到 `docs/legacy`。

## 不再作为默认入口的文件

- `scripts/teamlead-control.ps1` 及旧 dispatch、headless runner、trigger 脚本。
- `scripts/route-monitor.ps1`、`route-notifier.ps1` 和 Rich watcher。
- `.claude/agents`、`.claude/skills`、`.claude/hooks` 中的旧指挥规则。
- `01-tasks/TASK-LOCKS.json`、`config` 内旧心跳和 `mcp/route-server/data` 内状态。

这些文件中仍可能出现 Claude 专属限制和旧状态。它们仅描述历史机制，当前任务不读取其限制、不写其状态。MCP 服务配置保留但新流程不要求调用；未修改用户级 MCP 注册。

## 可继续复用的资产

任务内容、API 契约、仓库映射、适用的验证标准和 `validate-qa-evidence.ps1` 可按需复用。新的 QA 报告优先使用 `validate-desktop-result.py`，其校验包含任务和 attempt；旧脚本不能替代新的结果合同。

## 本地状态和恢复

迁移前四仓文件快照及 patch 位于 `runtime/migrations/desktop-20261102-172903`。旧状态、原始证据、客户表格、部署包和本地数据库保留在原路径，忽略或取消跟踪不会删除磁盘文件。

迁移检查使用实际进程命令行识别旧 watcher；没有把旧 JSON 的 running 当成存活结论，也不根据 PID 文件直接终止进程。若以后发现旧 watcher 仍在运行，先核对完整进程命令和任务归属，再由主会话处理，避免误伤其他会话。

需要研究旧系统时，从基线 `4e24b15` 和快照读取。恢复旧执行链路属于新的明确变更，不能只启动旧 bootstrap 让两套状态写入者同时运行。
