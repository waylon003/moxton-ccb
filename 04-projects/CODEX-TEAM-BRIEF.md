# Codex 桌面协作简报

主会话工作目录：`E:\moxton-ccb`。先读根 `AGENTS.md`、[当前轮次](./CURRENT-ROUND.md)、[任务总览](../01-tasks/STATUS.md) 和目标任务。

| 仓库 | 标识 | 开发 / QA |
|------|------|-----------|
| E:\moxton-lotapi | BACKEND | backend-dev / backend-qa |
| E:\moxton-lotadmin | ADMIN-FE | admin-fe-dev / admin-fe-qa |
| E:\nuxt-moxton | SHOP-FE | shop-fe-dev / shop-fe-qa |

原生子代理直接向父会话回报，项目角色声明在 `.codex/config.toml`。主会话唯一更新任务状态；每仓默认一个开发写入者，QA 使用新上下文。

详细步骤和结果合同见 [工作流](../03-guides/codex-desktop-workflow.md)。不启动旧 bootstrap、route、WezTerm watcher，也不使用旧任务锁推进新任务。该简报由主会话维护，不再调用旧 assign_task.py 生成。

任务中断后从文件、实际差异和证据恢复，不依赖旧子代理 ID。角色热加载、模型权限及工具可用性以当前会话实际能力为准；本项目不改用户级配置或其他项目。
