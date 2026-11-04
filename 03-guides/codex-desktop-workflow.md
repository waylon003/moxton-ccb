# Codex 桌面主会话工作流

当前默认入口：在 `E:\moxton-ccb` 的 Codex 桌面会话中描述需求，由主会话组织开发，并按风险触发独立 QA。根 `AGENTS.md` 是指挥规则，任务 Markdown 是正式记录。

## 作用范围

项目配置只在文档中心 `.codex` 声明六个角色，不修改全局配置、模型、权限、MCP 或技能。其他目录的独立会话不会因本次项目文件变化而改变规则；同一仓库的新会话会加载相应项目规则。已打开会话需重新开启或显式读取更新后的规则。

角色文件是职责配置，不是自动隔离的进程或独立沙箱。工具没有角色选择参数时，主会话在派遣消息中要求读取对应 TOML。不能仅凭文件存在宣称当前桌面客户端已热加载角色。

## 新会话和恢复

1. 读取 `AGENTS.md`、`04-projects/CURRENT-ROUND.md`、`01-tasks/STATUS.md` 和目标任务。
2. 在目标仓库执行 `git rev-parse --show-toplevel`、`git status --short --branch` 和必要的差异检查，核对基线及原有修改。
3. 查看任务的执行模式、状态、当前 attempt、依赖、最后结果和下次入口。旧任务处于 migration_hold 时先核实实际代码，不重新开发已经实现的功能。
4. 若上轮中断，核对实际产物和可能仍在执行的任务；不能将旧子代理 ID 或旧 running JSON 当成存活证明。
5. 主会话执行期间继续跟进原生子代理；关闭应用后的无人值守续派不属于本版能力承诺。

## 计划与任务拆分

用户只要求讨论时先讨论；范围明确后使用 `01-tasks/templates` 的对应模板。每个任务写清业务目标、改动边界、前置依赖、API 契约、验收、回退和隔离环境。

任务正式状态按 `QA_LEVEL` 分流：`skip` 走 `planned -> ready -> in_progress -> dev_verified -> completed`；`smoke` 先做开发自测和轻量冒烟，再由主会话决定是否进入独立 QA；`full` 走 `planned -> ready -> in_progress -> waiting_qa -> qa -> qa_passed -> completed`。阻塞用 `blocked`，另记根因和恢复动作。迁移保留任务先使用 `migration_hold`，核实后由主会话选择正确入口。

同一任务只有主会话写正式状态；STATUS 是汇总。旧 TASK-LOCKS、route、controller 不同时参与。每次新执行或重试增加正整数 attempt，保留此前结果。

## 派遣

主会话使用当前可用的原生子代理能力，明确传入以下内容：

```text
task_file: E:\moxton-ccb\01-tasks\active\<domain>\<TASK-ID>-<slug>.md
task_id: <TASK-ID>
attempt: <N>
role_file: E:\moxton-ccb\.codex\agents\<role>.toml
workdir: <准确业务仓库或 worktree 的绝对路径>
baseline: <实际 Git 提交与原有未提交改动摘要>
allowed_files: <本任务允许改动的文件或模块>
dependencies: <已验证的依赖和 API 文档>
verification: <本次实际要求的命令和验收场景>
evidence: E:\moxton-ccb\05-verification\<TASK-ID>\attempt-<N>
```

不为子任务创建用户侧独立聊天。开发者按任务执行，直接向父会话回报；不再调用 report_route、旧控制器或 WezTerm。发现范围/环境/权限不符，返回阻塞分类、尝试和所需决策。

每个业务仓默认一个开发写入者；不同仓无依赖可并行。并行修改同仓前使用独立 worktree，并先保存未提交成果，确保验证对象包含要交付的代码。

原生子代理不能自动切换当前工具的工作目录，所有命令显式使用目标 workdir，并核对 Git 根。可写范围以实际会话权限为准；权限不足应回报，不能偷偷修改全局权限配置。

## 开发自测和风险触发 QA

开发回报必须包含 task_id、attempt、目标仓库/基线、变更文件、实际执行的命令和退出码、自测/冒烟证据、未覆盖场景、跨仓兼容性影响及剩余问题。开发阶段必须完成任务要求的类型检查、构建、单测或冒烟；主会话检查实际差异和自测结果后，按 `QA_LEVEL` 决定完成或进入 waiting_qa。

默认触发规则：

