# Tech-Spec: 修复后端启动 uuid ESM require 报错

**任务ID:** BACKEND-015
**创建时间:** 2026-03-12
**状态:** 准备开发
**角色:** 后端工程师
**项目:** moxton-lotapi (E:\moxton-lotapi)
**优先级:** P1
**技术栈:** Node.js + Koa + TypeScript + Prisma + MySQL
**QA_LEVEL:** full

---

## 执行上下文（强约束）

- **Task File = 唯一执行输入源**：派遣消息可能是短文本，必须以本任务文件为准，不得依赖派遣消息补充细节。
- **工作目录**：`E:\moxton-lotapi`
- **必读文档**：
  - `E:\moxton-lotapi\CLAUDE.md`
  - `E:\moxton-lotapi\AGENTS.md`
- **开始后 60 秒内**：必须 `report_route(status="in_progress")`
- **执行中每 90~120 秒**：发送一次 `in_progress` 心跳
- **遇阻塞 2 分钟内**：`report_route(status="blocked", body="blocker_type=...;question=...;attempted=...;next_action_needed=...")`
- **完成后必须**：`report_route(status="success|fail|blocked", body=变更文件+命令+测试结果)`
- **本机接口访问**：统一使用 `http://localhost:3033`（不要使用 `0.0.0.0`）
- **已授权执行**：可运行 `npm run dev` 与 `curl /health`、`curl /version` 验证；若 3033 端口被占用，允许停止占用进程后重试。

---

## 概述

### 问题陈述

后端开发环境启动报错，服务无法启动：

```
Error: require() of ES Module E:\moxton-lotapi\node_modules\uuid\dist-node\index.js from E:\moxton-lotapi\src\middleware\requestId.ts not supported.
Instead change the require of index.js in E:\moxton-lotapi\src\middleware\requestId.ts to a dynamic import() which is available in all CommonJS modules.
```

### 目标

修复 `requestId` 中间件对 `uuid` 的导入方式，确保后端能正常启动并生成请求 ID。

### 范围 (包含/排除)

**包含:**
- 修复 `src/middleware/requestId.ts` 中 `uuid` 的加载方式（兼容当前模块系统）
- 验证服务可启动并正常返回 `/health`

**不包含:**
- 与 requestId 无关的模块/依赖升级
- 业务逻辑变更

---

## 开发上下文

### 现有实现

- 目标文件：`src/middleware/requestId.ts`
- 报错来自 `uuid` 作为 ESM 模块被 CommonJS 方式 `require` 引入

### 依赖项

- 需遵循项目现有模块系统（CommonJS/ESM）的实际配置

---

## 技术方案

### 推荐修复方向（择一实现）

- 方案 A：使用 `import()` 动态导入 `uuid`（兼容 CommonJS）
- 方案 B：改为 ESModule 的 `import { v4 as uuidv4 } from 'uuid'` 并保证编译/运行配置可用
- 方案 C：使用已有项目内的 requestId 生成方式（若已有工具/封装）

> 实际选择需以仓库现有模块规范为准（以可启动为验收基准）。

---

## 实施步骤

1. 确认 `requestId.ts` 当前导入方式与项目模块配置（tsconfig/package.json）
2. 采用与仓库规范一致的导入方式修复 `uuid` 引用
3. 本地启动服务并访问 `/health` 验证

---

## 验收标准

- [ ] `npm run dev` 启动成功且无上述 ESM require 报错
- [ ] `/health` 可正常返回 200
- [ ] requestId 仍能正常注入（检查响应头或日志）

---

## 风险和注意事项

| 风险 | 缓解措施 |
|------|----------|
| 修改导入方式引入兼容问题 | 以项目现有模块规范为准，必要时回退至动态 import |

---

**相关文档:**
- `E:\moxton-lotapi\CLAUDE.md`
- `E:\moxton-lotapi\AGENTS.md`

<!-- AUTO-QA-SUMMARY:BEGIN -->
## QA 摘要（自动回写）

- 最后更新: `2026-03-17T15:17:14+08:00`
- QA Worker: `backend-qa`
- 路由状态: `fail`
- 验收结论: `FAIL`
- 结论摘要: requestId 的 uuid ESM 启动问题已修复并通过任务级运行时验收：npm run dev 可启动、/health 返回 200、响应头含 X-Request-ID；但当前仓库仍存在契约不一致和 2 个支付服务回归用例失败，因此本轮 QA 不能判定 PASS。
- 证据索引:
  - `build`: `PASS` -> `05-verification/BACKEND-015/build.log`, `05-verification/BACKEND-015/dev.stdout.20260317-151311.log`, `05-verification/BACKEND-015/dev.stderr.20260317-151311.log`, `05-verification/BACKEND-015/dev-process.json`
  - `contract`: `FAIL` -> `05-verification/BACKEND-015/contract-check.json`
  - `failure_path`: `PASS` -> `05-verification/BACKEND-015/failure-path.json`, `05-verification/BACKEND-015/health-post-response.txt`
  - `network`: `PASS` -> `05-verification/BACKEND-015/network.json`, `05-verification/BACKEND-015/health-response.txt`, `05-verification/BACKEND-015/version-response.txt`
  - `pre_existing_changes`: `PASS` -> `05-verification/BACKEND-015/pre-existing-changes.json`
  - `tests`: `FAIL` -> `05-verification/BACKEND-015/vitest.json`
- 验证命令:
  - `node -e "const {spawnSync}=require('node:child_process');const r=spawnSync(process.execPath,['-v']);console.log(r.error?.code||'OK')"`
  - `npm run build`
  - `npx vitest run tests\api`
  - `npx vitest run tests\api\health.spec.ts`
  - `npm run dev`
  - `curl.exe -sS -i http://localhost:3033/health`
  - `curl.exe -sS -i http://localhost:3033/version`
  - `curl.exe -sS -i -X POST http://localhost:3033/health`
- 原始证据仍以 `05-verification/` 中的文件为准。
<!-- AUTO-QA-SUMMARY:END -->
