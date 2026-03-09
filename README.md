# Moxton-CCB 指挥中心

多 AI 协作的任务编排系统，协调三个业务仓库的开发工作。

## 架构

- **Team Lead**：Claude Code 会话（本仓库）— 需求拆分、任务分派、进度监控
- **Workers**：Codex / Gemini CLI — 在 WezTerm 多窗口中执行开发和 QA
- **通信**：WezTerm CLI `send-text`（底层）+ MCP `report_route` 回调 + `approval-router` 审批转发
- **控制入口**：`scripts/teamlead-control.ps1`（业务动作统一入口）

## 业务仓库

| 前缀 | 仓库 | Dev 引擎 | QA 引擎 |
|------|------|---------|---------|
| BACKEND | `E:\moxton-lotapi` | Codex (`-a untrusted`) | Codex (`-a on-request`) |
| ADMIN-FE | `E:\moxton-lotadmin` | Codex (`-a untrusted`) | Codex (`-a on-request`) |
| SHOP-FE | `E:\nuxt-moxton` | Gemini (default) | Codex (`-a on-request`) |

## 使用方式

所有操作通过统一控制器 `scripts/teamlead-control.ps1`：

```bash
# 新会话第一步
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\teamlead-control.ps1" -Action bootstrap

# 派遣任务
... -Action dispatch -TaskId BACKEND-010
... -Action dispatch -TaskId BACKEND-010 -DispatchEngine codex
... -Action dispatch-qa -TaskId BACKEND-010

# 复审驳回后回退但不自动派遣
... -Action requeue -TaskId BACKEND-010 -TargetState waiting_qa -RequeueReason "review_reject"

# 查看状态
... -Action status
```

派遣规则（强约束）：
- `dispatch/dispatch-qa` 必须串行执行（一次只执行一条）。
- 不要并行启动两条 dispatch 命令；同角色并发由控制器自动分配 worker pool 实例。
- 引擎默认来自 `worker-map.json`，可用 `-DispatchEngine codex|gemini` 做单次覆盖。
- `baseline-clean` 改为手动触发；控制器不会在每次派遣前自动清理 pending route / approval。
- `requeue` 只做“记录 + 改状态”，不会自动通知旧 worker，也不会自动重新派遣。
- QA 复审驳回后，默认 `requeue -> dispatch-qa`，并使用 fresh QA context。
- 每次 `dispatch/dispatch-qa` 都会生成新的 `run_id`；Worker 回传 `report_route` 时必须原样带回。
- `route-monitor` 会基于 `run_id + 当前锁状态` 忽略旧 worker 迟到 route，避免状态被写回漂移。
- 前端链路保留 `Playwright` 作为 smoke/回归基座，同时加入 `agent-browser` 作为真实浏览器交互验收增强层；不做替换。
- `agent-browser` 统一全局安装在 worker 所在机器环境中，不分别安装到 `nuxt-moxton` / `moxton-lotadmin` 仓库。

详细工作流程见 [CLAUDE.md](./CLAUDE.md)。

## 技能链路（Team Lead）

- **规划阶段**：`planning-gate`
  - 需求澄清 -> 方案对比 -> 任务文档落地
  - 只读 `E:\moxton-ccb` 文档中心，默认不扫描三业务仓代码
  - 最终产物必须落到 `01-tasks/active/<domain>/<TASK-ID>.md`
  - 禁止把 `docs/plans/*` 作为执行输入
- **执行阶段**：`teamlead-controller`
  - `status -> dispatch/dispatch-qa -> archive`
  - 统一调用 `teamlead-control.ps1`，禁止手工派遣
- **模板辅助**：`development-plan-guide`
  - 任务模板、命名规范、跨角色拆分参考

技能说明见 [.claude/skills/README.md](./.claude/skills/README.md)。

## 关键约束

- 禁止 Team Lead 使用子代理（`Task(...)` / `Backgrounded agent`）执行派遣。
- 禁止直接调用控制器子脚本（如 `dispatch-task.ps1` / `start-worker.ps1`）。
- 禁止 Team Lead 直接使用 `assign_task.py` 执行写入动作（建任务/改锁/拆分）；仅允许只读诊断参数。
- Worker 遇阻塞必须 `report_route(status=blocked, ...)`，不得静默等待。
- QA 回传 `status=success` 时，`body` 必须是 JSON 结构化证据；不合规会被 route-monitor 自动降级为 `blocked`。
- QA 通过不自动提交；仅在 `archive` 成功迁移 `active -> completed` 后触发提交发布流程。
- QA 通过后若复审不通过，先 `requeue -TargetState waiting_qa`，不要把驳回原因直接发到旧 QA 窗口。
- 前端 QA 默认顺序：`Playwright smoke -> agent-browser 真实交互验收 -> playwright-mcp/截图/网络证据补充`。
- Team Lead 监控 Worker 时禁止无限轮询：同一 `get-text/check_routes` 无变化最多 3 轮，随后必须转 `status/recover`。
- 高风险审批会由 `approval-router` 主动发送短唤醒消息到 Team Lead：`[APR] id=... task=... worker=... risk=...`。

## 目录结构

```
01-tasks/          任务文档与锁（含任务主记录与 QA 摘要回写）
02-api/            API 参考文档
03-guides/         技术指南
04-projects/       项目文档与协调关系
05-verification/   QA 验证报告与原始证据
config/            配置（worker-map、approval-policy）
scripts/           控制器与工具脚本
mcp/route-server/  MCP 路由服务（report_route / check_routes / clear_route）
```
