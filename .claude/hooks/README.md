# CCB Hooks 说明

本目录包含 Claude Code 的 hooks，用于在 CCB Team Lead 模式下自动化工作流程。

## 可用 Hooks

### 1. on-session-start.sh
**触发时机**: Claude Code 会话启动时

**功能**:
- 显示 Team Lead 角色说明
- 列出职责边界和禁止操作
- 提供快速命令参考
- 自动注入 `.claude/agents/team-lead.md` 角色定义到上下文

**输出示例**:
```
🎯 CCB Team Lead Mode Activated
📋 Role: Team Lead (Coordination & Orchestration)
✅ Responsibilities: ...
❌ Prohibited: ...
```

### 2. on-user-prompt-submit.sh
**触发时机**: 用户提交每个提示词时

**功能**:
- 检测用户意图（开发计划、任务分派、状态查询等）
- 提供相应的命令建议
- 警告违反 Team Lead 边界的操作（如直接编辑业务代码）

**检测模式**:
| 用户输入关键词 | 建议操作 |
|--------------|---------|
| "编写开发计划"、"创建任务" | 使用 `/development-plan-guide` skill |
| "分派"、"执行"、"dispatch" | `python scripts/assign_task.py --dispatch-ccb` |
| "状态"、"进度"、"poll" | `python scripts/assign_task.py --poll-ccb` |
| "修改 nuxt-moxton/lotadmin/lotapi" | ⚠️ 警告：应创建任务并分派给 worker |
| "任务列表"、"list task" | `python scripts/assign_task.py --list` |

### 3. on-task-complete.sh
**触发时机**: 任务标记为完成前

**功能**:
- 验证任务锁状态（必须是 `qa` 或 `completed`）
- 检查 QA 证据是否存在于 `05-verification/ccb-runs/`
- 阻止未经 QA 验证的任务完成

**验证规则**:
- ❌ 任务状态不是 `qa` 或 `completed` → 拒绝
- ❌ 没有 QA 证据文件 → 警告
- ✅ 通过验证 → 允许完成

## 配置

Hooks 在 `.claude/settings.json` 中配置：

```json
{
  "hooks": {
    "on-session-start": "bash .claude/hooks/on-session-start.sh",
    "on-user-prompt-submit": "bash .claude/hooks/on-user-prompt-submit.sh \"$PROMPT\""
  }
}
```

## 工作流程集成

```
用户启动 Claude Code
    ↓
on-session-start.sh
    ↓ (注入 Team Lead 身份)
Claude Code 实例获得 Team Lead 角色上下文
    ↓
用户输入: "编写订单管理的开发计划"
    ↓
on-user-prompt-submit.sh
    ↓ (检测到开发计划请求)
提示: "使用 /development-plan-guide skill"
    ↓
Claude 调用 development-plan-guide skill
    ↓ (使用正确的模板和角色分配)
生成任务文档到 01-tasks/active/
    ↓
用户确认后分派任务
    ↓
python scripts/assign_task.py --dispatch-ccb TASK-ID
    ↓
CCB 启动 Codex worker 执行
    ↓
Worker 完成后返回结果
    ↓
QA 验证
    ↓
on-task-complete.sh
    ↓ (验证 QA 证据)
标记任务完成
```

## 调试

如果 hooks 未按预期工作：

1. 检查 hooks 文件权限：
```bash
chmod +x .claude/hooks/*.sh
```

2. 手动测试 hook：
```bash
bash .claude/hooks/on-session-start.sh
bash .claude/hooks/on-user-prompt-submit.sh "编写开发计划"
bash .claude/hooks/on-task-complete.sh "BACKEND-001"
```

3. 检查 `.claude/settings.json` 中的 hooks 配置是否正确

## 注意事项

- Hooks 使用 bash 脚本，需要 Git Bash 或 WSL 环境（Windows）
- `$PROMPT` 变量由 Claude Code 自动传递给 `on-user-prompt-submit.sh`
- Hooks 输出会显示在 Claude Code 界面中，帮助用户理解当前模式