| QA_LEVEL | 默认动作 | 典型任务 |
|----------|----------|----------|
| `skip` | 开发自测 + 主会话差异复核 | 文档、配置、纯重命名、无行为变化 |
| `smoke` | 开发自测 + 轻量冒烟；主会话按风险决定是否独立 QA | 简单 UI、字段展示、低风险页面 |
| `full` | 开发自测后必须独立 QA | 权限、支付、订单、数据库、邮件、跨仓契约、Agent 工具、生产影响 |

独立 QA 不是开发自测的重复执行者。被触发时，QA 优先检查权限、失败路径、跨仓契约、真实浏览器行为和副作用；已由开发可靠验证的命令不必机械重复。

QA 应检查任务全部适用标准，不把局部类型检查或首页可见性烟测替代完整业务验证。后端默认 build 仅覆盖局部文件，完整类型检查须另外记录。后台 lint 具有自动修复行为，只读检查必须禁用 fix。

QA 结果文件示例：

```json
{
  "task_id": "BACKEND-029",
  "attempt": 1,
  "worker": "backend-qa",
  "verdict": "PASS",
  "summary": "目标接口契约、权限和失败路径通过",
  "commands": [{"command": "npm test", "exit_code": 0}],
  "checks": {
    "contract": {"pass": true, "evidence": ["05-verification/BACKEND-029/attempt-1/contract.json"]},
    "network": {"pass": true, "has_5xx": false, "evidence": ["05-verification/BACKEND-029/attempt-1/network.json"]},
    "failure_path": {"pass": true, "evidence": ["05-verification/BACKEND-029/attempt-1/failure-path.json"]}
  }
}
```

`backend` 必需 contract/network/failure_path；`frontend` 必需 ui/console/network/failure_path，console 要明确 error_count=0；`workflow` 仅用于指挥流程自身验收，必需 config/native_dispatch/scope/recovery，不用于替代业务 QA。

以主记录中的 task_id 和 attempt 运行：

```powershell
python scripts/validate-desktop-result.py --result 05-verification/BACKEND-029/attempt-1/result.json --task-id BACKEND-029 --attempt 1 --kind backend
```

校验器只检查结果合同和证据路径，不证明截图或日志内容正确；主会话仍须阅读证据。旧 attempt、其他任务路径、缺失文件、失败命令、5xx 和控制台错误均不能 PASS。预期错误路径的 5xx 必须在隔离的 failure_path 证据中说明，正常链路 network 仍须无未处理 5xx。

环境不可用、缺少身份或未测场景返回 BLOCKED；代码不符返回 FAIL。已知基线失败写入限制和恢复计划，不能隐瞒后继续声称整体绿色。生产数据写入、发信、支付和迁移需有明确任务授权。

独立 QA 通过后进入 qa_passed；未触发 QA 时，主会话核对开发自测、差异和限制后进入 dev_verified。两种路径都要同步 API 文档并记录集成情况后才能 completed。任务完成、Git 提交、推送和部署分开；不默认自动推送或部署。

## 证据和干净工作区

- 原始证据：`05-verification/<TASK-ID>/attempt-<N>/`，本地忽略；脱敏摘要：`05-verification/<TASK-ID>/summary.md`，可以提交。
- 测试身份、客户表格、部署产物、缓存、PID、旧运行数据库和快照保持本地；不能将密码和 Token 写入角色文件或公开报告。
- 正式任务、API 文档、指南、报告和必要产品素材纳入版本管理。增加 ignore 不会自动取消已跟踪文件。
- 原有成果与本轮迁移或业务交付分开提交，不批量 git add 整仓，不覆盖其他会话的未提交文件。
- 文档中心迁移前快照保存在 `runtime/migrations/desktop-20261102-172903`，内有 before.zip、manifest.json 与四仓 patch。manifest 中 SHA-256 用于校验，恢复时先解压到受控临时目录并逐项核对，不覆盖正在修改的工作区。

## 日常指令

- “先讨论这个需求，拆成后端和后台任务，先不执行。”
- “按确认的任务派遣开发，按 QA_LEVEL 和风险决定是否独立 QA。”
- “恢复当前轮次，核对实际代码后继续未完成任务。”
- “汇总本轮变更、验证、阻塞和下次入口。”

配置及合同回归：`python -m unittest discover -s tests -p test_desktop_workflow.py -v`。Python 3.11 使用标准 tomllib；当前 Python 3.10 的测试工具复用已安装 pip 自带的 TOML 解析器，无需改全局环境或安装依赖。
