# Moxton-CCB 指挥中心

本仓库是三个业务仓库的共享知识与编排中心：
- `E:\nuxt-moxton`（SHOP-FE，商城前端）
- `E:\moxton-lotadmin`（ADMIN-FE，管理后台前端）
- `E:\moxton-lotapi`（BACKEND，后端 API）

架构说明：
- Team Lead：在 `E:\moxton-ccb` 启动的 Claude Code 会话
- Workers：
  - Codex — 负责 BACKEND（开发+QA）和 ADMIN-FE（开发+QA）
  - Gemini CLI — 负责 SHOP-FE（开发+QA），配有 playwright-mcp
- 通信方式：WezTerm `send-text`（主要）/ CCB `ask`（Codex 备用）
- 状态来源：`01-tasks/*` 与 `01-tasks/TASK-LOCKS.json`

## Quick Start

1. 安装 WezTerm 和 CCB（一次性设置），确保 Gemini CLI 已安装

2. 启动 Claude Code 作为 Team Lead:
```bash
cd E:\moxton-ccb
# Claude Code 会自动加载 Team Lead 角色
```

3. 启动 Workers:
```powershell
# Codex workers（后端 + 管理后台）
powershell -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\start-codex.ps1" "E:\moxton-lotapi"
powershell -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\start-codex.ps1" "E:\moxton-lotadmin"

# Gemini worker（商城前端）
wezterm cli spawn --cwd "E:\nuxt-moxton" -- cmd /c "gemini"
```

4. 创建和分派任务:
```bash
# 创建任务
python scripts/assign_task.py --intake "实现订单支付状态查询接口"

# 分派任务（通过 WezTerm send-text）
wezterm cli send-text --pane-id <PANE_ID> --no-paste "<dispatch prompt>"

# 查看 worker 状态
wezterm cli get-text --pane-id <PANE_ID>
```

标准 dispatch 模板见：`config/dispatch-template.md`

## Team Lead 工作流

规划模式（无 active 任务）：
- 讨论需求
- 拆分任务模板
- 让用户确认是否进入执行

执行模式（存在 active 任务）：
- 分派任务（WezTerm send-text 或 CCB ask）
- 监控 worker 状态（wezterm cli get-text）
- 推进任务锁状态：`assigned -> in_progress -> qa -> completed/blocked`
- QA PASS 后归档报告到 `05-verification/ccb-runs/`，清理业务仓库临时文件

## 常用命令

```bash
python scripts/assign_task.py --standard-entry
python scripts/assign_task.py --list
python scripts/assign_task.py --scan
python scripts/assign_task.py --show-lock
python scripts/assign_task.py --show-task-locks
python scripts/assign_task.py --doctor
python scripts/assign_task.py --split-request "<requirement text>"
```

## Worker 分配

| 角色 | Provider | 仓库 | 说明 |
|------|----------|------|------|
| BACKEND | Codex | E:\moxton-lotapi | 后端开发 |
| BACKEND-QA | Codex | E:\moxton-lotapi | 后端 QA |
| ADMIN-FE | Codex | E:\moxton-lotadmin | 管理后台开发 |
| ADMIN-FE-QA | Codex | E:\moxton-lotadmin | 管理后台 QA |
| SHOP-FE | Gemini | E:\nuxt-moxton | 商城前端开发 |
| SHOP-FE-QA | Gemini | E:\nuxt-moxton | 商城前端 QA |
| DOC-UPDATER | Codex | E:\moxton-ccb | 文档更新 |

详细配置见：`config/ccb-routing.json`

## 关键路径

- `01-tasks/active/*` — 活动任务
- `01-tasks/completed/*` — 已完成任务
- `01-tasks/ACTIVE-RUNNER.md`
- `01-tasks/TASK-LOCKS.json`
- `05-verification/ccb-runs/*` — QA 报告归档
- `.claude/agents/*` — 角色定义
- `config/ccb-routing.json` — Worker 路由配置
- `config/dispatch-template.md` — 标准 dispatch 模板

## 故障排查

1. `doctor` 失败
- 执行 `python scripts/assign_task.py --doctor`
- 按输出修复缺失文件或配置

2. `dispatch` 被阻塞
- 检查 `python scripts/assign_task.py --show-lock`
- 检查 `python scripts/assign_task.py --show-task-locks`
- 确保 runner 为 `claude`

3. Codex 子代理卡审批
- 检查 `~/.codex/config.toml` 中项目段是否有 `approval_policy = "never"` 和 `sandbox_mode = "danger-full-access"`

4. WezTerm pane 丢失
- `wezterm cli list` 查看存活 pane
- 用 `wezterm cli spawn` 重建

5. Gemini MCP 不生效
- 检查 `~/.gemini/settings.json` 中 `mcpServers` 配置
- 重启 Gemini CLI 使配置生效

## 文档导航

- **[QUICK-START.md](./QUICK-START.md)** - 快速启动指南
- **[CLAUDE.md](./CLAUDE.md)** - Team Lead 工作流程指南
- **[config/dispatch-template.md](./config/dispatch-template.md)** - Dispatch 模板
- **[config/ccb-routing.json](./config/ccb-routing.json)** - Worker 路由配置
- **[docs/reports/DOCUMENTATION-INDEX.md](./docs/reports/DOCUMENTATION-INDEX.md)** - 完整文档索引

### CCB 相关文档
- [CCB 迁移完成报告](./docs/ccb/CCB-MIGRATION-COMPLETE.md)
- [CCB 安装指南](./docs/ccb/CCB-INSTALLATION-GUIDE.md)

## Team Lead 边界

- Team Lead 负责协调，不直接改业务仓库代码
- 不绕过任务锁
- 不跳过 QA 证据
- 未经用户确认不标记完成
