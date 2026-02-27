# Development Plan Guide Skill 优化报告

## 优化概述

已完成 `development-plan-guide` skill 的重构，明确区分三个关键概念，并优化工作流程。

## 三个关键概念的明确定义

### 1. 固定角色模板 (`.claude/agents/`)
**定位**: Codex worker 的身份和行为规范

**包含文件**:
- `team-lead.md` - Team Lead 角色（CCB 编排者）
- `shop-frontend.md` / `admin-frontend.md` / `backend.md` - 开发者角色
- `shop-fe-qa.md` / `admin-fe-qa.md` / `backend-qa.md` - QA 角色
- `protocol.md` - 跨 agent 通信协议

**使用场景**:
- Codex worker 启动时自动加载
- 定义 worker 的职责边界和工作方式
- Team Lead 不需要手动引用

### 2. 开发计划任务模板 (`01-tasks/templates/`)
**定位**: 创建新任务时使用的标准化文档结构

**包含文件**:
- `tech-spec-shop-frontend.md` - 商城前端任务模板
- `tech-spec-admin-frontend.md` - 管理后台任务模板
- `tech-spec-backend.md` - 后端任务模板

**模板结构**:
```markdown
# Tech-Spec: [任务标题]
- 概述（问题陈述、解决方案、范围）
- 开发上下文（现有实现、依赖项）
- 技术方案（API 设计、数据模型、业务逻辑）
- 实施步骤
- 验收标准
- 风险和注意事项
```

**使用场景**:
- Team Lead 创建新任务时复制对应模板
- 填充具体的需求和技术细节

### 3. 开发计划任务示例 (`.claude/skills/development-plan-guide/examples/`)
**定位**: 展示如何正确填写任务模板的完整示例

**包含文件**:
- `shop-frontend-example.md` - 商城支付功能示例
- `admin-frontend-example.md` - 商品管理页面示例
- `backend-example.md` - 支付 API 示例
- `cross-role-example.md` - 跨角色任务示例

**使用场景**:
- Team Lead 不确定如何填写任务模板时参考
- 学习任务拆分和技术方案编写的最佳实践

## 优化后的 Skill 结构

### 新增章节

1. **三个关键概念** - 明确区分固定角色模板、任务模板、任务示例
2. **工作流程** - 5 步完整流程（理解需求 → 选择模板 → 创建文档 → 填写内容 → 处理跨角色）
3. **快速参考** - 任务创建检查清单和常用命令
4. **示例场景** - 3 个具体场景（单角色后端、单角色前端、跨角色）

### 优化内容

1. **更清晰的层次结构**:
   - 概述 → 三个关键概念 → 使用场景 → 工作流程 → 快速参考 → 示例场景 → 最佳实践 → 故障排查

2. **更实用的工作流程**:
   - 步骤 1: 理解需求并确定角色归属（决策树）
   - 步骤 2: 选择正确的任务模板
   - 步骤 3: 创建任务文档（命名规范）
   - 步骤 4: 填写任务内容（参考示例）
   - 步骤 5: 处理跨角色任务

3. **集成 Python 脚本**:
   ```bash
   # 接收需求并生成任务
   python scripts/assign_task.py --intake "需求描述"

   # 拆分跨角色需求
   python scripts/assign_task.py --split-request "需求描述"
   ```

4. **完整的命令参考**:
   - 查看活动任务
   - 添加任务锁
   - 分派任务
   - 查看任务锁状态

## 与 Hooks 的集成

### on-user-prompt-submit.sh 检测逻辑

当用户输入包含以下关键词时，hook 会提示使用 `/development-plan-guide`:
- "编写"、"创建"、"写"、"生成" + "开发计划"、"任务"、"plan"、"task"
- "拆分需求"、"split request"

### 工作流程示例

```
用户: "编写订单管理的开发计划"
    ↓
[on-user-prompt-submit.sh 触发]
    ↓
检测到: 开发计划请求
提示: "💡 Use /development-plan-guide skill"
    ↓
Team Lead 调用: /development-plan-guide
    ↓
Skill 指导:
  1. 分析需求 → 涉及后台管理界面 → ADMIN-FE
  2. 选择模板 → tech-spec-admin-frontend.md
  3. 创建文档 → ADMIN-FE-001-order-management.md
  4. 参考示例 → admin-frontend-example.md
  5. 填写内容 → 概述、技术方案、验收标准等
    ↓
生成任务文档到: 01-tasks/active/admin-frontend/
    ↓
添加任务锁: python scripts/assign_task.py --lock-task ADMIN-FE-001
    ↓
分派任务: python scripts/assign_task.py --dispatch-ccb ADMIN-FE-001
```

## 关键改进点

### 1. 概念清晰化
- ✅ 明确区分三种文档的用途和使用场景
- ✅ 避免混淆固定角色模板和任务模板

### 2. 流程标准化
- ✅ 5 步工作流程，每步都有明确的输入输出
- ✅ 集成 Python 脚本，自动化任务创建

### 3. 实用性增强
- ✅ 快速参考章节，包含检查清单和常用命令
- ✅ 3 个具体场景示例，覆盖单角色和跨角色

### 4. 可维护性提升
- ✅ 结构化的文档组织
- ✅ 清晰的故障排查指南

## 使用建议

### 对于 Team Lead

1. **首次使用**: 阅读"三个关键概念"章节，理解文档体系
2. **创建任务**: 按照"工作流程"章节的 5 步执行
3. **遇到问题**: 查看"故障排查"章节
4. **学习最佳实践**: 阅读 `examples/` 中的完整示例

### 对于系统维护者

1. **更新角色定义**: 修改 `.claude/agents/` 中的固定角色模板
2. **更新任务模板**: 修改 `01-tasks/templates/` 中的任务模板
3. **添加新示例**: 在 `.claude/skills/development-plan-guide/examples/` 添加新示例
4. **更新 Skill**: 修改 `skill.md` 反映最新的流程和规范

## 文件清单

优化的文件:
- `.claude/skills/development-plan-guide/skill.md` (重构)

相关文件:
- `.claude/agents/*.md` (固定角色模板)
- `01-tasks/templates/*.md` (任务模板)
- `.claude/skills/development-plan-guide/examples/*.md` (任务示例)
- `.claude/hooks/on-user-prompt-submit.sh` (自动检测)

## 下一步建议

1. **测试 Skill**: 使用 `/development-plan-guide` 创建一个测试任务
2. **验证 Hook**: 输入"编写开发计划"，确认 hook 提示正确
3. **完善示例**: 根据实际使用情况，添加更多示例到 `examples/`
4. **文档同步**: 确保 README.md 和其他文档引用正确的概念
