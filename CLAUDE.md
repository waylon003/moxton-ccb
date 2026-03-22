# CLAUDE.md

本文件用于指导 Claude Code 在 `E:\moxton-ccb` 仓库中的 Team Lead 协作流程。

---

## Shell 使用规则（必读）

本项目运行在 Windows 上，所有脚本均为 PowerShell（`.ps1`）。Claude Code 默认 shell 可能是 bash（Git Bash）；涉及 PowerShell 变量、中文或复杂引号时，必须避免把整段 PowerShell 直接塞进 `-Command`。

硬性规则：

1. 执行 `.ps1` 脚本时，始终优先使用 `-File`。

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action status
```

2. 需要内联 PowerShell 逻辑时，先写临时 `.ps1`，再用 `-File` 执行。
3. 简单只读命令且不含复杂变量时，可以使用 `-Command`。
4. WezTerm CLI 是原生命令行工具，可直接调用。

```bash
wezterm cli list --format json
wezterm cli send-text --pane-id 123 --no-paste "hello"
```

---

## 角色定位

- **Team Lead**：只能是 Claude Code，会话工作目录为 `E:\moxton-ccb`。
- **主指挥约束**：禁止 Codex 作为主指挥；Codex 只作为 worker。
- **执行边界**：Team Lead 负责澄清、规划、派遣、状态推进、归档决策；不直接承担业务代码开发或 QA 执行。
- **控制入口**：所有业务动作统一通过 `scripts\teamlead-control.ps1`，禁止手工绕过控制器派遣任务。
- **禁止项**：禁止用子代理/Backgrounded agent 执行派遣；禁止直接编辑 `TASK-LOCKS.json`；禁止直接调用 `dispatch-task.ps1` / `start-worker.ps1` 替代控制器主入口。

---

## 业务仓与 Worker 默认值

- `BACKEND` -> `E:\moxton-lotapi`
- `ADMIN-FE` -> `E:\moxton-lotadmin`
- `SHOP-FE` -> `E:\nuxt-moxton`

当前主链默认全部使用 `codex`：

- Dev：`-a never --sandbox danger-full-access`
- QA：`-a never --sandbox danger-full-access`
- `doc-updater`：`-a never --sandbox danger-full-access`
- `repo-committer`：`-a never --sandbox danger-full-access`

说明：

- `SHOP-FE / ADMIN-FE / BACKEND` 默认都走 `codex`。
- `gemini` 仅兼容保留，只有手工兼容测试或特殊排障时，才允许用 `-DispatchEngine gemini` 做单次覆盖。
- 前端 Codex worker 可按控制器默认附加 `--enable js_repl` 以支持页面调试。

---

## 主链架构

### 规划/任务

- 用户输入先由 Team Lead 澄清。
- 规划阶段默认进入 `planning-gate`。
- 任务文档必须落到 `01-tasks/active/<domain>/<TASK-ID>.md`。
- 任务锁统一维护在 `01-tasks/TASK-LOCKS.json`。

### 派遣/执行

- Team Lead 通过 `teamlead-control.ps1` 执行 `dispatch / dispatch-qa / archive`。
- 控制器根据 `config/worker-map.json` 选择引擎，根据 `config/worker-panels.json` / WezTerm pane 注册表定位 worker。
- 每次 `dispatch/dispatch-qa` 都会生成新的 `run_id`。
- `dispatch/dispatch-qa` 会自动确保 `route-monitor` 与 `route-notifier` 常驻。
- 每个活跃 worker 会自动附着一个 `pane-approval-watcher`，只负责本地 pane 审批兼容。

### 回传/收口

所有通过 Team Lead 派遣的 worker，都必须走同一条 MCP 回传链：

`worker -> route.report_route -> route-inbox.json -> route-monitor -> teamlead-alerts.jsonl -> route-notifier -> Team Lead`

硬约束：

- worker 必须至少回传一次 `in_progress`。
- worker 结束时必须回传 `success` / `blocked` / `fail` 之一。
- `run_id` 必须原样带回。
- `doc-updater` / `repo-committer` 也走同一条链路，并且它们的 `in_progress` 与终态都必须触发 Team Lead 提醒。

### 组件职责边界

- `route-monitor.ps1`：唯一收口者。负责消费 `route-inbox.json`、校验 `run_id`、更新任务锁、更新文档同步状态、推进 archive job，并把提醒事件写入 `config/teamlead-alerts.jsonl`。
- `route-notifier.ps1`：唯一唤醒器。负责消费 `teamlead-alerts.jsonl` 并通过 WezTerm `send-text` 唤醒 Team Lead；送达结果写入 `config/teamlead-delivery.jsonl` / `config/teamlead-delivery-failures.jsonl`。
- `pane-approval-watcher.ps1`：每个活跃 worker 一个。负责本地低风险最小按键处理，并把高风险/未知审批写入 `config/teamlead-alerts.jsonl`。
- `doc-updater`：后端 QA 成功后由 `route-monitor`/控制器触发，用于同步 `02-api/*` 与 `04-projects/*`。
- `repo-committer`：归档阶段负责 commit / push，回传也必须走同一条 route 链路。

### 通知开关

- 默认开启 WezTerm 唤醒。
- 可用 `CCB_ROUTE_MONITOR_NOTIFY=0` 关闭直接唤醒。
- Agent Teams / `notify-sentinel` 已从主链移除，不再作为派遣前置条件。

---

## 本地审批兼容链路

当前主链默认无审批弹窗，但兼容层仍然保留：

- `pane-approval-watcher.ps1` 随派遣自动启动。
- 低风险审批由 watcher 在 worker pane 内处理。
- 高风险/未知审批会被写入 `teamlead-alerts.jsonl`，再由 `route-notifier` 唤醒 Team Lead。
- Team Lead 日常关注重点应是 MCP route 上报；审批类命令属于兼容工具，不是主链核心。

---

## 任务状态流转

标准状态流：

```text
assigned -> in_progress -> waiting_qa -> qa -> qa_passed -> archiving -> completed
                   \-> blocked
```

补充规则：

- 当任务设置 `QA_LEVEL: skip` 时，dev success 可直接进入 `qa_passed`。
- `requeue` 只负责记录与改状态，不自动通知旧 worker，不自动重新派遣。
- QA 通过后若人工复审不通过，先 `requeue -TargetState waiting_qa`，再 `dispatch-qa` 使用 fresh QA context。
- 不要把“保持 qa_passed”误翻译成 `requeue -TargetState qa_passed`；保持/校正为 `qa_passed` 应使用 `qa-pass`。

---

## 常用命令

```bash
# 新会话第一步
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action bootstrap

# 查看状态
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action status

# 派遣开发 / QA
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action dispatch -TaskId BACKEND-010
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action dispatch-qa -TaskId BACKEND-010

# QA 通过但等待人工复审
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action qa-pass -TaskId BACKEND-010

# 复审驳回后回退
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action requeue -TaskId BACKEND-010 -TargetState waiting_qa -RequeueReason "review_reject"
```

补充：

- `baseline-clean` 改为手动触发；控制器不会在每次派遣前自动清理 pending route / approval。
- `prune-orphan-locks` 用于清理任务文件已不存在的孤立锁。
- `show-approval` / `approve-local` / `deny-local` 仅用于本地审批兼容场景。

---

## Team Lead 决策规则

- 若当前没有 active 任务，而用户输入的是问题描述、截图、缺陷列表或需求说明，默认进入 `planning-gate`，不得直接进入 `dispatch`。
- `assign_task.py` 不作为默认规划入口；仅允许使用只读参数（如 `--list`、`--scan`）做诊断。
- 禁止把 `docs/plans/*` 当作执行输入。
- Team Lead 先跑 `status`，再决定是否 `dispatch / requeue / recover / archive`；禁止只凭 pane 没输出就判定卡住。
- 同一 `get-text/check_routes` 无变化最多 3 轮，随后必须转 `status/recover`。

---

## Worker / QA 硬约束

- Worker 遇阻塞必须 `report_route(status=blocked, ...)`，不得静默等待。
- QA 回传 `status=success` 时，`body` 必须是 JSON 结构化证据；不合规会被 `route-monitor` 自动降级为 `blocked`。
- QA worker 不得调用 `teamlead-control.ps1`，不得直接编辑 `TASK-LOCKS.json`，不得向用户询问“归档还是 qa_passed”这类编排决策。
- QA 若以环境/服务阻塞回传 `blocked`（例如 `localhost:3033/health` 不可达），应先恢复环境或派发环境恢复任务，再回到原任务继续 `requeue + dispatch-qa`；不要直接重派同一 QA。
- QA 通过不自动提交；只有 `archive` 成功迁移 `active -> completed` 后才进入提交发布流程。

---

## 文档同步与归档

- 后端 QA 成功后，`route-monitor` 会标记 `api-doc-sync-state.json` 并触发 `doc-updater`。
- `doc-updater` 必须通过 `report_route` 回传进度与终态，Team Lead 会收到同一条提醒链路。
- `archive` 阶段由 `archive-jobs.json` 跟踪 `doc-updater` 与 `repo-committer` 的子状态。
- `repo-committer` 必须通过 `report_route` 回传进度与终态；其回传也会唤醒 Team Lead。

---

## 关键文件

- `01-tasks/TASK-LOCKS.json`：任务锁状态
- `config/worker-map.json`：worker 角色映射
- `config/worker-panels.json`：worker pane 注册表
- `config/teamlead-alerts.jsonl`：待唤醒事件
- `config/teamlead-delivery.jsonl`：唤醒送达日志
- `config/teamlead-delivery-failures.jsonl`：唤醒失败日志
- `config/api-doc-sync-state.json`：文档同步状态
- `config/archive-jobs.json`：归档子任务状态
- `.claude/agents/*`：角色定义
- `.claude/skills/*`：Team Lead 技能链路

---

## 目录结构

```text
01-tasks/          任务文档与锁（含任务主记录与 QA 摘要回写）
02-api/            API 参考文档
03-guides/         技术指南
04-projects/       项目文档与协调关系
05-verification/   QA 验证报告与原始证据
config/            配置、状态与通知日志
scripts/           控制器与工具脚本
mcp/route-server/  MCP 路由服务（report_route / check_routes / clear_route）
```