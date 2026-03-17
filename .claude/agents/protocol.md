# Multi-agent Relay Protocol

使用本协议统一 Team Lead 与各 Worker 的通信链路。主通道为 MCP `report_route`，禁止把 `[ROUTE]...[/ROUTE]` 当作必需协议。

## 短派遣兼容（重要）

- Team Lead 可能只发送短派遣消息（仅包含 `task_id` 和 `task_file`）。
- Worker 收到后必须立即读取 `task_file`，并以任务文件作为唯一执行输入源。
- 不得因为派遣消息较短而等待补充指令；如任务文件缺失信息，按阻塞协议上报。

## 主协议

所有跨角色消息都必须通过 `report_route` 上报：

```text
report_route(
  from: "<agent-name>",
  task: "<TASK-ID>",
  status: "in_progress" | "blocked" | "success" | "fail",
  body: "<结构化消息体>",
  run_id: "<派遣消息中的 route_run_id>"
)
```

约束：
- 若派遣消息中出现 `route_run_id`，Worker 每次 `report_route` 都必须原样带回同一个 `run_id`。
- 不得自行生成新的 `run_id`，也不得省略已提供的 `run_id`。

`body` 推荐使用 `key=value;` 结构，便于 Team Lead 自动解析。例如：

```text
stage=qa_running; progress=smoke_done; next=runtime_check
```

## 路由规则

1. 直接发给 Team Lead  
所有消息默认由 Team Lead 处理，不需要手写 `to: team-lead` 信封。

2. 需要跨角色协作  
由发送方使用 `status=blocked` 报告需求，`body` 中写明 `target_role=<role>; question=<...>; next_action_needed=<...>`，再由 Team Lead 决定是否派遣/转发。

3. 权限请求  
Worker 遇到审批卡点时必须发 `status=blocked` 给 Team Lead；Team Lead 审批低风险请求，高风险再升级给用户。

4. Team Lead 角色边界  
Team Lead 负责协调、派遣、审批、归档，不直接承担开发实现任务。

## 生命周期

1. Developer/QA 接任务后先回传一次 `status=in_progress`（开始心跳）。
2. 执行期间每 90~120 秒发送一次 `status=in_progress`。
3. 遇到阻塞在 2 分钟内发送 `status=blocked`。
4. 完成后发送 `status=success` 或 `status=fail`，并附证据摘要。
5. Team Lead 基于回传结果继续 `dispatch / dispatch-qa / archive`。

### ACK 行为（强制）

- 若派遣消息要求 ACK，必须通过 `report_route(status=in_progress, ...)` 完成 ACK，并在 `body` 中包含 `ack=1` 与 `first_step=<...>`。
- 不得仅发送聊天 ACK；ACK 必须可被 Team Lead 通过 route-monitor 捕获。
- 不得在 ACK 后停留等待用户“继续/确认”。
- 需要用户决策时，按阻塞协议 `report_route(status=blocked, ...)` 上报。

示例：

```text
report_route(
  from: "backend-dev",
  task: "BACKEND-014",
  status: "in_progress",
  body: "ack=1; first_step=read role_definition + protocol + task_file; next=scan repo + plan",
  run_id: "<route_run_id>"
)
```

## 阻塞上报（强制）

阻塞消息必须包含以下字段：

```text
blocker_type=<approval|api|env|dependency|unknown>;
question=<需要 Team Lead 决策/补充的信息>;
attempted=<已尝试动作>;
next_action_needed=<希望 Team Lead 执行的动作>
```

禁止在 pane 里提问后静默等待；需要决策时只能走 `report_route(status=blocked, ...)`。

## QA 回传合同

当 QA 回传 `status=success` 时，`body` 必须是 JSON，最小结构如下：

```json
{
  "task_id": "SHOP-FE-004",
  "worker": "shop-fe-qa",
  "verdict": "PASS",
  "summary": "一句话结论",
  "checks": {
    "network": { "pass": true, "has_5xx": false, "evidence": ["05-verification/SHOP-FE-004/network.json"] },
    "failure_path": { "pass": true, "scenario": "500 异常提示验证", "evidence": ["05-verification/SHOP-FE-004/failure-path.png"] }
  },
  "commands": ["pnpm test:e2e -- tests/e2e/smoke.spec.ts"],
  "changed_files": []
}
```

约束：
- `status=success` 时 `verdict` 必须为 `PASS`。
- 前端 QA 必须包含并通过：`checks.ui`、`checks.console`、`checks.network`、`checks.failure_path`。
- 后端 QA 必须包含并通过：`checks.contract`、`checks.network`、`checks.failure_path`。
- 每个检查项都必须带 `evidence` 文件路径且文件可访问。
- `checks.network.has_5xx=true` 时禁止回传 `success`。

不满足以上条件时，route-monitor 会自动把该条 success 降级为 `blocked`，并要求补证据后重跑 QA。

## 兼容说明

历史文档中的 `[ROUTE]...[/ROUTE]` 仅视为消息体格式示例，不再作为通信协议要求。
