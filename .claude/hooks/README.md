# Hooks 说明

本目录包含 Claude Code 的 hooks，用于在 Team Lead 模式下自动化工作流程。

## 可用 Hooks

### on-session-start.py

**触发时机**: Claude Code 会话启动时（SessionStart 事件）

**功能**:
- 显示 Team Lead 欢迎横幅
- 调用 `assign_task.py --show-task-locks` 展示当前活跃任务
- 读取 `.claude/agents/team-lead.md` 角色定义并注入到会话上下文
- 读取 `.claude/STARTUP-CHECKLIST.md` 启动提醒并注入

**输出示例**:
```
==================================================
🎯 Team Lead Mode Activated
==================================================

📊 当前任务状态:
   ...

✅ Team Lead 角色定义已注入

💡 下一步: python scripts/assign_task.py --standard-entry
==================================================
```

## 配置

Hooks 在 `.claude/settings.json` 中配置：

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "python .claude/hooks/on-session-start.py",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

## 工作流程集成

```
用户启动 Claude Code
    ↓
on-session-start.py
    ↓ (注入 Team Lead 身份 + 任务状态)
Claude Code 实例获得 Team Lead 角色上下文
    ↓
用户输入需求
    ↓
Team Lead 分析并拆分任务
    ↓
.\scripts\dispatch-task.ps1 分派给 Worker
    ↓
Worker 完成后返回 [ROUTE] 回执
    ↓
route-monitor.ps1 更新任务锁
    ↓
QA 验证 → 标记完成
```

## 调试

如果 hooks 未按预期工作：

1. 手动测试 hook：
```bash
echo '{}' | python .claude/hooks/on-session-start.py
```

2. 检查 `.claude/settings.json` 中的 hooks 配置是否正确

3. 确认 Python 可用且 `scripts/assign_task.py` 能正常运行

## 注意事项

- Hook 使用 Python 脚本（非 bash），无需 Git Bash 或 WSL
- Hook 通过 stdout 输出 JSON 注入上下文，通过 stderr 显示用户可见信息
- `hookSpecificOutput.additionalContext` 字段用于向 Claude 注入角色定义
