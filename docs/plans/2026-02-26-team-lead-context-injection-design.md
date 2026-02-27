# Team Lead 上下文注入设计文档

**日期**: 2026-02-26
**作者**: Claude (Team Lead)
**状态**: 已实施

## 背景

在 moxton-ccb 目录启动 Claude Code 时，需要自动将 Team Lead 角色定义注入到会话上下文中，确保 Claude 理解其作为 Team Lead 的职责边界和工作流程。

### 问题

原有的 `on-session-start.sh` hook 使用 `cat .claude/agents/team-lead.md` 输出角色定义，但这只是将内容显示在终端，并未真正注入到 Claude Code 的会话上下文中。

## 设计方案

### 选定方案：使用 Hook 的 `additionalContext` 输出

通过 Claude Code 的 SessionStart hook 支持的 JSON 格式输出，将 Team Lead 角色定义注入到会话上下文。

### 实现细节

**修改文件**: `E:\moxton-ccb\.claude\hooks\on-session-start.sh`

**关键变更**:
1. 读取 `.claude/agents/team-lead.md` 内容到变量
2. 使用 `jq` 将内容转换为 JSON 字符串（处理换行和特殊字符）
3. 输出符合 Claude Code hook 规范的 JSON 格式：
   ```json
   {
     "hookSpecificOutput": {
       "additionalContext": "<team-lead.md 内容>"
     }
   }
   ```

**技术要点**:
- 使用 `jq -Rs .` 将多行文本安全转换为 JSON 字符串
- 保留用户可见的欢迎消息（echo 输出）
- JSON 输出在最后，确保被 Claude Code 正确解析

## 架构

```
Claude Code 启动
    ↓
触发 SessionStart hook
    ↓
执行 on-session-start.sh
    ↓
├─ 显示欢迎消息（用户可见）
│   └─ 角色说明、职责、快速命令
│
└─ 输出 JSON（Claude Code 解析）
    └─ additionalContext: team-lead.md 内容
        ↓
    注入到 Claude 会话上下文
        ↓
    Claude 获得 Team Lead 身份和规则
```

## 验证方法

1. **重启 Claude Code 会话**
   ```bash
   cd E:\moxton-ccb
   # 重新启动 Claude Code
   ```

2. **检查 hook 输出**
   - 应该看到欢迎消息
   - 不应该看到 JSON 输出（被 Claude Code 内部处理）

3. **验证上下文注入**
   - 询问 Claude："你的角色是什么？"
   - 应该回答包含 Team Lead 职责和边界
   - 尝试让 Claude 直接修改业务仓库代码，应该被拒绝

4. **测试工作流**
   - 提出需求，观察 Claude 是否按 Team Lead 流程工作
   - 检查是否会建议使用 CCB 分派任务而非直接编码

## 依赖

- **jq**: JSON 处理工具（需要在系统中安装）
- **bash**: 脚本执行环境（Git Bash 或 WSL）
- **Claude Code**: 支持 `hookSpecificOutput.additionalContext` 的版本

## 回滚方案

如果方案 A 不工作，可以回退到方案 B：

1. 将 `.claude/agents/team-lead.md` 内容追加到 `CLAUDE.md`
2. 移除 hook 中的 JSON 输出部分
3. 保留欢迎消息显示

## 后续改进

1. **错误处理**: 添加 jq 不存在时的降级方案
2. **日志记录**: 记录 hook 执行状态到日志文件
3. **动态上下文**: 根据当前任务状态注入不同的上下文信息
4. **多角色支持**: 扩展到其他角色的上下文注入

## 参考

- Claude Code Hook 文档: `.claude/hooks/README.md`
- Team Lead 角色定义: `.claude/agents/team-lead.md`
- CCB 工作流: `CLAUDE.md`
