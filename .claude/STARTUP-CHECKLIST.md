# Team Lead 启动检查清单

每次在 `E:\moxton-ccb` 启动新的 Claude Code 会话时，只执行这一套新链路，不要再走旧的 pane 派遣/审批链。

## 1. 会话前提

- 当前目录必须是 `E:\moxton-ccb`
- Team Lead 只能是 Claude Code
- 所有调度动作统一走 `scripts/teamlead-control.ps1`
- 不再依赖 Agent Teams / `notify-sentinel`
- 当前业务主链默认无审批弹窗，Codex worker 统一使用 `-a never --sandbox danger-full-access`

## 2. 新会话第一步

先执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action bootstrap
```

再执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action status
```

说明：
- `bootstrap` 负责初始化 Team Lead 运行态、检测/拉起 `route-monitor` 与 `route-notifier`
- `status` 用于查看当前任务锁、headless 运行态、最近 route 和建议动作

## 3. Team Lead 允许做什么

- 需求澄清、规划、拆任务
- 写 `01-tasks/active/*` 任务文档
- 通过控制器执行 `dispatch / dispatch-qa / qa-pass / requeue / recover / archive`
- 查看 `status` 并根据既有链路直接决策

## 4. Team Lead 禁止做什么

- 直接调用 `start-worker.ps1`、`dispatch-task.ps1`、`route-monitor.ps1`
- 手工拼 `wezterm cli send-text` 派遣 worker
- 直接编辑 `01-tasks/TASK-LOCKS.json`
- 直接修改三个业务仓库代码
- 把审批兼容动作当作主链入口

## 5. 常用控制器命令

```powershell
# 查看状态
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action status

# 派遣开发
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action dispatch -TaskId BACKEND-010

# 派遣 QA
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action dispatch-qa -TaskId BACKEND-010

# QA 通过，保持待人工复审
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action qa-pass -TaskId BACKEND-010

# 驳回回退但不自动重派
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action requeue -TaskId BACKEND-010 -TargetState waiting_qa -RequeueReason "review_reject"

# 恢复/清理
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action recover -RecoverAction restart-task -TaskId BACKEND-010

# 归档
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action archive -TaskId BACKEND-010
```

## 6. 收到 route 提醒后的标准动作

当主窗口收到 `[ROUTE] ... next=status/check_routes`：

1. 先执行 `status`
2. 再根据当前锁状态与 route 内容做决策
3. 决策属于既有链路时直接执行，不要反问用户

已知决策示例：
- dev 成功后进入 `waiting_qa`：执行 `dispatch-qa`
- QA 通过待复审：执行 `qa-pass`
- 人工复审驳回：执行 `requeue`
- 任务完成：执行 `archive`
- 运行态漂移/陈旧：执行 `recover`

## 7. 阻塞处理原则

收到 `blocked` / `fail` 后，第一步永远是：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action status
```

然后再分类处理：
- `runtime/orchestration`：先恢复运行态，不要直接回开发
- `env/service`：先修环境，不要直接重派原任务
- `qa_evidence`：回 QA 补证据，不要回开发
- `code/contract/ui`：才回开发修复

## 8. 当前通知机制

- worker / QA / `doc-updater` / `repo-committer` 都通过 `report_route` 回传
- `route-monitor` 负责收口、写锁、落提醒事件
- `route-notifier` 独立负责把提醒短文本发回 Team Lead
- 不再依赖 `notify-sentinel`

## 9. 一句话记忆

先 `bootstrap`，再 `status`，然后只通过 `teamlead-control.ps1` 做所有决策与派遣。
