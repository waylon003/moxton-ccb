# Dispatch Prompt 标准模板

以下为 Team Lead 向 Codex Worker 分派任务时的标准 prompt 结构。
使用文件路径引用，Codex 在 `E:\` 启动后可直接读取。

---

## 模板

```markdown
## 角色
读取并严格遵守: E:\moxton-ccb\.claude\agents\<role>.md

## 任务
读取任务文档: E:\moxton-ccb\01-tasks\active\<domain>\<TASK-ID>.md

## 参考文档
- API 文档: E:\moxton-ccb\02-api\<relevant>.md
- 仓库说明: <repo>\CLAUDE.md
- 仓库结构: <repo>\AGENTS.md

## 工作目录
所有代码操作在 <repo> 目录下执行。

## 强制规则
1. 修改 UI 组件前，必须先用 MCP 查询该组件的 API 文档
2. 修改现有文件前，必须先完整读取文件内容
3. 禁止重构现有文件结构，只做增量修改
4. 报告必须包含每个步骤的完整命令输出作为证据
```

---

## 占位符说明

| 占位符 | 含义 | 示例 |
|--------|------|------|
| `<role>` | 角色定义文件名（不含 .md） | `backend`, `admin-fe`, `shop-fe`, `backend-qa` |
| `<domain>` | 任务域目录 | `backend`, `admin-frontend`, `shop-frontend` |
| `<TASK-ID>` | 任务文件名 | `TASK-007-user-api.md` |
| `<relevant>` | 相关 API 文档文件名 | `users.md`, `products.md` |
| `<repo>` | 目标仓库绝对路径 | `E:\moxton-lotapi`, `E:\nuxt-moxton` |

---

## 使用示例

### 后端开发任务

```markdown
## 角色
读取并严格遵守: E:\moxton-ccb\.claude\agents\backend.md

## 任务
读取任务文档: E:\moxton-ccb\01-tasks\active\backend\TASK-007-user-api.md

## 参考文档
- API 文档: E:\moxton-ccb\02-api\users.md
- 仓库说明: E:\moxton-lotapi\CLAUDE.md
- 仓库结构: E:\moxton-lotapi\AGENTS.md

## 工作目录
所有代码操作在 E:\moxton-lotapi 目录下执行。

## 强制规则
1. 修改 UI 组件前，必须先用 MCP 查询该组件的 API 文档
2. 修改现有文件前，必须先完整读取文件内容
3. 禁止重构现有文件结构，只做增量修改
4. 报告必须包含每个步骤的完整命令输出作为证据
```

### QA 验收任务

```markdown
## 角色
读取并严格遵守: E:\moxton-ccb\.claude\agents\backend-qa.md

## 任务
读取任务文档: E:\moxton-ccb\01-tasks\active\backend\TASK-007-user-api.md

## 参考文档
- API 文档: E:\moxton-ccb\02-api\users.md
- QA 身份池: E:\moxton-ccb\05-verification\QA-IDENTITY-POOL.md
- 仓库说明: E:\moxton-lotapi\CLAUDE.md

## 工作目录
所有验证操作在 E:\moxton-lotapi 目录下执行。

## 强制规则
1. 修改现有文件前，必须先完整读取文件内容
2. 禁止重构现有文件结构，只做增量修改
3. 报告必须包含每个步骤的完整命令输出作为证据
```

### QA FAIL 修复派遣

当 QA 报告结果为 FAIL 时，Team Lead 使用此模板将修复任务派回给 dev worker。

```markdown
## 角色
读取并严格遵守: E:\moxton-ccb\.claude\agents\<role>.md

## 任务
修复 QA 验收失败项: E:\moxton-ccb\01-tasks\active\<domain>\<TASK-ID>.md

## QA 报告
读取 QA 报告，只修复其中标记为 FAIL 的项: <repo>\qa-<task-id>-report.md

## 参考文档
- API 文档: E:\moxton-ccb\02-api\<relevant>.md
- 仓库说明: <repo>\CLAUDE.md

## 工作目录
所有代码操作在 <repo> 目录下执行。

## 强制规则
1. 只修复 QA 报告中标记为 FAIL 的项，不要动其他代码
2. 修改现有文件前，必须先完整读取文件内容
3. 禁止重构无关代码
4. 修复完成后自行运行基线检查（build/typecheck）确认通过
5. 完成后输出修复摘要，列出每个 FAIL 项的修复方式
```
