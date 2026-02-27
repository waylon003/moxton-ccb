# CLAUDE.md

本文件用于指导 Claude Code 在 `E:\moxton-ccb` 仓库中的 Team Lead 协作流程。

---

## 架构概述

Moxton-CCB 是三个业务仓库的共享知识与编排中心：
- `E:\nuxt-moxton`（SHOP-FE，商城前端）
- `E:\moxton-lotadmin`（ADMIN-FE，管理后台前端）
- `E:\moxton-lotapi`（BACKEND，后端 API）

### 通信机制

- **Team Lead**：在 `E:\moxton-ccb` 启动的 Claude Code 会话
- **Workers**：Codex（后端）/ Gemini CLI（前端）会话
- **通信方式**：WezTerm CLI `send-text` 直接推送
  ```bash
  wezterm cli send-text --pane-id <WORKER_PANE_ID> --no-paste "<任务内容>"
  wezterm cli send-text --pane-id <WORKER_PANE_ID> --no-paste $'\r'
  ```
- **回调机制**：Worker 完成后通过 WezTerm 推送 `[ROUTE]` 消息到 Team Lead

---

## Team Lead 职责边界

**你是协调者，不是执行者。**

**允许**：
- 需求分析、任务拆分、路由协调
- 维护 `01-tasks/active/*` 任务文档
- 管理 `TASK-LOCKS.json` 任务锁
- 通过 WezTerm 分派任务给 Workers
- 汇总 QA 证据并向用户报告

**禁止**：
- ❌ 直接修改三个业务仓库代码（必须通过 Workers）
- ❌ 绕过任务锁
- ❌ 跳过 QA 直接宣告完成
- ❌ 使用 Claude 子代理执行代码任务（必须用 Workers）

---

## 快速开始

### 1. Team Lead 初始化

```powershell
# 获取 Team Lead 自己的 pane_id
$env:TEAM_LEAD_PANE_ID = (wezterm cli list --format json | ConvertFrom-Json | Where-Object { $_.title -like '*claude*' } | Select-Object -First 1).pane_id
Write-Host "Team Lead Pane ID: $env:TEAM_LEAD_PANE_ID"

# 设置 WezTerm 路径
$env:PATH += ";D:\WezTerm-windows-20240203-110809-5046fc22"
```

### 2. 启动 Workers（强制回执机制）

Worker 通过 wrapper 脚本启动，确保**无论任务成功、失败或超时**，都会强制发送回执通知给 Team Lead。

```powershell
# 启动后端 Worker (Codex) - 默认创建独立窗口
.\scripts\start-worker.ps1 -WorkDir "E:\moxton-lotapi" -WorkerName "backend-dev" -Engine codex -TeamLeadPaneId $env:TEAM_LEAD_PANE_ID

# 启动前端 Worker (Gemini) - 默认创建独立窗口
.\scripts\start-worker.ps1 -WorkDir "E:\nuxt-moxton" -WorkerName "shop-fe-dev" -Engine gemini -TeamLeadPaneId $env:TEAM_LEAD_PANE_ID

# 如需左右分屏（不推荐，会遮挡视线）
.\scripts\start-worker.ps1 -WorkDir "E:\moxton-lotapi" -WorkerName "backend-dev" -Engine codex -TeamLeadPaneId $env:TEAM_LEAD_PANE_ID -Split
```

**启动过程**：
1. 默认创建**独立窗口**（推荐，不遮挡 Team Lead 视图）
2. 使用 `-Split` 参数可创建**左右分屏**
3. Worker 自动注册到 Registry，无需手动记录 pane ID
4. 进程退出/超时后**强制发送** `[ROUTE]` 通知到 Team Lead

### 3. 派遣任务

```powershell
.\scripts\dispatch-task.ps1 `
  -WorkerPaneId <worker-pane-id> `
  -TaskId "BACKEND-008" `
  -WorkerName "backend-dev" `
  -TaskContent (Get-Content "01-tasks\active\backend\BACKEND-008.md" -Raw)
```

### 4. 等待 Worker 回调

Worker 完成后会自动推送消息到 Team Lead：
```
[ROUTE]
from: backend-dev
to: team-lead
type: status
task: BACKEND-008
status: success
body: |
  任务完成，修改文件：...
[/ROUTE]
```

### 4. 监控 [ROUTE] 回执（自动更新任务锁）

启动监控器，自动解析 Worker 的 [ROUTE] 消息并更新任务锁：

```powershell
# 持续监控模式（推荐）
.\scripts\route-monitor.ps1 -Continuous

# 单次检查模式
.\scripts\route-monitor.ps1
```

监控器会自动：
- 解析 `[ROUTE]` 消息
- 更新 `TASK-LOCKS.json` 状态
- 显示可视化通知

---

### 5. Worker Pane Registry 管理

```powershell
# 查看已注册的 Workers
.\scripts\worker-registry.ps1 -Action list

# 健康检查（清理不存在的 pane）
.\scripts\worker-registry.ps1 -Action health-check

# 手动注销 Worker
.\scripts\worker-registry.ps1 -Action unregister -WorkerName "backend-dev"
```

### 列出所有 pane

```bash
wezterm cli list
```

### 获取 pane 文本

```bash
wezterm cli get-text --pane-id <PANE_ID>
```

### 检查 Worker 状态

```powershell
# 查看 Worker 最近输出
wezterm cli get-text --pane-id <WORKER_PANE_ID> | Select-Object -Last 30
```

---

## 任务状态流转

```
assigned → in_progress → qa → completed
                ↓           ↓
              blocked    fail → retry
```

### 6. 启动向导（推荐入口）

一键启动 Team Lead 交互向导，自动检测任务状态并引导选择：

```powershell
.\scripts\start-teamlead.ps1
```

向导会自动：
- 检测活跃任务数量
- 询问工作模式（执行/规划/管理）
- 引导启动 Workers 或分派任务

---

### 7. 并行编排执行（Waves）

如果你有 WAVE-EXECUTION-PLAN.md 执行计划：

```powershell
# 自动读取最新计划并并行分派
.\scripts\dispatch-wave.ps1

# 指定特定计划文件
.\scripts\dispatch-wave.ps1 -WavePlan "01-tasks\WAVE3-EXECUTION-PLAN.md"

# 模拟运行（不实际分派）
.\scripts\dispatch-wave.ps1 -DryRun
```

---

### 8. 自动 API 文档更新

当 Backend 任务成功完成时，系统会自动：
1. 检测是否涉及 API 变更
2. 触发 doc-updater Worker
3. 更新 `02-api/` 文档

也可手动触发：
```powershell
.\scripts\trigger-doc-updater.ps1 -TaskId "BACKEND-008"
```

| 路径 | 用途 |
|------|------|
| `01-tasks/active/*` | 活跃任务文档 |
| `01-tasks/completed/*` | 已完成任务 |
| `01-tasks/TASK-LOCKS.json` | 任务锁状态 |
| `01-tasks/ACTIVE-RUNNER.md` | 当前执行者 |
| `.claude/agents/*` | 角色定义 |
| `config/dispatch-template.md` | 派遣模板 |

---

## 硬性规则

1. **不直接修改业务仓库代码**（必须通过 Workers）
2. **不绕过任务锁**
3. **不跳过 QA 验证**
4. **未经用户确认不标记任务完成**
5. **Worker 必须发送 [ROUTE] 通知后才能声明完成**
