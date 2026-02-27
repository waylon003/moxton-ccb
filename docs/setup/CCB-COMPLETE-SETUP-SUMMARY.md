# CCB 模式完整配置总结

## ✅ 已完成的工作

### 1. Claude Code Hooks 系统（Team Lead）

**创建的文件**:
- `.claude/hooks/on-session-start.sh` - 会话启动时注入 Team Lead 身份
- `.claude/hooks/on-user-prompt-submit.sh` - 智能检测用户意图并提示
- `.claude/hooks/on-task-complete.sh` - 验证 QA 证据
- `.claude/hooks/README.md` - Hooks 完整文档

**配置**:
- `.claude/settings.json` - 添加了 hooks 配置

**功能**:
- ✅ 自动注入 Team Lead 角色定义
- ✅ 检测"编写开发计划"并提示使用 `/development-plan-guide`
- ✅ 警告违反 Team Lead 边界的操作
- ✅ 验证任务完成前的 QA 证据

### 2. Development Plan Guide Skill 优化

**优化的文件**:
- `.claude/skills/development-plan-guide/skill.md` - 重构并明确三个概念

**三个关键概念**:
1. **固定角色模板** (`.claude/agents/`) - Codex worker 的身份定义
2. **开发计划任务模板** (`01-tasks/templates/`) - 创建任务时使用的结构
3. **开发计划任务示例** (`.claude/skills/development-plan-guide/examples/`) - 完整的填写示例

**新增内容**:
- 5 步完整工作流程
- 快速参考和检查清单
- 3 个具体场景示例
- 集成 Python 脚本命令

### 3. CCB Request 角色模板注入

**修改的文件**:
- `scripts/assign_task.py` - `write_ccb_request()` 函数

**新增字段**:
```json
{
  "role_prompts": {
    "dev_prompt_path": ".claude/agents/backend.md",
    "dev_prompt_content": "完整的开发者角色模板内容",
    "qa_prompt_path": ".claude/agents/backend-qa.md",
    "qa_prompt_content": "完整的 QA 角色模板内容"
  }
}
```

**解决的问题**:
- ✅ Dev 和 QA 获得不同的角色定义，不会混淆
- ✅ 完整的上下文传递，不依赖手动读取
- ✅ 支持动态角色定义

### 4. 文档更新

**创建的文档**:
- `CLAUDE.md` - 改进的项目指导文档
- `CCB-SETUP-REPORT.md` - Hooks 配置报告
- `SKILL-OPTIMIZATION-REPORT.md` - Skill 优化报告
- `CCB-ROLE-INJECTION-ANALYSIS.md` - 角色注入分析报告
- `CCB-REQUEST-FORMAT.md` - Request 格式说明

## 🎯 完整的工作流程

### 启动阶段

```
1. 启动 Claude Code (E:\moxton-ccb)
    ↓
2. [on-session-start.sh 触发]
    ↓
3. 显示 Team Lead 角色说明
    ↓
4. 注入 team-lead.md 到上下文
    ↓
5. Team Lead 身份激活 ✅
```

### 计划阶段

```
用户: "编写订单管理的开发计划"
    ↓
[on-user-prompt-submit.sh 触发]
    ↓
检测到: 开发计划请求
提示: "💡 Use /development-plan-guide"
    ↓
Team Lead 调用: /development-plan-guide
    ↓
Skill 指导:
  1. 分析需求 → ADMIN-FE
  2. 选择模板 → tech-spec-admin-frontend.md
  3. 创建文档 → ADMIN-FE-001-order-management.md
  4. 参考示例 → admin-frontend-example.md
  5. 填写内容
    ↓
生成任务文档到: 01-tasks/active/admin-frontend/
```

### 执行阶段

```
Team Lead: python scripts/assign_task.py --dispatch-ccb ADMIN-FE-001
    ↓
write_ccb_request() 生成 request.json
    ↓
包含内容:
  - task_path: 任务文档路径
  - repo: E:\moxton-lotadmin
  - role_prompts.dev_prompt_content: 完整的开发者角色定义
  - role_prompts.qa_prompt_content: 完整的 QA 角色定义
    ↓
CCB 系统读取 request.json
    ↓
启动 Codex Dev Worker (E:\moxton-lotadmin)
    ↓
注入: role_prompts.dev_prompt_content
    ↓
Dev Worker 获得身份: "你是管理后台前端开发者..."
    ↓
开发完成
    ↓
启动 Codex QA Worker (E:\moxton-lotadmin)
    ↓
注入: role_prompts.qa_prompt_content
    ↓
QA Worker 获得身份: "你是管理后台 QA 工程师..."
    ↓
验收完成，写入 response.json
```

### 完成阶段

```
Team Lead: python scripts/assign_task.py --poll-ccb CCB-xxx
    ↓
读取 response.json
    ↓
[on-task-complete.sh 触发]
    ↓
验证:
  - 任务状态 = qa ✅
  - QA 证据存在 ✅
    ↓
向用户报告结果
    ↓
用户确认
    ↓
移动到 completed/
```

