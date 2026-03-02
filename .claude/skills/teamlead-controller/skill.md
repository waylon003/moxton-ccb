---
name: teamlead-controller
description: Team Lead 统一控制器 - 所有操作的单一入口
triggers:
  - bootstrap
  - dispatch
  - dispatch-qa
  - repo-committer
  - archive
  - status
  - recover
  - add-lock
---

# Team Lead 控制器技能

## 目的

强制 Team Lead 所有操作走单一入口。
避免常见错误：bash/PowerShell 转义冲突、直接调用子脚本、手工拼接 wezterm 派遣命令。

## 操作映射

| 意图 | Action | 命令 |
|--------|--------|---------|
| 新会话初始化 | bootstrap | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action bootstrap` |
| 派遣开发任务 | dispatch | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action dispatch -TaskId <ID>` |
| 派遣 QA 任务 | dispatch-qa | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action dispatch-qa -TaskId <ID>` |
| 派遣 repo-committer | repo-committer | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\trigger-repo-committer.ps1" -TaskId <ID> -Force` |
| 归档并提交/推送 | archive | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action archive -TaskId <ID>` |
| 查看状态 | status | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action status` |
| 清理僵尸 Worker | recover | `... -Action recover -RecoverAction reap-stale` |
| 重启 Worker | recover | `... -Action recover -RecoverAction restart-worker -WorkerName <name>` |
| 重置任务状态 | recover | `... -Action recover -RecoverAction reset-task -TaskId <ID> -TargetState assigned` |
| 补建任务锁 | add-lock | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action add-lock -TaskId <ID>` |

## 意图识别

用户表达意图后，映射到正确分支：

| 关键词模式 | 分支 |
|---------|--------|
| "execute", "continue", "dispatch", "run tasks" | 执行分支：status -> dispatch |
| "QA", "verify", "test", "validate" | 执行分支：dispatch-qa |
| "discuss", "plan", "design", "brainstorm" | 规划分支：仅读 CCB 文档 -> planning-gate -> 任务模板落地 |
| "status", "progress", "what's happening" | 状态分支：status |
| "stuck", "broken", "restart", "reset" | 恢复分支：recover |

## 禁止行为

1. **禁止**直接调用子脚本：
   - `start-worker.ps1`：改用控制器 `bootstrap` 或 `recover -RecoverAction restart-worker`
   - `dispatch-task.ps1`：改用控制器 `dispatch`
   - `route-monitor.ps1`：由控制器 `bootstrap` 管理
   - `worker-registry.ps1`：改用控制器 `status` 或 `recover`

2. **禁止**使用 `powershell -Command` 执行复杂逻辑（变量、中文、嵌套引号）

3. **禁止**手工拼接 `wezterm cli send-text` 进行任务派遣

4. **禁止**在新会话跳过 bootstrap

5. **禁止**使用 `Task(...)` / `Backgrounded agent` 进行 Team Lead 派遣
   - 包括："Task(Dispatch ...)"、"Backgrounded agent"、子代理委派
   - 必须路径：仅在主进程运行控制器/触发脚本
   - repo 提交场景：必须使用 `trigger-repo-committer.ps1`

6. **禁止**无退出条件轮询 Worker 输出
   - 同一 pane 的 `get-text` 连续 3 次无变化必须停止
   - 同一 task 的 `check_routes` 连续 3 次无 pending 必须停止
   - 停止后转 `status -> recover`，不得继续同样轮询

## 结构化输出模板

每次控制器动作后，按以下模板汇报：

```
Action: <action performed>
Result: <success/fail>
Details: <brief summary>
Next: <suggested next action>
```
