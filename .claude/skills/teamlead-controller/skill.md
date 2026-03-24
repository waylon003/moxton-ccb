---
name: teamlead-controller
description: Team Lead 统一控制器 - 所有操作的单一入口
triggers:
  - bootstrap
  - dispatch
  - dispatch-qa
  - archive
  - status
  - recover
  - add-lock
  - requeue
  - qa-pass
  - reply-worker
---

# Team Lead 控制器技能（最新）

## 目的

强制 Team Lead 所有操作走 `teamlead-control.ps1` 单一入口，避免手工派遣、子脚本绕过和状态漂移。

## 新会话必做

1. 先执行 bootstrap（每个新会话一次）
2. 再执行 status 确认当前锁、路由与运行态
3. 默认由 `route-monitor` + `route-notifier` 负责回传收口与唤醒，无需再创建 `notify-sentinel`
4. Rich 看板只作为二级观察层：先 `status`，只有在多任务并行、阻塞根因不清、通知异常或 runtime 需要对照时才看 Rich

## 控制器动作表

| 意图 | Action | 命令 |
|------|--------|------|
| 新会话初始化 | bootstrap | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action bootstrap` |
| 查看状态 | status | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action status` |
| 派遣开发任务 | dispatch | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action dispatch -TaskId <ID>` |
| 派遣 QA 任务 | dispatch-qa | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action dispatch-qa -TaskId <ID>` |
| QA 通过后保持待复审 | qa-pass | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action qa-pass -TaskId <ID>` |
| 复审驳回回退（不自动派遣） | requeue | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action requeue -TaskId <ID> -TargetState <assigned|waiting_qa> -RequeueReason "..."` |
| 补建任务锁 | add-lock | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action add-lock -TaskId <ID>` |
| 恢复流程 | recover | `... -Action recover -RecoverAction <action>` |
| 归档并提交/推送 | archive | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action archive -TaskId <ID>` |
| 回覆 worker（仅提醒/暂停） | reply-worker | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action reply-worker -WorkerName <name> -TaskId <ID> -ReplyText "..."` |

recover 可用动作：
- `reap-stale`
- `restart-worker -WorkerName <name>`
- `reset-task -TaskId <ID> -TargetState <assigned|waiting_qa>`
- `normalize-locks`
- `prune-orphan-locks`
- `baseline-clean`
- `full-clean`

## Route Notifications

- 默认由 `route-monitor.ps1` 写入事件，再由 `route-notifier.ps1` 唤醒 Team Lead。
- 如需关闭直接唤醒，设置 `CCB_ROUTE_MONITOR_NOTIFY=0`。
- 不再依赖 Agent Teams / `notify-sentinel`。

## 关键规则

- **不得**直接调用子脚本：`start-worker.ps1` / `dispatch-task.ps1` / `route-monitor.ps1` / `worker-registry.ps1`
- **不得**手工拼 `wezterm cli send-text` 派遣任务文本
- **不得**在新会话跳过 bootstrap
- **不得**使用 `Task(...)` / `Backgrounded agent` 进行派遣
- **不得**把 pane 轮询当主观察方式：主链默认看 `status` / Rich / route 提醒。只有人工调试时才短时使用 `get-text`，且同一任务连续 3 轮 `status` 无新 route/runtime 变化必须停止并转 `recover`
- **不得**直接用 `assign_task.py` 做写入动作（仅允许只读诊断参数）

## 决策优先级

- 当前主链默认无审批弹窗；不要把审批兼容动作当作常规入口。
- 已知链路内决策必须直接执行：`qa-pass` / `requeue` / `recover` / `dispatch` / `dispatch-qa` / `archive`。
- 收到 `blocked` / `fail` 后先 `status`，再按阻塞类型决策；不要直接反问用户。
- 只有未知阻塞、未知依赖、未知风险才升级给用户。

## 复审流转

- QA 通过后默认 `qa-pass` 等人工复审。
- 复审不通过：`requeue` 回退，不把驳回原因直接塞回旧 QA 运行上下文。
- 重新派遣：`requeue` 后再 `dispatch` 或 `dispatch-qa`。

## 结构化输出模板

每次控制器动作后，按以下模板汇报：

```
Action: <action performed>
Result: <success/fail>
Details: <brief summary>
Next: <suggested next action>
```
