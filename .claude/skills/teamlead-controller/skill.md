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
  - approve-request
  - deny-request
  - show-approval
  - requeue
  - qa-pass
  - reply-worker
---

# Team Lead 控制器技能（最新）

## 目的

强制 Team Lead 所有操作走 `teamlead-control.ps1` 单一入口，避免手工派遣、子脚本绕过和状态漂移。

## 新会话必做

1. 先执行 bootstrap（每个新会话一次）
2. 再执行 status 确认当前锁、路由与审批
3. 在 Claude Code UI/手机端务必手动创建 notify-sentinel（见下文）

## 控制器动作表

| 意图 | Action | 命令 |
|------|--------|------|
| 新会话初始化 | bootstrap | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action bootstrap` |
| 查看状态 | status | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action status` |
| 派遣开发任务 | dispatch | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action dispatch -TaskId <ID>` |
| 派遣 QA 任务 | dispatch-qa | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action dispatch-qa -TaskId <ID>` |
| QA 通过后保持待复审 | qa-pass | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action qa-pass -TaskId <ID>` |
| 复审驳回回退（不自动派遣） | requeue | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action requeue -TaskId <ID> -TargetState <assigned|waiting_qa> -RequeueReason "..."` |
| 查看审批详情 | show-approval | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action show-approval -RequestId <ID>` |
| 批准审批 | approve-request | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action approve-request -RequestId <ID>` |
| 拒绝审批 | deny-request | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action deny-request -RequestId <ID>` |
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

## notify-sentinel（强制提醒）

- notify-sentinel 不会随 dispatch 自动启动；每个新会话必须手动创建并让其阅读 `E:\moxton-ccb\.claude\agents\notify-sentinel.md`
- Claude Code UI/手机端审批与回调提醒依赖 notify-sentinel（非 WezTerm 注入）
- WezTerm 注入默认启用；如需关闭，设置 `CCB_ENABLE_WEZTERM_NOTIFY=0`
- notify-sentinel 启动后必须输出一次 [WATCH-READY]；未出现则重建 teammate
- dispatch/dispatch-qa 前必须有 notify-sentinel ready 标记；若无，先执行 `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action notify-ready`

## 关键规则

- **不得**直接调用子脚本：`start-worker.ps1` / `dispatch-task.ps1` / `route-monitor.ps1` / `worker-registry.ps1`
- **不得**手工拼 `wezterm cli send-text` 派遣任务文本
- **不得**在新会话跳过 bootstrap
- **不得**使用 `Task(...)` / `Backgrounded agent` 进行派遣
- **不得**无限轮询：同一 pane `get-text` 连续 3 次无变化必须停止；同一 task `check_routes` 3 次无变化必须停止
- **不得**直接用 `assign_task.py` 做写入动作（仅允许只读诊断参数）

## 审批优先级

- 有 pending 审批时必须先 `show-approval` 并 `approve-request/deny-request`
- 高风险审批不得询问用户；由 Team Lead 直接 approve/deny，默认拒绝，除非任务文档明确允许
- 不允许先 `sleep/wait`
- 若确认是历史遗留可用 `recover -RecoverAction baseline-clean` 一键清理

## 复审流转

- QA 通过后默认 `qa-pass` 等人工复审
- 复审不通过：`requeue` 回退，不把驳回原因直接发到旧 worker 窗口
- 重新派遣：`requeue` 后再 `dispatch` 或 `dispatch-qa`

## 结构化输出模板

每次控制器动作后，按以下模板汇报：

```
Action: <action performed>
Result: <success/fail>
Details: <brief summary>
Next: <suggested next action>
```
