# Tech-Spec: 前端开发环境恢复（端口 3666 / _nuxt/builds/meta 500 / hydration 错误）

**任务ID:** SHOP-FE-014
**创建时间:** 2026-03-23
**状态:** 准备开发
**角色:** 独立站前端工程师
**项目:** nuxt-moxton (E:\nuxt-moxton)
**优先级:** P1
**技术栈:** Vue 3 + Nuxt 3 + TypeScript + Pinia + Reka UI + UnoCSS
**QA_LEVEL:** skip

---

## 执行上下文（强约束）

- **Task File = 唯一执行输入源**：派遣消息可能是短文本，必须以本任务文件为准，不得依赖派遣消息补充细节。
- **工作目录**：`E:\nuxt-moxton`
- **必读文档**：
  - `E:\nuxt-moxton\CLAUDE.md`
  - `E:\nuxt-moxton\AGENTS.md`
- **开始后 60 秒内**：必须 `report_route(status="in_progress")`
- **执行中每 90~120 秒**：发送一次 `in_progress` 心跳
- **遇阻塞 2 分钟内**：`report_route(status="blocked", body="blocker_type=...;question=...;attempted=...;next_action_needed=...")`
- **完成后必须**：`report_route(status="success|fail|blocked", body=变更文件+命令+测试结果)`

---

## 概述

### 问题陈述

SHOP-FE-013 的 QA 过程中，前端开发环境异常：
- 端口 **3666** 已有现成进程占用且运行时异常
- 首页请求触发 `/_nuxt/builds/meta/*.json` **500**
- 浏览器控制台存在 **manifest/hydration** 错误

导致无法完成支付页真实验收（要求 console=0 errors）。

### 目标

恢复前端开发环境，使：
- 端口 3666 可正常提供 Nuxt 开发服务
- `/_nuxt/builds/meta/*.json` 返回 200
- 首页无 manifest/hydration 错误

### 范围 (包含/排除)

**包含:**
- 排查并清理占用 3666 端口的异常进程
- 清理 Nuxt 本地构建缓存并重启 dev server
- 验证首页与关键资源请求正常

**不包含:**
- 业务逻辑改动
- 任何功能性需求变更

---

## 实施步骤

1. **排查并停止异常进程**
   - 找到占用 3666 端口的进程并停止（仅限当前项目相关进程）。

2. **清理本地构建缓存**
   - 清理 `.nuxt`（如存在），必要时清理 `.output`。

3. **重新启动前端开发服务**
   - 按项目规范启动 dev server（如 `pnpm dev`）。

4. **验证**
   - 访问首页，确认：
     - `/_nuxt/builds/meta/*.json` 返回 200
     - 控制台无 manifest/hydration 错误

---

## 验收标准

- [ ] 端口 3666 上 dev server 正常运行
- [ ] `/_nuxt/builds/meta/*.json` 返回 200
- [ ] 首页无 manifest/hydration 错误

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 清理缓存导致首次启动变慢 | 属正常现象，等待构建完成 |
| 发现并非环境问题而是代码问题 | 立即 `report_route(status="blocked")` 并说明原因 |

---

**相关任务:**
- SHOP-FE-013（支付意图智能复用）

<!-- AUTO-QA-SUMMARY:BEGIN -->
## QA 摘要（自动回写）

- 最后更新: `2026-03-23T18:12:15+08:00`
- QA Worker: `shop-fe-qa`
- 路由状态: `blocked`
- 结论摘要: 前端开发环境已恢复，但 QA success 合同无法完成，因为 Playwright 自带 chromium_headless_shell 在本机启动即崩溃。
- 原始证据仍以 `05-verification/` 中的文件为准。
<!-- AUTO-QA-SUMMARY:END -->
