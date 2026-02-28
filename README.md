# Moxton-CCB 指挥中心

多 AI 协作的任务编排系统，协调三个业务仓库的开发工作。

## 架构

- **Team Lead**：Claude Code 会话（本仓库）— 需求拆分、任务分派、进度监控
- **Workers**：Codex / Gemini CLI — 在 WezTerm 多窗口中执行开发和 QA
- **通信**：WezTerm CLI `send-text` + `[ROUTE]` 回调机制

## 业务仓库

| 前缀 | 仓库 | Worker 引擎 |
|------|------|------------|
| BACKEND | `E:\moxton-lotapi` | Codex |
| ADMIN-FE | `E:\moxton-lotadmin` | Codex |
| SHOP-FE | `E:\nuxt-moxton` | Gemini |

## 使用方式

所有操作通过统一控制器 `scripts/teamlead-control.ps1`：

```bash
# 新会话第一步
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action bootstrap

# 派遣任务
... -Action dispatch -TaskId BACKEND-010

# 查看状态
... -Action status
```

详细工作流程见 [CLAUDE.md](./CLAUDE.md)。

## 目录结构

```
01-tasks/          任务文档与锁
02-api/            API 参考文档
03-guides/         技术指南
04-projects/       项目文档与协调关系
05-verification/   QA 验证报告
config/            配置（worker-map、dispatch 模板）
scripts/           控制器与工具脚本
```
