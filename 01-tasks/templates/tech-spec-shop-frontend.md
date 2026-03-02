# Tech-Spec: [任务标题]

**任务ID:** SHOP-FE-XXX
**创建时间:** YYYY-MM-DD
**状态:** 准备开发
**角色:** 独立站前端工程师
**项目:** nuxt-moxton
**优先级:** [P0|P1|P2|P3]
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia

---

## 执行上下文（强约束）

- **Task File = 唯一执行输入源**：派遣消息可能是短文本，必须以本任务文件为准，不得依赖派遣消息补充细节。
- **工作目录**：`E:\nuxt-moxton`
- **必读文档**：
  - `E:\nuxt-moxton\CLAUDE.md`
  - `E:\nuxt-moxton\AGENTS.md`
  - `E:\moxton-ccb\02-api\` 相关接口文档
- **开始后 60 秒内**：必须 `report_route(status="in_progress")`
- **执行中每 90~120 秒**：发送一次 `in_progress` 心跳
- **遇阻塞 2 分钟内**：`report_route(status="blocked", body="blocker_type=...;question=...;attempted=...;next_action_needed=...")`
- **完成后必须**：`report_route(status="success|fail|blocked", body=变更文件+命令+测试结果)`

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

### 架构设计

[架构图或设计说明]

### 数据模型

[数据结构变更]

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
- [项目状态](../../04-projects/nuxt-moxton.md)
