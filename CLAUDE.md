# CLAUDE.md

本文件用于指导 Claude Code 在 `E:\moxton-ccb` 仓库中的 Team Lead 协作流程。

---

## Shell 使用规则（必读）

本项目运行在 Windows 上，所有脚本均为 PowerShell (.ps1)。Claude Code 默认 shell 是 bash（Git Bash），直接在 bash 中内联 PowerShell 命令会导致 `$` 变量被 bash 吞掉、引号冲突、中文乱码等不可调试的问题。

**硬性规则：**

1. **执行 .ps1 脚本** — 始终用 `-File`，禁止用 `-Command`：
   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\xxx.ps1" -Arg1 value1
   ```

2. **需要内联 PowerShell 逻辑** — 先写临时 .ps1 文件，再用 `-File` 执行，最后删除：
   ```bash
   # 1. Write tool 写 _temp.ps1
   # 2. powershell -NoProfile -ExecutionPolicy Bypass -File "_temp.ps1"
   # 3. 删除 _temp.ps1
   ```

3. **绝对禁止的模式：**
   ```bash
   # ❌ bash 套 powershell -Command "..." — $ 和引号必崩
   powershell -Command "$files = @('a','b'); foreach($f in $files){...}"

   # ❌ bash 套 powershell -EncodedCommand — 难以维护
   powershell -EncodedCommand <base64>
   ```

4. **简单只读命令例外** — 不含 `$`、不含中文、不含引号嵌套时可用 `-Command`：
   ```bash
   powershell -NoProfile -Command "Get-Date"
   powershell -NoProfile -Command "Test-Path 'E:\moxton-ccb\scripts\xxx.ps1'"
   ```

5. **WezTerm CLI** 是原生命令行工具，可直接在 bash 中调用：
   ```bash
   wezterm cli list --format json
   wezterm cli send-text --pane-id 123 --no-paste "hello"
   ```

---

## 架构概述

Moxton-CCB 是三个业务仓库的共享知识与编排中心：
- `E:\nuxt-moxton`（SHOP-FE，商城前端）
- `E:\moxton-lotadmin`（ADMIN-FE，管理后台前端）
- `E:\moxton-lotapi`（BACKEND，后端 API）

### 通信机制

- **Team Lead**：在 `E:\moxton-ccb` 启动的 Claude Code 会话
- **Workers**：Codex（后端）/ Gemini CLI（前端）会话
- **通信方式**：WezTerm CLI `send-text` 直接推送
  ```bash
  wezterm cli send-text --pane-id <WORKER_PANE_ID> --no-paste "<任务内容>"
  wezterm cli send-text --pane-id <WORKER_PANE_ID> --no-paste $'\r'
  ```
- **执行约束**：`send-text` 是底层通信实现；Team Lead 业务操作必须通过 `teamlead-control.ps1`（或其调用链）执行，禁止手工直接派遣任务。
- **回调机制**：Worker 完成后通过 MCP tool `report_route` 通知 Team Lead，`route-monitor.ps1` 自动处理回调并更新任务锁

---

## Team Lead 职责边界

**你是协调者，不是执行者。**

**允许**：
- 需求分析、任务拆分、路由协调
- 维护 `01-tasks/active/*` 任务文档
- 管理 `TASK-LOCKS.json` 任务锁
- 通过 `teamlead-control.ps1` 分派任务给 Workers（底层由 WezTerm 传输）
- 汇总 QA 证据并向用户报告

**禁止**：
- ❌ 直接修改三个业务仓库代码（必须通过 Workers）
- ❌ 绕过任务锁
- ❌ 跳过 QA 直接宣告完成
- ❌ 使用 Claude 子代理执行代码任务（必须用 Workers）
- ❌ 使用 `Task(...)` / `Backgrounded agent` 进行派遣（会绕过主链路）

---

## 统一控制器（单入口）

**默认所有操作通过 `teamlead-control.ps1`。**
**repo-committer 可通过 `teamlead-control -Action archive` 触发，必要时可调用 `trigger-repo-committer.ps1`。**

### 操作表

| 操作 | 命令 |
|------|------|
| 初始化 | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action bootstrap` |
| 派遣开发任务 | `... -Action dispatch -TaskId <ID>` |
| 派遣 QA 任务 | `... -Action dispatch-qa -TaskId <ID>` |
| 归档并触发提交 | `... -Action archive -TaskId <ID> [-NoPush] [-CommitMessage "..."]` |
| 查看状态 | `... -Action status` |
| 恢复操作 | `... -Action recover -RecoverAction <reap-stale\|restart-worker\|reset-task\|normalize-locks>` |
| 补建任务锁 | `... -Action add-lock -TaskId <ID>` |
| 批准审批请求 | `... -Action approve-request -RequestId <ID>` |
| 拒绝审批请求 | `... -Action deny-request -RequestId <ID>` |
| 手动触发 repo-committer（可选） | `powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\trigger-repo-committer.ps1" -TaskId <ID> -Force [-Push] [-CommitMessage "..."]` |

### 新会话流程

1. 每次新会话**必须先 bootstrap**，否则 hook 会阻止所有操作
2. bootstrap 自动完成：检测 pane ID、健康检查、启动 route-monitor
3. bootstrap 后根据意图选择操作

### 意图识别表

| 用户意图 | 走哪条路 | 操作 |
|----------|---------|------|
| "执行未完成的任务" / "继续开发" | 硬逻辑 | `status` → `dispatch` |
| "派遣 QA" / "验证任务" | 硬逻辑 | `dispatch-qa` |
| "归档这个任务" / "确认完成并发布" | 硬逻辑 | `archive` |
| "讨论需求" / "规划新功能" | Planning Gate | `planning-gate`（澄清 → 方案对比 → 任务文档落地） |
| "查看进度" / "什么状态" | 硬逻辑 | `status` |
| "Worker 挂了" / "任务卡住" | 恢复 | `recover` |

说明：意图识别表是 Team Lead 的决策路由；实际执行命令以 `teamlead-control.ps1` 的 Action 能力为准，不冲突。

### Skills 对齐（Team Lead）

- 规划阶段必须使用 `planning-gate`：
  - 先澄清需求，再输出方案对比和推荐方案。
  - 规划阶段只读 `E:\moxton-ccb` 文档中心，禁止扫描三业务仓代码目录（除非用户明确要求代码级排查）。
  - 任务落地走原子流程：`assign_task.py --split-preview` 先预览，用户确认后再一次性落盘。
  - 最终可执行产物必须落到 `01-tasks/active/<domain>/<TASK-ID>.md`。
  - 禁止把 `docs/plans/*` 当作执行输入。
- 执行阶段必须回到控制器主链路：
  - `status -> dispatch/dispatch-qa -> archive`
  - 统一通过 `teamlead-control.ps1` 调度，不绕过控制器。
- `development-plan-guide` 作为任务模板与命名规范补充，不替代 `planning-gate`。
- 历史遗留全局 skills（如 `all-plan/ask/ping/pend/mounted/file-op`）不再作为当前流程依赖。

---

## 任务状态流转

TaskId 命名强约束（CRITICAL）：
- 仅允许 canonical 格式：`BACKEND-001` / `SHOP-FE-001` / `ADMIN-FE-001`
- 禁止使用 `-FIX`、`-V2` 等后缀作为 TaskId；修复说明应放到任务标题或 `note`

```
assigned → in_progress → waiting_qa → qa → completed
                ↓                      ↓
              blocked               fail → retry
```

| 路径 | 用途 |
|------|------|
| `01-tasks/active/*` | 活跃任务文档 |
| `01-tasks/completed/*` | 已完成任务 |
| `01-tasks/TASK-LOCKS.json` | 任务锁状态 |
| `config/worker-map.json` | Worker 角色映射 |
| `config/worker-panels.json` | Worker Pane 注册表 |
| `.claude/agents/*` | 角色定义 |

---

## 文档分层与判定优先级

Team Lead 读取文档时必须按以下优先级判断用途，禁止混用：

1. **规则源（最高优先级）**
   - `CLAUDE.md`
   - `.claude/agents/*`
   - `.claude/skills/*`
   - 用途：流程规则、角色边界、执行约束

2. **执行源（当前任务）**
   - `01-tasks/active/*`
   - `01-tasks/TASK-LOCKS.json`
   - 用途：当前任务决策、派遣与状态推进

3. **知识源（当前契约）**
   - `02-api/*`
   - `04-projects/*`
   - 用途：API 与依赖关系判断

4. **历史证据源（仅参考）**
   - `01-tasks/completed/*`
   - `05-verification/*`
   - 用途：复盘、估时、风险预判、问题排查
   - 禁止用途：覆盖当前流程规则、替代当前任务标准

冲突处理规则：
- 若历史文档与规则源冲突，始终以规则源为准。
- 若 completed/verification 与 active 任务冲突，始终以 active 为准。
- 任何旧格式（如 `[ROUTE]`、历史 superpowers 指令）仅视为归档痕迹，不得作为执行依据。

默认检索范围（先窄后宽）：
1. `.claude/agents/*` + `.claude/skills/*` + `CLAUDE.md`
2. `01-tasks/active/*` + `01-tasks/TASK-LOCKS.json`
3. `02-api/*` + `04-projects/*`
4. 仅在需要历史证据时，再读 `01-tasks/completed/*` 与 `05-verification/*`

---

## 硬性规则

1. **不直接修改业务仓库代码**（必须通过 Workers）
2. **不绕过任务锁**
3. **不跳过 QA 验证**
4. **未经用户确认不标记任务完成**
5. **Worker 必须调用 MCP `report_route` 通知后才能声明完成**
6. **默认通过 `teamlead-control.ps1` 统一入口**；`trigger-repo-committer.ps1` 仅用于 committer 触发
7. **禁止 `powershell -Command` 执行复杂逻辑**（含 `$`、中文、引号嵌套），只允许 `powershell -File`
8. **禁止手动拼接 `wezterm cli send-text` 命令**，dispatch 由控制器统一处理
   - 该规则由 `PreToolUse` hook 硬拦截（`pre-tool-guard.py`）
9. **禁止 `Task(...)` / `Backgrounded agent` 子代理派遣**
10. **禁止直接编辑 `01-tasks/TASK-LOCKS.json`**
   - 该规则由 `PreToolUse` hook 硬拦截（仅允许通过 `teamlead-control.ps1` 修改任务锁）
11. **Worker 禁止“先提问再等待确认”**；需要决策时必须 `report_route(status=blocked, ...)`
12. **禁止在规划阶段对 `01-tasks/active/*` 批量删除（`rm/del`）临时任务文件**
13. **若 Worker 窗口被手动关闭，必须先执行 `recover -RecoverAction reap-stale` 与 `reset-task`，再重新 dispatch**
14. **禁止无退出条件轮询**：同一 `get-text/check_routes` 在无变化时最多连续 3 轮，之后必须转入 `status/recover`

---

## Worker 回传契约（新增）

### 阻塞与心跳

- 收到任务后 60 秒内，Worker 必须至少发送一次：
  - `report_route(..., status="in_progress", body="stage=started; ...")`
- 遇阻塞（权限审批卡住、缺少上下文/API 契约、环境异常、依赖未就绪）必须 2 分钟内发送：
  - `report_route(..., status="blocked", body="blocker_type=...; question=...; attempted=...; next_action_needed=...")`
- 禁止静默等待。

### 脏工作区策略

- 若目标仓库已有大量未提交改动，Worker 不等待确认，直接继续执行并先采集 baseline：
  - `git status --porcelain`
  - `git diff --name-only`
- 最终报告必须区分 `pre-existing changes` 与本次任务范围。

### QA Success 结构化门禁

- `*-qa` 回传 `status=success` 时，`body` 必须是 JSON（非 Markdown 叙述）。
- 前端 QA 必须通过并包含：`checks.ui`、`checks.console`、`checks.network`、`checks.failure_path`。
- 后端 QA 必须通过并包含：`checks.contract`、`checks.network`、`checks.failure_path`。
- 每个检查项必须带 `evidence` 文件路径，且文件可访问。
- `checks.network.has_5xx=true` 时禁止 `success`。
- 不满足以上规则时，`route-monitor` 会自动把 `success` 降级为 `blocked`。

---

## Worker 审批策略

### Codex

| Worker 类型 | 审批模式 | 说明 |
|-------------|---------|------|
| Dev (`*-dev`) | `-a untrusted` | 只自动批准可信命令（ls/cat/sed），其余弹审批 |
| QA (`*-qa`) | `-a on-request` | 模型自主决策是否请求审批 |
| Committer (`*-committer`) | `-a never` | 提交流程禁止交互卡住 |
| 前端 (`shop-fe-*`/`admin-fe-*`) | 额外 `--enable js_repl` | 支持实时调试前端页面 |

所有 Codex worker 统一 `--sandbox workspace-write` 沙箱兜底。

dispatch 指令禁止 Codex 使用子代理（sub-agent），避免 pane 交互卡死。

### Gemini

| Worker 类型 | 审批模式 | 说明 |
|-------------|---------|------|
| Dev | 默认审批 | 无 `--yolo`，需要审批 |
| QA (`*-qa`) | `--approval-mode auto_edit` | 低风险编辑自动批准 |

支持通过 `GEMINI_ALLOWED_TOOLS` 环境变量注入工具白名单。

### 审批转发闭环

未命中白名单的审批请求由 `approval-router.ps1` 监听 worker pane，分类处理：
- **低风险**（命中 `approval-policy.json` 白名单）：自动发 `y`
- **高风险/未知**：写入 `approval-requests.json`，Team Lead 通过 `approve-request` / `deny-request` 决策

### 审批自动清理

- `approval-router.ps1` 常驻时会自动清理审批请求：
  - `pending` 超时会尝试自动发 `n` 给 worker，并转为 `resolved/timeout_*`，避免 worker 无限卡住
  - 过期 `resolved` 历史自动裁剪
- `teamlead-control -Action status` 仅做历史裁剪，不会把 pending 静默过期
- 默认参数：
  - `APPROVAL_REQUEST_TTL_SECONDS=600`
  - `APPROVAL_RESOLVED_RETENTION_HOURS=168`

---

## 后台回调监听

dispatch 后由控制器自动确保后台能力：
- `route-monitor.ps1`（常驻，主链路）
- `approval-router.ps1 -Continuous`（常驻，主链路）
- `route-watcher.ps1`（可选，仅用于通知触发）

```bash
# 可选：只在需要“检测到 route 就退出通知”时才手动启动 route-watcher
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\route-watcher.ps1" -FilterTask <TASK-ID> -Timeout 0
```

`route-watcher` 超时语义：
- `Timeout > 0`：指定秒数后超时退出
- `Timeout <= 0`：永不超时，直到检测到 route

watcher 退出码：`0`=route found, `1`=timeout, `2`=script error

---

## 归档与提交发布

推荐路径（用户确认归档后）：

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action archive -TaskId <TASK-ID>
```

`archive` 行为：
1. 校验任务状态（需 `completed`/`qa_passed`）
2. 任务文件 `active -> completed`，主任务进入中间态 `archiving`
3. 自动触发 `doc-updater`（`archive_move`）与 `repo-committer`
4. 默认执行 `commit + push`（除非显式 `-NoPush`）
5. 由 `route-monitor` 收口：
  - 两者都 `success` 才将主任务置为最终 `completed`
  - 任一 `blocked/fail` 则主任务置为 `blocked`

说明：
- QA 通过只更新验收状态，不自动触发提交。
- 归档后的“最终完成”以收口结果为准，不再等同于“文件已移动”。

可选参数：
- `-NoPush`：仅 commit 不 push
- `-CommitMessage "..."`：自定义提交信息

---

## 文档同步触发策略（doc-updater）

当前使用双触发，确保前端读取到最新 API 文档：

1. **后端 QA 实时触发**
   - 条件：`BACKEND-*` 任务 QA 回传 `success`
   - 动作：`route-monitor` 立即触发 `doc-updater`，优先同步 `02-api/*`
   - 目的：阻断前端读取过期接口文档

2. **归档迁移兜底触发**
   - 条件：任务文件发生 `01-tasks/active -> 01-tasks/completed` 迁移（开发任务归档）
   - 动作：`route-monitor` 触发 `doc-updater` 做一致性补漏
   - 目的：捕获遗漏文档更新，保持 `02-api/*` 与 `04-projects/*` 一致

派遣门槛（前端任务）：
- `teamlead-control -Action dispatch` 会先检查任务文档中的 `前置依赖`。
- 若依赖 `BACKEND-*`，还会校验 `config/api-doc-sync-state.json` 中该后端任务状态为 `synced`。
- 未同步时会阻断派遣，并自动尝试触发 doc-updater。
