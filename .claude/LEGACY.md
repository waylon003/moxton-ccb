# Claude Code 项目配置已退役

2026-11-02 起默认入口为根 AGENTS.md 和 Codex 桌面工作流。本目录角色、技能、hooks 源文件保留作历史参考，不作为当前主指挥或子代理规则。

本项目 settings.json 中的 hooks 已清空，原文件保存在 settings.legacy.json；用户级 Claude 配置和其他目录均未改动。原配置亦可从 Git 基线 `4e24b15` 或本地迁移快照恢复。

不要因本目录旧文案启动 watcher、派遣 Worker、调用 report_route 或改任务锁。新角色位于 `.codex/agents`，通信和状态记录见 `03-guides/codex-desktop-workflow.md`。
