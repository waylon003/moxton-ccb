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

## QA 阻塞补充（2026-03-24）

- 结论：环境恢复已达成（首页 200、`/_nuxt/builds/meta/dev.json` 200、console 0 errors），但 **Playwright smoke 测试在本机崩溃**。
- 失败命令：`pnpm test:e2e -- tests/e2e/smoke.spec.ts`
- 报错关键字：`chromium_headless_shell` + `Invalid file descriptor to ICU data received`
- 证据目录：`E:\moxton-ccb\05-verification\SHOP-FE-014\`
  - `smoke.txt`
  - `playwright-console.txt`
  - `playwright-network.txt`
- 处理要求：必须修复本机 Playwright/Chromium 运行环境（或明确替代 smoke 的允许策略），**修复前不得重新派发 QA**。

<!-- AUTO-QA-SUMMARY:BEGIN -->
## QA 摘要（自动回写）

- 最后更新: `2026-03-24T15:13:19+08:00`
- QA Worker: `shop-fe-qa-2`
- 路由状态: `success`
- 验收结论: `PASS`
- 结论摘要: 前端开发环境已恢复：3666 dev server 正常，/_nuxt/builds/meta/dev.json 稳定返回 200，首页无 manifest/hydration 错误，type-check/build/smoke 全部通过；正常路径控制台仍有 4 条既有 Vue warning，但无 error。
- 证据索引:
  - `component_api`: `PASS` -> `05-verification/SHOP-FE-014/context7-notes.txt`
  - `console`: `PASS` -> `05-verification/SHOP-FE-014/playwright-console-final.txt`, `05-verification/SHOP-FE-014/browser-console-summary.txt`
  - `failure_path`: `PASS` -> `05-verification/SHOP-FE-014/failure-path-order-500.png`, `05-verification/SHOP-FE-014/failure-path-text.txt`
  - `network`: `PASS` -> `05-verification/SHOP-FE-014/playwright-network-final.txt`, `05-verification/SHOP-FE-014/meta-dev-response-stable.txt`
  - `ui`: `PASS` -> `05-verification/SHOP-FE-014/home-final-fresh.png`
- 验证命令:
  - `node -e "const {spawnSync}=require('node:child_process');const r=spawnSync(process.execPath,['-v']);console.log(r.error?.code||'OK')"`
  - `curl.exe -sS http://localhost:3033/health`
  - `pnpm type-check`
  - `pnpm build`
  - `pnpm test:e2e -- tests/e2e/smoke.spec.ts`
- 原始证据仍以 `05-verification/` 中的文件为准。
<!-- AUTO-QA-SUMMARY:END -->
