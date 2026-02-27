# Moxton 项目 Skills

本目录包含用于 Moxton 项目开发的 AI skills。

## 可用 Skills

| Skill | 路径 | 说明 |
|-------|------|------|
| 📝 **开发计划编写指南** | [development-plan-guide/](development-plan-guide/) | 指导 AI 如何为 Moxton 项目编写正确的开发计划 |

## 使用方式

### 开发计划编写指南

当你需要创建新任务时，这个 skill 会帮助你：

1. **确定任务归属** - 使用决策树判断任务属于哪个角色
2. **选择正确模板** - 根据角色选择对应的任务模板
3. **遵循命名规范** - 使用正确的文件命名格式
4. **拆分任务** - 了解如何组织跨角色任务

**触发条件：**
- 用户询问"如何编写开发计划？"
- 用户询问"这个任务应该给谁做？"
- 正在创建新的任务文档

## 示例场景

查看 [development-plan-guide/examples/](development-plan-guide/examples/) 目录获取完整的任务编写示例：

| 示例 | 文件 | 说明 |
|------|------|------|
| 商城支付功能 | [shop-frontend-example.md](development-plan-guide/examples/shop-frontend-example.md) | SHOP-FE 单角色任务 |
| 商品管理页面 | [admin-frontend-example.md](development-plan-guide/examples/admin-frontend-example.md) | ADMIN-FE 单角色任务 |
| 支付 API 开发 | [backend-example.md](development-plan-guide/examples/backend-example.md) | BACKEND 单角色任务 |
| 完整订单流程 | [cross-role-example.md](development-plan-guide/examples/cross-role-example.md) | 跨角色任务 |

## 相关文档

- [任务状态](../../01-tasks/STATUS.md) - 当前任务统计
- [角色定义](../agents/) - AI 角色提示词
- [项目状态](../../04-projects/) - 三端项目状态
