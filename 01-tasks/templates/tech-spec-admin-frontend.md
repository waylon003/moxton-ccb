# Tech-Spec: [任务标题]

**任务ID:** ADMIN-FE-XXX
**创建时间:** YYYY-MM-DD
**状态:** planned
**执行模式:** codex-desktop
**当前 attempt:** 0
**角色:** CRUD前端工程师
**项目:** moxton-lotadmin
**优先级:** [P0|P1|P2|P3]
**技术栈:** Vue 3 + TypeScript + SoybeanAdmin + Naive UI
**QA_LEVEL:** [full|smoke|skip]

**QA_LEVEL 规则:** `full` 必须独立 QA；`smoke` 由主会话按风险决定是否独立 QA；`skip` 只做开发自测和主会话复核。无论级别，开发者都必须返回实际验证命令、退出码、证据和未覆盖范围。

---

## 执行上下文（强约束）

- 本任务文件是正式主记录；主会话在派遣前补齐基线、范围和验证要求。
- **工作目录**：`E:\moxton-lotadmin`
- **基线提交 / 原有改动**：[主会话填写实际提交和差异]
- **允许改动范围**：[明确文件或模块]
- **前置依赖**：[无，或列出任务及所需状态和 API 契约]
- **必读文档**：
  - `E:\moxton-lotadmin\AGENTS.md`
  - `E:\moxton-ccb\03-guides\codex-desktop-workflow.md`
  - `E:\moxton-ccb\.codex\agents\admin-fe-dev.toml` 或 `admin-fe-qa.toml`
  - `E:\moxton-ccb\02-api\` 相关接口文档
- **回报方式**：直接向父会话返回 task_id、attempt、变更、命令及退出码、证据和阻塞；主会话更新状态。
- **证据目录**：`E:\moxton-ccb\05-verification\<TASK-ID>\attempt-<N>`。
- **恢复记录**：每轮记录最后完成步骤、开发/QA 结果、剩余问题和下次入口。

---

## 概述

### 问题陈述

[描述当前问题或需求]

### 解决方案

[描述解决方案的概述]

### 范围 (包含/排除)

**包含:**
- [功能1]
- [功能2]

**不包含:**
- [明确不包含的内容]

---

## 开发上下文

### 现有实现

[相关文件位置和当前实现]

### 依赖项

- [依赖1]
- [依赖2]

---

## 技术方案

### 页面结构

[页面布局和组件结构]

### 数据流

[数据获取和状态管理]

### API 调用

[需要调用的后端 API]

---

## 实施步骤

1. [步骤1]
2. [步骤2]
3. [步骤3]

---

## 验收标准

- [ ] [验收条件1]
- [ ] [验收条件2]
- [ ] [验收条件3]

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| [风险1] | [缓解措施] |

---

**相关文档:**
- [API 文档](../../02-api/)
- [项目状态](../../04-projects/moxton-lotadmin.md)
