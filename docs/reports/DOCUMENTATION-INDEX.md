# 📚 Moxton-CCB 文档索引

快速导航到所有项目文档。

---

## 🚀 新手入门（从这里开始）

| 文档 | 说明 | 优先级 |
|------|------|--------|
| **[QUICK-START.md](./QUICK-START.md)** | 3 步快速启动指南 | ⭐⭐⭐ |
| **[PROJECT-COMPLETE-SUMMARY.md](./PROJECT-COMPLETE-SUMMARY.md)** | 项目完整配置总结 | ⭐⭐⭐ |
| [README.md](./README.md) | 项目概述 | ⭐⭐ |

---

## 📖 核心指导文档

| 文档 | 说明 | 用途 |
|------|------|------|
| **[CLAUDE.md](./CLAUDE.md)** | Team Lead 工作指南 | Claude Code 会话指导 |
| [.claude/agents/team-lead.md](./.claude/agents/team-lead.md) | Team Lead 角色定义 | 详细的角色职责 |
| [.claude/agents/protocol.md](./.claude/agents/protocol.md) | 跨 agent 通信协议 | ROUTE 信封格式 |

---

## 🛠️ CCB 相关文档

### 安装和配置

| 文档 | 说明 |
|------|------|
| [CCB-INSTALLATION-GUIDE.md](./CCB-INSTALLATION-GUIDE.md) | CCB 安装指南 |
| [CCB-MIGRATION-PLAN.md](./CCB-MIGRATION-PLAN.md) | 迁移方案（6 个阶段） |
| [CCB-MIGRATION-COMPLETE.md](./CCB-MIGRATION-COMPLETE.md) | 迁移完成报告 |

### 技术分析

| 文档 | 说明 |
|------|------|
| [CCB-ROLE-INJECTION-ANALYSIS.md](./CCB-ROLE-INJECTION-ANALYSIS.md) | 角色模板注入分析 |
| [CCB-REQUEST-FORMAT.md](./CCB-REQUEST-FORMAT.md) | Request 格式说明（已废弃） |

---

## 🎨 Hooks 和 Skills

### Hooks 系统

| 文档 | 说明 |
|------|------|
| [.claude/hooks/README.md](./.claude/hooks/README.md) | Hooks 完整文档 |
| [CCB-SETUP-REPORT.md](./CCB-SETUP-REPORT.md) | Hooks 配置报告 |

**Hooks 文件**：
- `.claude/hooks/on-session-start.sh` - 会话启动
- `.claude/hooks/on-user-prompt-submit.sh` - 用户输入检测
- `.claude/hooks/on-task-complete.sh` - 任务完成验证

### Skills

| 文档 | 说明 |
|------|------|
| [.claude/skills/development-plan-guide/skill.md](./.claude/skills/development-plan-guide/skill.md) | 开发计划编写指南 |
| [.claude/skills/README.md](./.claude/skills/README.md) | Skills 概述 |
| [SKILL-OPTIMIZATION-REPORT.md](./SKILL-OPTIMIZATION-REPORT.md) | Skill 优化报告 |

**示例文档**：
- `.claude/skills/development-plan-guide/examples/shop-frontend-example.md`
- `.claude/skills/development-plan-guide/examples/admin-frontend-example.md`
- `.claude/skills/development-plan-guide/examples/backend-example.md`
- `.claude/skills/development-plan-guide/examples/cross-role-example.md`

---

## 🔧 配置文件

### CCB 配置

| 文件 | 说明 |
|------|------|
| `.ccb/ccb.config` | CCB workers 配置 |
| `.ccb/shop-fe-dev.sh` | 商城前端启动脚本 |
| `.ccb/admin-fe-dev.sh` | 管理后台启动脚本 |
| `.ccb/backend-dev.sh` | 后端启动脚本 |
| `.ccb/qa.sh` | QA 启动脚本 |

### Claude Code 配置

| 文件 | 说明 |
|------|------|
| `.claude/settings.json` | Claude Code 设置（包含 hooks） |
| `config/ccb-routing.json` | CCB 路由配置 |

---

## 📋 任务管理

### 任务目录

| 目录 | 说明 |
|------|------|
| `01-tasks/active/` | 活动任务 |
| `01-tasks/completed/` | 已完成任务 |
| `01-tasks/templates/` | 任务模板 |

### 任务模板

| 文件 | 说明 |
|------|------|
| `01-tasks/templates/tech-spec-shop-frontend.md` | 商城前端任务模板 |
| `01-tasks/templates/tech-spec-admin-frontend.md` | 管理后台任务模板 |
| `01-tasks/templates/tech-spec-backend.md` | 后端任务模板 |

### 任务状态

| 文件 | 说明 |
|------|------|
| `01-tasks/TASK-LOCKS.json` | 任务锁状态 |
| `01-tasks/ACTIVE-RUNNER.md` | 运行器状态 |
| `01-tasks/STATUS.md` | 任务统计 |

---

