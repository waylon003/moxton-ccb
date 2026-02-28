---
name: teamlead-controller
description: Team Lead unified controller - single entry point for all operations
triggers:
  - bootstrap
  - dispatch
  - status
  - recover
  - add-lock
---

# Team Lead Controller Skill

## Purpose

Enforce single-entry-point discipline for all Team Lead operations.
Prevent common errors: bash-powershell escaping, direct sub-script calls, manual wezterm commands.

## Operation Mapping

| Intent | Action | Command |
|--------|--------|---------|
| New session init | bootstrap | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action bootstrap` |
| Dispatch dev task | dispatch | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action dispatch -TaskId <ID>` |
| Dispatch QA task | dispatch-qa | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action dispatch-qa -TaskId <ID>` |
| Check status | status | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action status` |
| Clean stale workers | recover | `... -Action recover -RecoverAction reap-stale` |
| Restart worker | recover | `... -Action recover -RecoverAction restart-worker -WorkerName <name>` |
| Reset task state | recover | `... -Action recover -RecoverAction reset-task -TaskId <ID> -TargetState assigned` |
| Add task lock | add-lock | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action add-lock -TaskId <ID>` |

## Intent Recognition

When user says something, map to the correct branch:

| Pattern | Branch |
|---------|--------|
| "execute", "continue", "dispatch", "run tasks" | Execution: status -> dispatch |
| "QA", "verify", "test", "validate" | Execution: dispatch-qa |
| "discuss", "plan", "design", "brainstorm" | Planning: read docs -> brainstorming -> writing-plans |
| "status", "progress", "what's happening" | Status: status |
| "stuck", "broken", "restart", "reset" | Recovery: recover |

## Prohibited Actions

1. **NEVER** call sub-scripts directly:
   - `start-worker.ps1` - use controller `bootstrap` or `recover -RecoverAction restart-worker`
   - `dispatch-task.ps1` - use controller `dispatch`
   - `route-monitor.ps1` - managed by controller `bootstrap`
   - `worker-registry.ps1` - use controller `status` or `recover`

2. **NEVER** use `powershell -Command` with complex logic (variables, Chinese, nested quotes)

3. **NEVER** manually compose `wezterm cli send-text` commands for task dispatch

4. **NEVER** skip bootstrap in a new session

## Structured Output Template

After each controller action, report to user:

```
Action: <action performed>
Result: <success/fail>
Details: <brief summary>
Next: <suggested next action>
```
