# 执行计划：Wave 3 — 角色系统 + 遗留修复

**创建时间:** 2026-02-27
**状态:** 待执行
**编排者:** Team Lead

---

## 任务清单

| ID | 任务 | 仓库 | dev worker | qa worker | 步骤数 |
|----|------|------|------------|-----------|--------|
| BACKEND-008 | 用户管理 API — Cart.ts 回归修复 | moxton-lotapi | backend-dev | backend-qa | 6 |
| BACKEND-010 | 角色系统扩展 — operator 角色 | moxton-lotapi | backend-dev | backend-qa | 10 |
| ADMIN-FE-008 | 用户管理页面 — 功能验证 | moxton-lotadmin | admin-fe-dev | admin-fe-qa | 6 |
| ADMIN-FE-009 | 角色门禁 + 菜单权限过滤 | moxton-lotadmin | admin-fe-dev | admin-fe-qa | 5 |
| SHOP-FE-002 | 登录注册 — UI 规范化 + API 修复 | nuxt-moxton | shop-fe-dev | shop-fe-qa | 5 |
| SHOP-FE-003 | 个人中心 — API 联调 + UI 规范化 | nuxt-moxton | shop-fe-dev | shop-fe-qa | 8 |

---

## 依赖关系图

```
BACKEND-008 ──QA PASS──→ ADMIN-FE-008 ──QA PASS──┐
                │                                   │
                └─doc-update                        ├──→ ADMIN-FE-009 ──QA PASS──→ done
                                                    │
BACKEND-010 ──QA PASS──→────────────────────────────┘
                │
                └─doc-update

SHOP-FE-002 ──QA PASS──→ SHOP-FE-003 ──QA PASS──→ done

全部完成 ──→ doc-updater 全量检查
```

**ADMIN-FE-009 双重依赖**: BACKEND-010 QA PASS + ADMIN-FE-008 QA PASS

---

## 分阶段执行编排

### Phase 1: 并行启动（无依赖任务）

| 线路 | 任务 | Worker | 说明 |
|------|------|--------|------|
| 后端线 | BACKEND-008 | backend-dev (Codex) | Cart.ts 一行修复，极快 |
| 商城线 | SHOP-FE-002 | shop-fe-dev (Gemini) | 登录注册，无后端依赖 |
| 管理线 | — | 等待 | 依赖 BACKEND-008 QA PASS |

**并行度**: 2 条线

---

### Phase 2: BACKEND-008 QA

| 线路 | 任务 | Worker | 说明 |
|------|------|--------|------|
| 后端线 | BACKEND-008 QA | backend-qa (Codex) | 验证 build 通过 + API 正常 |
| 商城线 | SHOP-FE-002 续 | shop-fe-dev (Gemini) | 继续开发 |
| 管理线 | — | 等待 | — |

**QA PASS 触发**:
- 解锁 ADMIN-FE-008 dev
- 解锁 BACKEND-010 dev
- 触发 doc-updater（如有 API 变更）

**QA FAIL 处理**: 带报告回 backend-dev 修复 → 修复后重新派 backend-qa

---

### Phase 3: 最大并行

| 线路 | 任务 | Worker | 说明 |
|------|------|--------|------|
| 后端线 | BACKEND-010 | backend-dev (Codex) | operator 角色后端实现 |
| 管理线 | ADMIN-FE-008 | admin-fe-dev (Codex) | 用户管理功能验证 |
| 商城线 | SHOP-FE-002 QA | shop-fe-qa (Gemini) | 登录注册 QA 验收 |
| 文档线 | BACKEND-008 文档 | doc-updater (Codex) | 更新 02-api/auth.md |

**并行度**: 4 条线（最大）

**SHOP-FE-002 QA PASS 触发**: 解锁 SHOP-FE-003 dev
**SHOP-FE-002 QA FAIL 处理**: 带报告回 shop-fe-dev 修复 → 重新派 shop-fe-qa

---

### Phase 4: 中段并行

| 线路 | 任务 | Worker | 说明 |
|------|------|--------|------|
| 后端线 | BACKEND-010 QA | backend-qa (Codex) | operator 角色 QA 验收 |
| 管理线 | ADMIN-FE-008 QA | admin-fe-qa (Codex) | 用户管理 QA 验收 |
| 商城线 | SHOP-FE-003 | shop-fe-dev (Gemini) | 个人中心开发 |

