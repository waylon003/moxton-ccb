# Ops-Task: 启动本机 3033 后端服务（供前端联调/QA）

**任务ID:** BACKEND-016
**创建时间:** 2026-03-19
**状态:** 准备执行
**角色:** 后端工程师（运维支持）
**项目:** moxton-lotapi (E:\moxton-lotapi)
**优先级:** P1
**技术栈:** Node.js + Koa + TypeScript

---

## 执行上下文（强约束）

- **Task File = 唯一执行输入源**
- **工作目录**：`E:\moxton-lotapi`
- **开始后 60 秒内**：必须 `report_route(status="in_progress")`
- **执行中每 90~120 秒**：发送一次 `in_progress` 心跳
- **遇阻塞 2 分钟内**：`report_route(status="blocked", body="blocker_type=...;question=...;attempted=...;next_action_needed=...")`
- **完成后必须**：`report_route(status="success|fail|blocked", body=变更文件+命令+测试结果)`
- **注意**：本任务为运维支持，**不得修改代码**、不得提交任何文件。

---

## 目标

为前端联调/QA 提供可访问的后端服务：`http://localhost:3033`。

---

## 执行步骤

1. 在 `E:\moxton-lotapi` 启动开发服务（`npm run dev`）。
2. 确认健康检查可访问：`curl http://localhost:3033/health` 返回 200。
3. **保持服务运行**（不要退出进程），直到 Team Lead 通知可停止。

---

## 验收标准

- `http://localhost:3033/health` 可访问并返回 200。
- 服务保持运行供前端联调使用。

---

## 失败处理

- 若端口被占用或启动失败，立即 `report_route(status="blocked")`，说明占用进程/错误信息与需要的下一步操作。

<!-- AUTO-QA-SUMMARY:BEGIN -->
## QA 摘要（自动回写）

- 最后更新: `2026-03-20T16:47:57+08:00`
- QA Worker: `backend-qa`
- 路由状态: `success`
- 验收结论: `PASS`
- 结论摘要: 3033 端口当前由 E:\moxton-lotapi 的 ts-node-dev 开发服务持续监听，/health 与 /version 返回 200，异常路径返回标准 404，可供联调/QA 使用。
- 证据索引:
  - `contract`: `PASS` -> `05-verification/BACKEND-016/contract-check.json`, `05-verification/BACKEND-016/curl-health.txt`, `05-verification/BACKEND-016/curl-version.txt`
  - `failure_path`: `PASS` -> `05-verification/BACKEND-016/failure-path.json`, `05-verification/BACKEND-016/curl-health-not-found.txt`
  - `network`: `PASS` -> `05-verification/BACKEND-016/network.json`, `05-verification/BACKEND-016/process.json`, `05-verification/BACKEND-016/build.txt`, `05-verification/BACKEND-016/automated-test.json`, `05-verification/BACKEND-016/curl-health.txt`, `05-verification/BACKEND-016/curl-version.txt`
- 验证命令:
  - `node -e "const {spawnSync}=require('node:child_process');const r=spawnSync(process.execPath,['-v']);console.log(r.error?.code||'OK')"`
  - `npm run build`
  - `mcp__vitest__run_tests target=./tests/api/health.spec.ts format=detailed showLogs=true`
  - `curl.exe -sS -i http://localhost:3033/health`
  - `curl.exe -sS -i http://localhost:3033/version`
  - `curl.exe -sS -i http://localhost:3033/health-not-found`
- 原始证据仍以 `05-verification/` 中的文件为准。
<!-- AUTO-QA-SUMMARY:END -->