## 🤖 角色定义

### 开发角色

| 文件 | 说明 |
|------|------|
| `.claude/agents/shop-frontend.md` | 商城前端开发者 |
| `.claude/agents/admin-frontend.md` | 管理后台开发者 |
| `.claude/agents/backend.md` | 后端开发者 |

### QA 角色

| 文件 | 说明 |
|------|------|
| `.claude/agents/shop-fe-qa.md` | 商城前端 QA |
| `.claude/agents/admin-fe-qa.md` | 管理后台 QA |
| `.claude/agents/backend-qa.md` | 后端 QA |

### 其他角色

| 文件 | 说明 |
|------|------|
| `.claude/agents/team-lead.md` | Team Lead |
| `.claude/agents/doc-updater.md` | 文档更新者 |

---

## 🔨 脚本文件

### Python 脚本

| 文件 | 说明 |
|------|------|
| `scripts/assign_task.py` | 任务管理主脚本 |

### Shell 脚本

| 文件 | 说明 |
|------|------|
| `scripts/ccb_start.ps1` | CCB 启动脚本（PowerShell） |
| `scripts/ccb_quick_start.sh` | CCB 快速启动脚本 |
| `scripts/ccb_wrapper.sh` | CCB 包装脚本 |

---

## 🧪 测试文件

| 文件 | 说明 |
|------|------|
| `tests/test_ccb_commands.py` | CCB 命令单元测试 |

---

## 📊 分析报告

| 文档 | 说明 |
|------|------|
| [CCB-COMPLETE-SETUP-SUMMARY.md](./CCB-COMPLETE-SETUP-SUMMARY.md) | 完整配置总结（旧版） |
| [PROJECT-COMPLETE-SUMMARY.md](./PROJECT-COMPLETE-SUMMARY.md) | 项目完成总结（最新） |

---

## 🗂️ 其他资源

### 项目状态

| 目录 | 说明 |
|------|------|
| `04-projects/` | 三端项目状态文档 |
| `05-verification/ccb-runs/` | CCB 执行日志 |

### API 文档

| 目录 | 说明 |
|------|------|
| `02-api/` | 后端 API 文档 |

### 开发指南

| 目录 | 说明 |
|------|------|
| `03-guides/` | 技术指南和最佳实践 |

---

## 🎯 按场景查找文档

### 场景 1: 我是新手，第一次使用
1. 阅读 [QUICK-START.md](./QUICK-START.md)
2. 阅读 [PROJECT-COMPLETE-SUMMARY.md](./PROJECT-COMPLETE-SUMMARY.md)
3. 运行 `python scripts/assign_task.py --doctor`

### 场景 2: 我想了解 Team Lead 的职责
1. 阅读 [CLAUDE.md](./CLAUDE.md)
2. 阅读 [.claude/agents/team-lead.md](./.claude/agents/team-lead.md)
3. 阅读 [.claude/agents/protocol.md](./.claude/agents/protocol.md)

### 场景 3: 我想创建开发计划
1. 调用 `/development-plan-guide` skill
2. 参考 [.claude/skills/development-plan-guide/skill.md](./.claude/skills/development-plan-guide/skill.md)
3. 查看示例：`.claude/skills/development-plan-guide/examples/`

### 场景 4: 我想了解 CCB 如何工作
1. 阅读 [CCB-MIGRATION-COMPLETE.md](./CCB-MIGRATION-COMPLETE.md)
2. 阅读 [CCB-ROLE-INJECTION-ANALYSIS.md](./CCB-ROLE-INJECTION-ANALYSIS.md)
3. 查看配置：`.ccb/ccb.config`

### 场景 5: 我遇到了问题
1. 运行 `python scripts/assign_task.py --doctor`
2. 查看 [QUICK-START.md](./QUICK-START.md) 的故障排查章节
3. 查看 [CCB-INSTALLATION-GUIDE.md](./CCB-INSTALLATION-GUIDE.md)

### 场景 6: 我想了解 Hooks 系统
1. 阅读 [.claude/hooks/README.md](./.claude/hooks/README.md)
2. 阅读 [CCB-SETUP-REPORT.md](./CCB-SETUP-REPORT.md)
3. 查看 hooks 文件：`.claude/hooks/*.sh`

---

## 📝 文档更新日志

| 日期 | 更新内容 |
|------|---------|
| 2026-02-26 | 完成所有文档创建和更新 |
| 2026-02-26 | CCB 迁移完成 |
| 2026-02-26 | Hooks 系统配置完成 |
| 2026-02-26 | Skills 优化完成 |

---

## 🔗 外部资源

- [CCB GitHub](https://github.com/bfly123/claude_code_bridge)
- [CCB 中文文档](https://github.com/bfly123/claude_code_bridge/blob/main/README_zh.md)
- [WezTerm 官网](https://wezfurlong.org/wezterm/)

---

**最后更新**：2026-02-26
**文档总数**：30+ 个文件
**项目状态**：✅ 生产就绪