**并行度**: 3 条线

**BACKEND-010 QA PASS 触发**:
- 触发 doc-updater 更新 02-api/auth.md（operator 角色、requireRole）
- 检查 ADMIN-FE-008 QA 是否也 PASS → 如果是，解锁 ADMIN-FE-009

**ADMIN-FE-008 QA PASS 触发**:
- 检查 BACKEND-010 QA 是否也 PASS → 如果是，解锁 ADMIN-FE-009

**任一 QA FAIL**: 带报告回对应 dev 修复 → 重新派 qa

---

### Phase 5: 管理线收尾

| 线路 | 任务 | Worker | 说明 |
|------|------|--------|------|
| 管理线 | ADMIN-FE-009 | admin-fe-dev (Codex) | 角色门禁 + 菜单过滤 |
| 商城线 | SHOP-FE-003 续 | shop-fe-dev (Gemini) | 个人中心继续 |
| 文档线 | BACKEND-010 文档 | doc-updater (Codex) | 更新 02-api/auth.md |

**并行度**: 3 条线

---

### Phase 6: 最终 QA

| 线路 | 任务 | Worker | 说明 |
|------|------|--------|------|
| 管理线 | ADMIN-FE-009 QA | admin-fe-qa (Codex) | 角色门禁 QA（三角色全量验证） |
| 商城线 | SHOP-FE-003 QA | shop-fe-qa (Gemini) | 个人中心 QA 验收 |

**并行度**: 2 条线

---

### Phase 7: 全量文档检查

| 线路 | 任务 | Worker | 说明 |
|------|------|--------|------|
| 文档线 | 全量一致性检查 | doc-updater (Codex) | 02-api/ + 04-projects/ 全量校验 |

**触发条件**: 6 个任务全部 QA PASS

---

## 流转规则

### 正常流转
```
dev 完成 → 派 qa → QA PASS → doc-updater(后端API变更时) → 解锁下游依赖
```

### QA FAIL 修复闭环
```
QA FAIL → Team Lead 审阅报告 → 带 QA 报告重新 dispatch 给 dev → 修复 → 再派 qa
```
最多 3 轮 QA FAIL 修复，超过 3 轮上报用户决策。

### doc-updater 触发时机

| 触发点 | 更新范围 |
|--------|----------|
| BACKEND-008 QA PASS | `02-api/auth.md` — 确认用户管理端点 |
| BACKEND-010 QA PASS | `02-api/auth.md` — operator 角色、requireRole 中间件、getUserInfo 角色映射 |
| 全部完成 | `02-api/` + `04-projects/` 全量一致性检查 |

前端任务不触发 doc-updater（不涉及 API 端点变更）。

### 任务完成清理

每个任务 QA PASS 后，Team Lead 负责：
1. 归档 QA 报告 → `E:\moxton-ccb\05-verification\ccb-runs\`
2. 删除业务仓库中的临时文件（qa-*.log, qa-*.ps1）
3. 更新 TASK-LOCKS.json 状态为 completed
4. 移动任务文档到 `01-tasks/completed/`

---

## 关键路径

```
BACKEND-010 dev → BACKEND-010 QA → doc-update → ADMIN-FE-009 dev → ADMIN-FE-009 QA
```

这是最长链路，决定整体完成时间。BACKEND-010 有 10 个 Step，是最重的任务。

---

## 风险预案

| 风险 | 影响 | 预案 |
|------|------|------|
| BACKEND-008 QA FAIL | 阻塞管理线和后端线 | 一行修复，FAIL 概率极低；如 FAIL 立即修复 |
| BACKEND-010 QA FAIL | 阻塞 ADMIN-FE-009 | 10 步任务复杂度高，预留修复轮次 |
| Gemini 无 MCP 工具 | SHOP-FE QA 只能做 typecheck | 接受限制，运行时验证由 Team Lead 人工确认 |
| Codex spawn EPERM | build/e2e 测试无法执行 | 跳过 build 测试，聚焦 typecheck + API 验证 |
| 双重依赖等待 | ADMIN-FE-009 启动延迟 | 优先保障 BACKEND-010 进度（关键路径） |
