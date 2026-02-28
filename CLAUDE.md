# CLAUDE.md

本文件用于指导 Claude Code 在 `E:\moxton-ccb` 仓库中的 Team Lead 协作流程。

---

## Shell 使用规则（必读）

本项目运行在 Windows 上，所有脚本均为 PowerShell (.ps1)。Claude Code 默认 shell 是 bash（Git Bash），直接在 bash 中内联 PowerShell 命令会导致 `$` 变量被 bash 吞掉、引号冲突、中文乱码等不可调试的问题。

**硬性规则：**

1. **执行 .ps1 脚本** — 始终用 `-File`，禁止用 `-Command`：
   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\xxx.ps1" -Arg1 value1
   ```

2. **需要内联 PowerShell 逻辑** — 先写临时 .ps1 文件，再用 `-File` 执行，最后删除：
   ```bash
   # 1. Write tool 写 _temp.ps1
   # 2. powershell -NoProfile -ExecutionPolicy Bypass -File "_temp.ps1"
   # 3. 删除 _temp.ps1
   ```

3. **绝对禁止的模式：**
   ```bash
   # ❌ bash 套 powershell -Command "..." — $ 和引号必崩
   powershell -Command "$files = @('a','b'); foreach($f in $files){...}"

   # ❌ bash 套 powershell -EncodedCommand — 难以维护
   powershell -EncodedCommand <base64>
   ```

4. **简单只读命令例外** — 不含 `$`、不含中文、不含引号嵌套时可用 `-Command`：
   ```bash
   powershell -NoProfile -Command "Get-Date"
   powershell -NoProfile -Command "Test-Path 'E:\moxton-ccb\scripts\xxx.ps1'"
   ```

5. **WezTerm CLI** 是原生命令行工具，可直接在 bash 中调用：
   ```bash
   wezterm cli list --format json
   wezterm cli send-text --pane-id 123 --no-paste "hello"
   ```

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
- **回调机制**：Worker 完成后通过 MCP tool `report_route` 通知 Team Lead，Team Lead 通过 `check_routes` 查询待处理回调

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

## 统一控制器（单入口）

**所有操作必须通过 `teamlead-control.ps1`，禁止直接调用子脚本。**

### 操作表

| 操作 | 命令 |
|------|------|
| 初始化 | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action bootstrap` |
| 派遣开发任务 | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action dispatch -TaskId <ID>` |
| 派遣 QA 任务 | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action dispatch-qa -TaskId <ID>` |
| 查看状态 | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action status` |
| 恢复操作 | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action recover -RecoverAction <reap-stale\|restart-worker\|reset-task>` |
| 补建任务锁 | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action add-lock -TaskId <ID>` |

### 新会话流程

1. 每次新会话**必须先 bootstrap**，否则 hook 会阻止所有操作
2. bootstrap 自动完成：检测 pane ID、健康检查、启动 route-monitor
3. bootstrap 后根据意图选择操作

### 意图识别表

| 用户意图 | 走哪条路 | 操作 |
|----------|---------|------|
| "执行未完成的任务" / "继续开发" | 硬逻辑 | `status` → `dispatch` |
| "派遣 QA" / "验证任务" | 硬逻辑 | `dispatch-qa` |
| "讨论需求" / "规划新功能" | Brainstorming | 读本地文档 → 分析 → 写计划 |
| "查看进度" / "什么状态" | 硬逻辑 | `status` |
| "Worker 挂了" / "任务卡住" | 恢复 | `recover` |

---

## 任务状态流转

```
assigned → in_progress → waiting_qa → qa → completed
                ↓                      ↓
              blocked               fail → retry
```

| 路径 | 用途 |
|------|------|
| `01-tasks/active/*` | 活跃任务文档 |
| `01-tasks/completed/*` | 已完成任务 |
| `01-tasks/TASK-LOCKS.json` | 任务锁状态 |
| `config/worker-map.json` | Worker 角色映射 |
| `config/worker-panels.json` | Worker Pane 注册表 |
| `.claude/agents/*` | 角色定义 |

---

## 硬性规则

1. **不直接修改业务仓库代码**（必须通过 Workers）
2. **不绕过任务锁**
3. **不跳过 QA 验证**
4. **未经用户确认不标记任务完成**
5. **Worker 必须发送 [ROUTE] 通知后才能声明完成**
6. **所有操作必须通过 `teamlead-control.ps1` 统一入口**，禁止直接调用 `start-worker.ps1`、`dispatch-task.ps1`、`route-monitor.ps1` 等子脚本
7. **禁止 `powershell -Command` 执行复杂逻辑**（含 `$`、中文、引号嵌套），只允许 `powershell -File`
8. **禁止手动拼接 `wezterm cli send-text` 命令**，dispatch 由控制器统一处理
