# CLAUDE.md

本文件用于指导 Claude Code 在 `E:\moxton-ccb` 仓库中的 Team Lead 协作流程。

---

## ⚠️ 启动必读

**每次启动新会话时，必须先执行**：

```bash
# 快速启动（推荐）
source .claude/init-teamlead.sh

# 或手动执行
export CCB_CALLER=claude
python scripts/assign_task.py --standard-entry
```

**详细启动步骤**：参见 `.claude/STARTUP-CHECKLIST.md`

---

## 项目概述

Moxton-CCB 是三个业务仓库的共享知识与编排中心：
- `E:\nuxt-moxton`（SHOP-FE，商城前端）
- `E:\moxton-lotadmin`（ADMIN-FE，管理后台前端）
- `E:\moxton-lotapi`（BACKEND，后端 API）

## 架构模式

- Team Lead：在 `E:\moxton-ccb` 启动的 Claude Code 会话
- Workers：
  - 后端（开发/QA）：Codex 会话（`python ccb -a codex`）
  - 前端（开发/QA）：Gemini CLI 会话（`python ccb -a gemini`）
- 通信：
  - Codex：CCB 桥接（`ask/cping`）或 WezTerm `send-text` 直接输入
  - Gemini：WezTerm `send-text` 直接输入（CCB ask 不支持 Gemini）
- 状态来源：`01-tasks/*` 和 `01-tasks/TASK-LOCKS.json`

## Team Lead 职责边界

**你是协调者，不是执行者。**

允许：
- 需求分析、任务拆分、路由协调
- 维护 `01-tasks/active/*` 任务文档
- 管理 `TASK-LOCKS.json` 任务锁
- 通过 WezTerm send-text 或 CCB ask 分派任务给 Workers
- 汇总 QA 证据并向用户报告

禁止：
- ❌ 直接修改三个业务仓库代码（必须通过 Workers）
- ❌ 绕过任务锁
- ❌ 跳过 QA 直接宣告完成
- ❌ 使用 Claude 子代理执行代码任务（必须用 Workers）

**关键原则**：
- 后端代码修改/QA → 分派给 Codex worker
- 前端代码修改/QA → 分派给 Gemini worker
- 你只负责协调、汇总、报告

## 工作流程

### 1. 模式检测

```bash
python scripts/assign_task.py --standard-entry
```

- 有 active 任务：执行模式
- 无 active 任务：规划模式

### 2. 规划模式

```bash
python scripts/assign_task.py --intake "需求描述"
python scripts/assign_task.py --split-request "需求描述"
```

### 3. 执行模式

```bash
python scripts/assign_task.py --dispatch-ccb <TASK-ID>
python scripts/assign_task.py --poll-ccb --ccb-worker <WORKER-NAME>
```

任务状态流转：`assigned -> in_progress -> qa -> completed/blocked`

## CCB 工作流程（WezTerm 环境）

### 前置条件

1. WezTerm 必须在 PATH 中：`D:\WezTerm-windows-20240203-110809-5046fc22`
2. CCB 脚本位置：`C:\Users\26249\AppData\Local\codex-dual\ccb`
3. CCB CLI 工具：`C:\Users\26249\AppData\Local\codex-dual\bin\` 下的 `ask`、`cping`

### 启动 Workers

Worker 分两类：Codex（后端）和 Gemini CLI（前端）。通过 WezTerm spawn 创建独立 pane。

#### Worker 分配

| Worker | 引擎 | 工作目录 | 说明 |
|--------|------|---------|------|
| backend-dev | Codex | `E:\moxton-lotapi` | 后端 API 开发 |
| backend-qa | Codex | `E:\moxton-lotapi` | 后端 QA 验收 |
| admin-fe-dev | Codex | `E:\moxton-lotadmin` | 管理后台开发 |
| admin-fe-qa | Codex | `E:\moxton-lotadmin` | 管理后台 QA |
| shop-fe-dev | Gemini | `E:\nuxt-moxton` | 商城前端开发 |
| shop-fe-qa | Gemini | `E:\nuxt-moxton` | 商城前端 QA |

#### Codex Worker 启动

```bash
# 从 Team Lead 会话中远程启动（推荐）
PATH="$PATH:/d/WezTerm-windows-20240203-110809-5046fc22" \
  wezterm cli spawn --cwd "E:/moxton-lotapi" -- \
  powershell.exe -NoExit -Command "python 'C:\Users\26249\AppData\Local\codex-dual\ccb' -a codex"
```

`-a` 参数会自动写入 `~/.codex/config.toml` 的 auto-approval 配置：
```toml
[projects."E:\\moxton-lotapi"]
trust_level = "trusted"
approval_policy = "never"
sandbox_mode = "danger-full-access"
```

**重要**：Codex 必须配置 `approval_policy = "never"` 和 `sandbox_mode = "danger-full-access"`，否则子代理会卡在审批环节无法执行 shell 命令。

#### Gemini Worker 启动

```bash
PATH="$PATH:/d/WezTerm-windows-20240203-110809-5046fc22" \
  wezterm cli spawn --cwd "E:/nuxt-moxton" -- \
  powershell.exe -NoExit -Command "python 'C:\Users\26249\AppData\Local\codex-dual\ccb' -a gemini"
