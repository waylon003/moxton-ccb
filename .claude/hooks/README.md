# Hooks 说明

本目录包含 Claude Code 的 hooks，用于在 Team Lead 模式下注入启动提醒，并对旧链路绕过行为做硬拦截。

## 当前保留的 Hooks

### on-session-start.py

**触发时机**: Claude Code 会话启动时（SessionStart 事件）

**功能**:
- 显示 Team Lead 欢迎横幅
- 调用 `assign_task.py --show-task-locks` 展示当前活跃任务
- 读取 `.claude/agents/team-lead.md` 角色定义并注入到会话上下文
- 读取 `.claude/STARTUP-CHECKLIST.md` 启动提醒并注入

### on-user-prompt-submit.py

**触发时机**: 每次用户提交消息时（UserPromptSubmit 事件）

**功能**:
- 在 bootstrap 未完成时，强提示必须先执行 `teamlead-control.ps1 -Action bootstrap`
- 在 bootstrap 完成后，持续注入当前主链动作集合：`status / dispatch / dispatch-qa / qa-pass / requeue / recover / add-lock / archive`
- 明确提醒：符合既有链路的决策不得反问用户

### pre-tool-guard.py

**触发时机**: Bash / Write / Edit / MultiEdit 工具执行前（PreToolUse 事件）

**功能**:
- 拦截绕过控制器的直接派遣：`dispatch-task.ps1` / `start-worker.ps1`
- 拦截 Team Lead 直接 `wezterm cli send-text`
- 拦截 Team Lead 直接改 `TASK-LOCKS.json`
- 拦截 Team Lead 直接写业务仓代码或在业务仓执行写入类命令
- 拦截 Team Lead 直接用 `assign_task.py` 做写入类动作

## 配置位置

Hooks 在 `.claude/settings.json` 中配置。

## 新链路下的职责边界

```text
SessionStart -> 注入 Team Lead 上下文 + 启动提醒
UserPromptSubmit -> 持续提醒统一入口与决策规则
PreToolUse -> 阻止旧链路绕过与危险写入
真正的调度/回传/通知 -> teamlead-control.ps1 + route-monitor + route-notifier
```

## 调试

如果 hooks 未按预期工作：

1. 手动测试 SessionStart hook：
```bash
echo '{}' | python .claude/hooks/on-session-start.py
```

2. 手动测试 UserPromptSubmit hook：
```bash
echo '{}' | python .claude/hooks/on-user-prompt-submit.py
```

3. 检查 `.claude/settings.json` 中的 hooks 配置是否正确

## 注意事项

- Hook 使用 Python 脚本（非 bash），无需 Git Bash 或 WSL
- Hook 通过 stdout 输出 JSON 注入上下文，通过 stderr 显示用户可见信息
- `hookSpecificOutput.additionalContext` 字段用于向 Claude 注入角色定义
- 当前主链默认无审批弹窗，因此 hook 不再把审批作为常规路径进行强化