## 📊 诊断结果

```bash
python scripts/assign_task.py --doctor
```

**结果**: ✅ 所有检查通过
- Runner lock: claude
- Task locks: 无过期
- 角色模板: 全部存在
- 代码仓库: 全部可达
- AGENTS.md: 全部存在
- QA 脚本: 全部配置
- Codex 二进制: 已找到
- MCP 服务: playwright, vitest 已配置

## 🔧 常用命令

### Team Lead 命令

```bash
# 检查模式（Planning/Execution）
python scripts/assign_task.py --standard-entry

# 诊断配置
python scripts/assign_task.py --doctor

# 接收需求并生成任务
python scripts/assign_task.py --intake "需求描述"

# 拆分跨角色需求
python scripts/assign_task.py --split-request "需求描述"

# 列出活动任务
python scripts/assign_task.py --list

# 分派任务
python scripts/assign_task.py --dispatch-ccb BACKEND-001

# 轮询任务进度
python scripts/assign_task.py --poll-ccb CCB-xxx

# 查看任务锁
python scripts/assign_task.py --show-task-locks
```

### Codex Workers 启动

```bash
# 启动所有 workers
powershell -ExecutionPolicy Bypass -File scripts/ccb_start.ps1 -Terminal wt
```

## 📁 关键文件路径

### Team Lead (Claude Code)
- 工作目录: `E:\moxton-ccb`
- 角色定义: `.claude/agents/team-lead.md`
- Hooks: `.claude/hooks/*.sh`
- Skills: `.claude/skills/development-plan-guide/`

### Codex Workers
- SHOP-FE: `E:\nuxt-moxton`
  - 角色定义: `E:\moxton-ccb\.claude\agents\shop-frontend.md`
  - QA 角色: `E:\moxton-ccb\.claude\agents\shop-fe-qa.md`

- ADMIN-FE: `E:\moxton-lotadmin`
  - 角色定义: `E:\moxton-ccb\.claude\agents\admin-frontend.md`
  - QA 角色: `E:\moxton-ccb\.claude\agents\admin-fe-qa.md`

- BACKEND: `E:\moxton-lotapi`
  - 角色定义: `E:\moxton-ccb\.claude\agents\backend.md`
  - QA 角色: `E:\moxton-ccb\.claude\agents\backend-qa.md`

### CCB 通信
- Request: `05-verification/ccb-runs/{REQ_ID}.request.json`
- Response: `05-verification/ccb-runs/{REQ_ID}.response.json`

### 任务管理
- 活动任务: `01-tasks/active/{role}/`
- 已完成: `01-tasks/completed/{role}/`
- 任务模板: `01-tasks/templates/`
- 任务锁: `01-tasks/TASK-LOCKS.json`

## ⚠️ 下一步：安装 CCB 本体

当前 CCB 系统的配置已完成，但需要：

### 1. 了解 CCB 是什么
- CCB 的完整名称和用途
- CCB 的仓库地址或安装文档
- CCB 的架构和工作原理

### 2. 安装 CCB
- 安装步骤
- 配置要求
- 依赖项

### 3. 集成 CCB 与当前配置
- CCB 如何读取 `05-verification/ccb-runs/*.request.json`
- CCB 如何启动 Codex workers
- CCB 如何注入 `role_prompts.dev_prompt_content` 到 Codex 会话
- CCB 如何收集 response 并写入 `*.response.json`

### 4. 测试完整流程
- 创建测试任务
- 通过 CCB 分派给 Codex worker
- 验证角色模板是否正确注入
- 验证 QA 流程
- 验证任务完成流程

## 📚 参考文档

| 文档 | 说明 |
|------|------|
| `CLAUDE.md` | 项目指导文档 |
| `README.md` | 项目概述 |
| `.claude/hooks/README.md` | Hooks 系统说明 |
| `.claude/skills/development-plan-guide/skill.md` | 开发计划编写指南 |
| `CCB-REQUEST-FORMAT.md` | CCB Request 格式说明 |
| `CCB-ROLE-INJECTION-ANALYSIS.md` | 角色注入分析 |
| `.claude/agents/protocol.md` | 跨 agent 通信协议 |

## ✅ 总结

CCB 模式的配置已经完成：

1. ✅ Team Lead 有完整的 hooks 自动化
2. ✅ Development Plan Guide skill 已优化
3. ✅ CCB Request 包含完整的角色模板
4. ✅ 所有配置通过诊断检查
5. ⏳ 等待安装 CCB 本体进行集成测试

现在可以：
- 使用 Claude Code 作为 Team Lead
- 使用 `/development-plan-guide` 创建任务
- 生成包含角色模板的 CCB Request
- 等待 CCB 系统集成后进行完整测试
