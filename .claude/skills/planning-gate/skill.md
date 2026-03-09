---
name: planning-gate
description: Team Lead 前置规划增强器（需求澄清 + 方案对比 + 开发计划落地）
triggers:
  - discuss
  - plan
  - design
  - brainstorm
---

# Planning Gate（Moxton 兼容版）

## 目的

在进入执行链路前，先把需求从“模糊描述”收敛为“可稳定执行的任务文档”，避免 codex/gemini 因描述宽泛导致产出不稳定。

## Hard Gate（强制）

1. 未完成本技能流程前，禁止 `dispatch` / `dispatch-qa` / `archive`。
2. 禁止把规划产物写到 `docs/plans/*` 作为最终执行输入。
3. 最终可执行产物必须落到：`01-tasks/active/<domain>/<TASK-ID>.md`。
4. 规划阶段禁止扫描三业务仓代码目录：`E:\nuxt-moxton`、`E:\moxton-lotadmin`、`E:\moxton-lotapi`（除非用户明确要求“代码级排查”）。
5. 规划阶段只允许读取 `E:\moxton-ccb` 文档中心（`01/02/03/04/05-*`）。

## 输入与最终产出

输入：
- 用户需求文本
- 本地文档上下文（`E:\moxton-ccb` 内文档）

最终产出：
- 一个或多个标准任务文档（`01-tasks/active/*`）
- 每个任务都包含：范围、依赖、验收标准、风险、API 文档引用

## 执行流程

### 步骤 1：强交互澄清启动（必须）

先向用户提 1 个关键问题，不得直接进入代码探索。

提问格式必须包含：
- `当前理解`（1-2 句）
- `缺失信息`（1 条最关键）
- `请选择`（2-3 个互斥选项，给出推荐项）

### 步骤 2：文档扫描（仅 CCB 文档）

只允许读取以下文档，不读三业务仓代码：
- `02-api/*`（相关接口）
- `04-projects/COORDINATION.md`
- `04-projects/DEPENDENCIES.md`
- `01-tasks/STATUS.md`
- 必要时补充：`03-guides/*`、`05-verification/*`

### 步骤 3：澄清循环（一次只问一个问题）

围绕 5 个维度逐步提问，直到可执行：
1. 问题与业务目标
2. 功能范围与边界（包含/不包含）
3. 验收标准（可测试）
4. 依赖与约束（API、权限、时序）
5. 优先级与交付顺序

规则：
- 每次只问 1 个关键问题。
- 优先用选项题，必要时开放题。
- 若用户要求快速推进，可在文档中显式写“假设项”。
- 每轮回复后都要输出：
  - `已确认`
  - `仍缺失`
  - `下一问`

### 步骤 4：给出 2-3 个方案并推荐

必须包含：
- 方案摘要
- 技术取舍（复杂度、风险、验证成本）
- 推荐方案与原因

### 步骤 5：设计确认

先给用户一个“计划摘要”，确认后再落地任务文档。

摘要最少包含：
- 任务拆分（按角色）
- 串并行关系
- QA 介入点
- doc-updater 触发点

### 步骤 6：落地到任务模板

按角色选择模板并写入任务：
- `01-tasks/templates/tech-spec-backend.md`
- `01-tasks/templates/tech-spec-shop-frontend.md`
- `01-tasks/templates/tech-spec-admin-frontend.md`

任务命名规范：
- `BACKEND-xxx-*`
- `SHOP-FE-xxx-*`
- `ADMIN-FE-xxx-*`

任务目录：
- `01-tasks/active/backend/`
- `01-tasks/active/shop-frontend/`
- `01-tasks/active/admin-frontend/`

任务文件落地流程（Team Lead）：
1. 基于对应模板创建任务文件到 `01-tasks/active/<domain>/<TASK-ID>-<slug>.md`。
2. 向用户确认任务拆分与命名后，再进行就地编辑完善内容。
3. 禁止使用 `assign_task.py` 写入任务（`--intake/--split-request/--lock-task`）；`assign_task.py` 仅用于只读诊断。
4. 命名或内容不符合预期时，直接就地修正文件；禁止在 `01-tasks/active/*` 批量 `rm/del` 清理。

### 步骤 7：任务质量门槛（写文档时强制）

每个任务文档必须具备：
1. 明确 `前置依赖`（没有则写“无”）
2. 明确 API 文档引用（`02-api/*.md` 路径）
3. 可验证的验收标准（checkbox）
4. 失败/风险处理与回退说明
5. 影响范围（是否影响另外两个仓）

### 步骤 8：交接执行链路

规划完成后只做两件事：
1. 告知用户“计划已落地到 `01-tasks/active/*`，可进入执行”。
2. 下一步由 Team Lead 走 `teamlead-control.ps1` 主链路（`status -> dispatch`）。

## 反模式（禁止）

- 禁止一加载技能就执行 Explore/Search 到业务仓代码路径。
- 禁止在用户尚未确认范围前直接写任务文档。
- 禁止把“需要用户决策的问题”留空后默认推进执行。
- 禁止以“先跑起来再说”的方式进入派遣阶段。
- 禁止在规划阶段使用 `Write/Edit + rm/del` 循环修文件名。
- 禁止对 `01-tasks/active/*` 执行批量删除（尤其是 `rm *.md` / `del *.md`）。

## 与 superpowers 的关系

本技能借鉴了 `brainstorming + writing-plans` 的澄清深度与方案对比方式，但做了 Moxton 约束适配：
- 保留：逐步澄清、方案对比、先确认再执行
- 改造：最终产物路径与执行入口（只认 `01-tasks/active/*` + `teamlead-control`）
- 禁用：`docs/plans/*` 作为最终输入、子代理驱动执行
