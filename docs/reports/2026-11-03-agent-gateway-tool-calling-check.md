# Agent 模型网关工具调用核查

日期：2026-11-03（Asia/Shanghai）。执行者：文档中心主会话。

## 结论

用户提供的第三方网关 `https://yfy-new.zhouyang168.top/v1` 在本次有效凭据下可访问。网关返回的 `gpt-5.6-sol` 和用户随后指定的 `gpt-6.1-sol`，均已通过 Chat Completions 的指定工具与自动选择工具两种完整往返测试，可作为首期后台只读助手的已验证候选模型。

本次只证明该网关、上述两个模型在合成用例下的基本工具调用兼容性，没有验证全部模型、生产稳定性、复杂查询准确率或流式调用。尚未开发助手功能或部署服务。

## 已确认的需求方向

- 使用者：内部运营员工。
- 入口：现有管理后台内嵌助手。
- 首期业务：预售线索、产品测试申请和相关商品信息。
- 操作范围：只读查询与分析；不修改状态/备注，不发送邮件、不操作支付。
- 模型数据范围：脱敏摘要，联系方式、详细地址和备注原文留在本地业务系统；聊天输入也需要纳入数据边界设计。
- 推荐结构：后台助手界面 → 现有 Koa 后端身份与权限 → 模型和受限业务查询工具 → 现有查询逻辑。统计由后端计算，回答附筛选条件、数据范围及后台记录链接。

以上为讨论中已选择的方向，尚未形成开发任务或完整实现规格；原有四个业务任务仍保留原状态。

## 配置与模型列表

测试读取 `runtime/agent-test.env` 中的 `AGENT_BASE_URL`、`AGENT_API_KEY`、`AGENT_MODEL`；文件被 Git 忽略，不在报告或聊天中复制密钥。用户仅填写密钥，`AGENT_MODEL` 为空，本次测试代码临时选择 `gpt-5.6-sol`，未回写默认模型配置。

认证 `GET /v1/models` 返回 HTTP 200，耗时约 1.43 秒，返回 7 个模型标识：`codex-auto-review`、`gpt-5.6-sol`、`gpt-5.6-terra`、`gpt-6-astra`、`gpt-6-sol`、`gpt-6.1-sol`、`gpt-6.1-terra`。这些标识来自网关响应，不等同于对上游模型来源、能力或定价的独立验证。

官方调用格式参考：[OpenAI function calling 文档](https://developers.openai.com/api/docs/guides/function-calling)，本轮实际获取正文，确认 Chat Completions 的 `tool_calls`、`tool_choice` 及工具结果回传流程。

## 实际测试

工具为本地模拟函数 `get_test_application_summary`，只接收国家与申请状态。测试要求查询 `Australia`、`APPLIED`，工具返回模拟数量 `23` 和核验标识 `SYNTHETIC-7Q3`；没有连接业务数据库。

| 场景 | 首次请求 | 回传工具结果 | 验证结果 |
|------|----------|--------------|----------|
| 指定工具 `tool_choice={type:function,...}` | HTTP 200，约 2.78 秒 | HTTP 200，约 1.78 秒 | 函数名、JSON 参数、tool call ID 有效；最终回答包含准确数量和核验标识 |
| 自动选择工具 `tool_choice=auto` | HTTP 200，约 3.12 秒 | HTTP 200，约 1.98 秒 | 同样完成工具选择、参数生成和结果消费 |

上表 `gpt-5.6-sol` 的四个推理请求均使用 `/v1/chat/completions`，工具结果作为 `role=tool`、关联 `tool_call_id` 回传，第二轮使用 `tool_choice=none`。服务端返回的模型标识与请求一致；所有函数参数在本地断言为 `{country:Australia,status:APPLIED}`，最终回答同时包含 `23` 和 `SYNTHETIC-7Q3`。

本次请求没有启用 strict schema、流式输出、并行工具或多工具连续规划，这些能力未验证。网关四个请求报告的 `total_tokens` 合计为 18348；这是网关提供的用量字段，本次没有查询其价格或实际扣费。

## 补充：gpt-6.1-sol

按用户要求使用相同的工具 schema、合成参数和核验结果测试 `gpt-6.1-sol`，通过命令行覆盖模型，不修改 `agent-test.env`。

| 场景 | 首次请求 | 回传工具结果 | 结果 |
|------|----------|--------------|------|
| 指定工具 | HTTP 200，约 3.54 秒 | HTTP 200，约 2.01 秒 | 工具名、参数、结果消费均通过，完整往返约 5.54 秒 |
| 自动选择工具 | HTTP 200，约 4.06 秒 | HTTP 200，约 2.11 秒 | 同样通过，完整往返约 6.18 秒 |

四个响应的模型标识均为 `gpt-6.1-sol`；数量 `23`、核验标识 `SYNTHETIC-7Q3` 均被最终回答准确引用。网关报告四个请求总 token 数为 17752；这次少量用例不构成性能、质量或费用优劣比较。

```powershell
node runtime/audits/agent-gateway-20261103/probe-tools.cjs forced gpt-6.1-sol
node runtime/audits/agent-gateway-20261103/probe-tools.cjs auto gpt-6.1-sol
```

两条命令均退出 0。证据为 `tool-call-result-gpt-6.1-sol-forced.json` 和 `tool-call-result-gpt-6.1-sol-auto.json`；旧模型证据完整保留。仍只使用合成数据，没有访问数据库或发送客户内容。

## 初次测试命令

执行命令（工作目录 `E:\moxton-ccb`，PowerShell 7）：

```powershell
node runtime/audits/agent-gateway-20261103/probe-tools.cjs
node runtime/audits/agent-gateway-20261103/probe-tools.cjs auto
```

两次命令均退出 0。首个命令在脚本尚未增加 `choiceMode` 参数时执行指定工具测试，后续增加参数只为保存独立自动选择测试结果。重新运行会调用网关并可能产生用量，不属于纯本地检查。

## 证据与下一步

本地证据位于 `runtime/audits/agent-gateway-20261103/`：`models-result.json`、`tool-call-result.json`、`tool-call-result-auto.json` 和模拟探针代码。结果中没有 API 密钥或客户内容，全部运行资产保持本地。

下一步细化只读工具清单、字段白名单、输入脱敏、后台入口、权限和验收标准，再落地正式任务；不得将本次模型兼容性通过当成业务 QA PASS。无需为首期先增加独立 MCP 服务、多 Agent 或向量库。