```

Gemini CLI 全局配置位于 `C:\Users\26249\.gemini\settings.json`，已配置：
- `playwright` MCP server（`@playwright/mcp@0.0.68`）— 用于浏览器运行时验证

**注意**：Gemini 启动后状态栏应显示 `1 MCP server`，确认 playwright 加载成功。

### 验证 Worker 连通性

```bash
# 需要 cd 到对应仓库目录，且 WezTerm 在 PATH 中
cd E:\moxton-lotapi
PATH="$PATH:/d/WezTerm-windows-20240203-110809-5046fc22" python "C:\Users\26249\AppData\Local\codex-dual\bin\cping"
```

三个仓库都应返回 `✅ Codex connection OK (Session healthy)`。

### 分派任务

**推荐方式：WezTerm send-text 直接输入。** Codex 和 Gemini 都支持。

```bash
# 向指定 pane 发送 prompt
PATH="$PATH:/d/WezTerm-windows-20240203-110809-5046fc22" \
  wezterm cli send-text --pane-id <PANE_ID> --no-paste '<dispatch prompt>'

# 发送回车提交
PATH="$PATH:/d/WezTerm-windows-20240203-110809-5046fc22" \
  wezterm cli send-text --pane-id <PANE_ID> --no-paste $'\r'
```

**备选方式（仅 Codex）：CCB ask**

```bash
cd E:\moxton-lotapi
PATH="$PATH:/d/WezTerm-windows-20240203-110809-5046fc22" \
  CCB_CALLER=claude python "C:\Users\26249\AppData\Local\codex-dual\bin\ask" codex "<prompt>"
```

注意：CCB ask 不支持 Gemini，Gemini 只能用 send-text。

标准 dispatch 模板见：`config/dispatch-template.md`

Prompt 结构（路径引用）：
1. 角色定义 → 指向 `.claude/agents/<role>.md`
2. 任务文档 → 指向 `01-tasks/active/<domain>/<TASK-ID>.md`
3. 参考文档 → 指向 `02-api/<relevant>.md` 和仓库 CLAUDE.md/AGENTS.md
4. 工作目录 → 指定目标仓库路径
5. 强制规则

### 等待响应 / 检查状态

```bash
# 查看指定 pane 的输出
PATH="$PATH:/d/WezTerm-windows-20240203-110809-5046fc22" \
  wezterm cli get-text --pane-id <PANE_ID> 2>/dev/null | tail -25

# 列出所有 pane
PATH="$PATH:/d/WezTerm-windows-20240203-110809-5046fc22" wezterm cli list

# 检查 Codex 连通性（仅 Codex）
cd E:\moxton-lotapi
PATH="$PATH:/d/WezTerm-windows-20240203-110809-5046fc22" \
  CCB_CALLER=claude python "C:\Users\26249\AppData\Local\codex-dual\bin\cping"
```

## Doc-Updater 派遣规则

### 时机 1: 后端 API 变更验收通过后（实时）
后端任务 QA PASS 且涉及 API 端点新增/修改/删除时：
→ 立即派遣 doc-updater 更新 `02-api/` 文档

### 时机 2: 一轮任务全部完成后（兜底）
当前轮次所有任务状态为 completed 时：
→ 派遣 doc-updater 做全量文档一致性检查（`02-api/` + `04-projects/`）

详细角色定义见：`.claude/agents/doc-updater.md`
触发配置见：`config/ccb-routing.json` 的 `doc_update_triggers` 节

## QA FAIL 修复闭环

```
开发(dev) → QA → Team Lead 审阅 QA 报告
                    ↓
              PASS → 清理 + 标记 completed
              FAIL → 带 QA 报告重新 dispatch 给 dev → 修复后再派 QA
```

修复派遣模板见：`config/dispatch-template.md` 的"QA FAIL 修复派遣"章节。

## 任务完成清理规则

任务标记 completed 时，Team Lead 负责清理 QA 产出物：

1. **归档 QA 报告**：将业务仓库中的 `qa-*-report.md` 移动到 `E:\moxton-ccb\05-verification\ccb-runs\`
2. **删除临时日志**：删除业务仓库中的 `qa-*-build.log`、`qa-*-runtime.log`、`qa-*-precheck.log`、`qa-*-test-api.log` 等临时文件
3. **删除临时脚本**：删除 QA 过程中生成的 `qa-*.ps1`、`qa-*.sh` 等临时脚本

清理命令示例：
```bash
# 归档报告
mv <repo>/qa-*-report.md E:\moxton-ccb\05-verification\ccb-runs\

# 清理临时文件
rm <repo>/qa-*-build.log <repo>/qa-*-runtime.log <repo>/qa-*-precheck.log <repo>/qa-*-test-api.log
rm <repo>/qa-*.ps1
```

## 常用命令

```bash
python scripts/assign_task.py --doctor
python scripts/assign_task.py --list
python scripts/assign_task.py --scan
python scripts/assign_task.py --show-lock
python scripts/assign_task.py --show-task-locks
python scripts/assign_task.py --lock claude --lock-note "ccb mode"
```

## 关键路径

- `01-tasks/active/*`
- `01-tasks/completed/*`
- `01-tasks/TASK-LOCKS.json`
- `01-tasks/ACTIVE-RUNNER.md`
- `05-verification/ccb-runs/*`
- `.claude/agents/*`
- `config/ccb-routing.json`
- `config/dispatch-template.md`

## ROUTE 信封格式

```text
[ROUTE]
from: <agent-name>
to: <target-agent|team-lead>
type: <status|question|blocker|handoff|review>
task: <TASK-ID>
body: <message body>
[/ROUTE]
```

## 硬性规则

1. Team Lead 不直接修改业务仓库代码。
2. 不绕过任务锁。
3. 不跳过 QA 验证。
4. 未经用户确认不标记任务完成。
