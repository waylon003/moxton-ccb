# Moxton 项目 Skills

本目录包含用于 Moxton 项目开发的 AI skills。

## 可用 Skills

| Skill | 路径 | 说明 |
|-------|------|------|
| 🧭 **planning-gate** | [planning-gate/](planning-gate/) | Team Lead 前置规划增强器：需求澄清、方案对比、任务文档落地 |
| 🎛️ **teamlead-controller** | [teamlead-controller/](teamlead-controller/) | Team Lead 统一控制器技能：所有执行操作走单入口命令 |
| 📝 **development-plan-guide** | [development-plan-guide/](development-plan-guide/) | 开发计划模板与任务命名/拆分规范参考 |

## 使用方式

### 推荐使用顺序（Team Lead）

1. 需求讨论/规划：先用 `planning-gate`
2. 任务执行/派遣：再用 `teamlead-controller`
3. 写任务文档细节：参考 `development-plan-guide`

### planning-gate

当你需要从模糊需求进入可执行计划时，这个 skill 会帮助你：

1. **逐步澄清需求** - 一次一问，收敛范围/边界/验收
2. **输出方案对比** - 至少 2 个方案并给出推荐
3. **落地任务文档** - 产物写入 `01-tasks/active/*`
4. **约束执行入口** - 规划完成后回到 `teamlead-control` 主链路
5. **强约束信息源** - 规划阶段只读 `E:\moxton-ccb` 文档，默认不扫三业务仓代码

### teamlead-controller

当你需要执行 Team Lead 操作时，这个 skill 会帮助你：

1. **统一单入口** - 使用 `teamlead-control.ps1` 执行 bootstrap/dispatch/dispatch-qa/archive/status/recover
2. **避免错误链路** - 禁止手工 `send-text` 派遣、禁止子代理派遣
3. **保障流程闭环** - 通过 route-monitor / approval-router 处理回调与审批

### development-plan-guide

当你需要创建新任务文档时，这个 skill 会帮助你：

1. **确定任务归属** - 使用决策树判断任务属于哪个角色
2. **选择正确模板** - 根据角色选择对应的任务模板
3. **遵循命名规范** - 使用正确的文件命名格式
4. **拆分任务** - 了解如何组织跨角色任务

**触发条件：**
- `planning-gate`：用户说“讨论需求/规划功能/brainstorm”
- `teamlead-controller`：用户说“dispatch/派遣/归档/status/recover”
- `development-plan-guide`：用户说“如何写任务文档/模板怎么用”

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
