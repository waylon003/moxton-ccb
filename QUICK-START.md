# Moxton-CCB 快速启动指南

## 系统概述

Moxton-CCB 是一个多 AI 协作的任务编排系统，协调三个业务仓库的开发工作。

**架构**：
- **Team Lead**: Claude Code 会话（在 E:\moxton-ccb）
- **Workers**:
  - Codex — BACKEND（E:\moxton-lotapi）+ ADMIN-FE（E:\moxton-lotadmin）
  - Gemini CLI — SHOP-FE（E:\nuxt-moxton），配有 playwright-mcp
- **QA**: 每个角色有独立 QA worker（BACKEND-QA、ADMIN-FE-QA、SHOP-FE-QA）

## 快速启动（3 步）

### 步骤 1: 启动 Team Lead

```bash
# 在 E:\moxton-ccb 目录启动 Claude Code
cd E:\moxton-ccb
# Claude Code 会自动加载 Team Lead 角色
```

### 步骤 2: 启动 Workers

```powershell
# Codex — 后端 worker
powershell -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\start-codex.ps1" "E:\moxton-lotapi"

# Codex — 管理后台 worker
powershell -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\start-codex.ps1" "E:\moxton-lotadmin"

# Gemini — 商城前端 worker
wezterm cli spawn --cwd "E:\nuxt-moxton" -- cmd /c "gemini"
```

每个 worker 在独立的 WezTerm pane 中运行。用 `wezterm cli list` 查看 pane ID。

### 步骤 3: 创建和分派任务

```bash
# 创建任务
python scripts/assign_task.py --intake "实现订单支付状态查询接口"

# 分派任务（通过 WezTerm send-text）
wezterm cli send-text --pane-id <PANE_ID> --no-paste "<dispatch prompt>"

# 查看 worker 输出
wezterm cli get-text --pane-id <PANE_ID>
```

Dispatch prompt 使用标准模板：`config/dispatch-template.md`

## 完整工作流程

### 1. Planning 模式（无活动任务）

```bash
# 检查当前模式
python scripts/assign_task.py --standard-entry

# 接收需求
python scripts/assign_task.py --intake "需求描述"

# 或拆分跨角色需求
python scripts/assign_task.py --split-request "需求描述"
```

### 2. Execution 模式（有活动任务）

```bash
# 列出活动任务
python scripts/assign_task.py --list

# 分派任务（WezTerm send-text）
wezterm cli send-text --pane-id <PANE_ID> --no-paste "<dispatch prompt>"

# 监控 worker
wezterm cli get-text --pane-id <PANE_ID>
```

### 3. QA 验收

分派给对应角色的 QA worker（BACKEND-QA / ADMIN-FE-QA / SHOP-FE-QA）。

QA 角色定义要求强制运行时验证：
- 后端 QA：curl 实际请求 + 响应证据
- 前端 QA：playwright-mcp 浏览器验证 + 控制台错误检查

### 4. 任务完成清理

QA PASS 后：
1. 归档 QA 报告到 `E:\moxton-ccb\05-verification\ccb-runs\`
2. 删除业务仓库中的 `qa-*` 临时文件（日志、JSON、脚本）
3. 更新任务状态为 completed

## 常用命令

### 诊断和状态

```bash
python scripts/assign_task.py --doctor
python scripts/assign_task.py --show-lock
python scripts/assign_task.py --show-task-locks
python scripts/assign_task.py --list
```

### 任务管理

```bash
python scripts/assign_task.py --intake "需求描述"
python scripts/assign_task.py --split-request "需求描述"
python scripts/assign_task.py --lock-task BACKEND-001 --task-owner team-lead
python scripts/assign_task.py --unlock-task BACKEND-001
```

### Worker 操作

```bash
# 查看所有 pane
wezterm cli list

# 发送命令到 worker
wezterm cli send-text --pane-id <PANE_ID> --no-paste "消息内容"

# 读取 worker 输出
wezterm cli get-text --pane-id <PANE_ID>

# 新建 pane
wezterm cli spawn --cwd "E:\moxton-lotapi" -- cmd /c "python ccb codex"

# CCB 备用方式（仅 Codex）
cd E:\moxton-lotapi
ask codex "<prompt>"
pend codex
cping
```

## Worker 分配

| 角色 | Provider | 仓库 | 说明 |
|------|----------|------|------|
| BACKEND | Codex | E:\moxton-lotapi | 后端开发 |
| BACKEND-QA | Codex | E:\moxton-lotapi | 后端 QA |
| ADMIN-FE | Codex | E:\moxton-lotadmin | 管理后台开发 |
| ADMIN-FE-QA | Codex | E:\moxton-lotadmin | 管理后台 QA |
| SHOP-FE | Gemini | E:\nuxt-moxton | 商城前端开发 |
| SHOP-FE-QA | Gemini | E:\nuxt-moxton | 商城前端 QA（playwright-mcp） |
| DOC-UPDATER | Codex | E:\moxton-ccb | 文档更新 |

详细配置：`config/ccb-routing.json`

## 任务文档结构

```
01-tasks/
├── active/              # 活动任务
│   ├── shop-frontend/
│   ├── admin-frontend/
│   └── backend/
├── completed/           # 已完成任务
│   ├── shop-frontend/
│   ├── admin-frontend/
│   └── backend/
└── templates/           # 任务模板
```

## Team Lead 职责边界

**允许**：需求分析、任务拆分、路由协调、维护任务文档、管理任务锁、分派任务、汇总 QA 证据

**禁止**：直接修改业务仓库代码、绕过任务锁、跳过 QA 验证、未经用户确认标记完成

## 故障排查

| 问题 | 排查方式 |
|------|---------|
| Worker 无响应 | `wezterm cli list` 检查 pane 是否存活 |
| Codex 卡审批 | 检查 `~/.codex/config.toml` 的 `approval_policy` |
| Gemini MCP 不生效 | 检查 `~/.gemini/settings.json` 的 `mcpServers`，重启 Gemini |
| 任务分派失败 | `python scripts/assign_task.py --show-task-locks` |
| Pane 丢失 | `wezterm cli spawn` 重建 |

## 相关文档

- `CLAUDE.md` — Team Lead 工作流程指南
- `config/dispatch-template.md` — 标准 dispatch 模板
- `config/ccb-routing.json` — Worker 路由配置
- `.claude/agents/*` — 角色定义文件
- `docs/reports/DOCUMENTATION-INDEX.md` — 完整文档索引
