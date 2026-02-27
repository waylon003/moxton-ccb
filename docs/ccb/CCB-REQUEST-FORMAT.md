# CCB Request 格式说明

## 更新内容

已修改 `scripts/assign_task.py` 中的 `write_ccb_request()` 函数，现在 CCB request 文件包含完整的角色模板内容。

## 新的 Request 格式

### 文件位置
`05-verification/ccb-runs/{REQ_ID}.request.json`

### JSON 结构

```json
{
  "req_id": "CCB-20260226-143022-123456-BACKEND-001",
  "created_at": "2026-02-26T14:30:22+08:00",
  "task_id": "BACKEND-001",
  "role_code": "BACKEND",
  "worker": "backend-dev",
  "repo": "E:\\moxton-lotapi",
  "task_path": "E:\\moxton-ccb\\01-tasks\\active\\backend\\BACKEND-001-payment-api.md",
  "note": "implement payment status query API",
  "role_prompts": {
    "dev_prompt_path": ".claude/agents/backend.md",
    "dev_prompt_content": "# Agent: Backend Developer\n\n你是 Moxton 后端工程师...",
    "qa_prompt_path": ".claude/agents/backend-qa.md",
    "qa_prompt_content": "# Agent: Backend QA\n\n你是 Moxton 后端 QA 工程师..."
  }
}
```

## 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `req_id` | string | CCB 请求唯一标识 |
| `created_at` | string | 创建时间（ISO 8601） |
| `task_id` | string | 任务 ID（如 BACKEND-001） |
| `role_code` | string | 角色代码（SHOP-FE/ADMIN-FE/BACKEND） |
| `worker` | string | Worker 名称（如 backend-dev） |
| `repo` | string | 目标代码仓库路径 |
| `task_path` | string | 任务文档完整路径 |
| `note` | string | 分派备注 |
| `role_prompts` | object | **新增：角色模板内容** |
| `role_prompts.dev_prompt_path` | string | 开发者角色模板路径 |
| `role_prompts.dev_prompt_content` | string | **开发者角色模板完整内容** |
| `role_prompts.qa_prompt_path` | string | QA 角色模板路径 |
| `role_prompts.qa_prompt_content` | string | **QA 角色模板完整内容** |

## 使用方式

### 1. Team Lead 分派任务

```bash
python scripts/assign_task.py --dispatch-ccb BACKEND-001
```

生成的 request 文件会包含：
- 任务信息
- 目标仓库
- **开发者角色模板完整内容**
- **QA 角色模板完整内容**

### 2. Codex Dev Worker 读取 Request

```javascript
// Codex worker 启动后
const request = JSON.parse(fs.readFileSync('05-verification/ccb-runs/{REQ_ID}.request.json'));

// 获取开发者角色定义
const devRole = request.role_prompts.dev_prompt_content;
console.log("My role:", devRole);

// 读取任务文档
const task = fs.readFileSync(request.task_path);

// 开始开发...
```

### 3. Codex QA Worker 读取 Request

```javascript
// QA worker 启动后
const request = JSON.parse(fs.readFileSync('05-verification/ccb-runs/{REQ_ID}.request.json'));

// 获取 QA 角色定义
const qaRole = request.role_prompts.qa_prompt_content;
console.log("My role:", qaRole);

// 开始验收...
```

## 优势

### ✅ 解决身份混淆问题

**之前的方案 3 问题**：
```
E:\nuxt-moxton\AGENTS.md
    ↓
Dev worker: 读到开发者角色 ✅
QA worker: 也读到开发者角色 ❌ (混淆！)
```

**现在的方案**：
```
CCB Request 包含两个角色模板
    ↓
Dev worker: 读取 role_prompts.dev_prompt_content ✅
QA worker: 读取 role_prompts.qa_prompt_content ✅
```

### ✅ 完整的上下文传递

- 不依赖 Codex 手动读取文件
- 所有信息在一个 request 文件中
- 便于调试和追踪

### ✅ 支持动态角色定义

- 可以为不同任务使用不同的角色模板
- 可以在分派时动态修改角色定义
- 便于 A/B 测试不同的提示词

## CCB 工作流程

```
Team Lead 分派任务
    ↓
write_ccb_request() 生成 request.json
    ↓ (包含 dev 和 qa 角色模板完整内容)
CCB 系统读取 request.json
    ↓
启动 Codex Dev Worker
    ↓ (注入 dev_prompt_content)
Dev Worker 获得开发者身份
    ↓
开发完成后
    ↓
启动 Codex QA Worker
    ↓ (注入 qa_prompt_content)
QA Worker 获得 QA 身份
    ↓
验收完成，写入 response.json
    ↓
Team Lead 轮询结果
```

## 下一步

### 1. 安装 CCB 本体

CCB 是什么？需要如何安装？请提供：
- CCB 的仓库地址或安装文档
- CCB 如何读取 request.json
- CCB 如何启动 Codex workers
- CCB 如何注入角色上下文

### 2. 测试 Request 生成

```bash
# 创建测试任务
python scripts/assign_task.py --intake "测试 CCB request 生成"

# 分派任务
python scripts/assign_task.py --dispatch-ccb BACKEND-001

# 查看生成的 request.json
cat 05-verification/ccb-runs/CCB-*.request.json
```

验证 `role_prompts` 字段是否包含完整的角色模板内容。

### 3. 更新 CCB 系统

确保 CCB 系统能够：
- 读取 `role_prompts.dev_prompt_content`
- 在启动 Dev Worker 时注入该内容
- 读取 `role_prompts.qa_prompt_content`
- 在启动 QA Worker 时注入该内容

## 相关文件

- `scripts/assign_task.py` - 已修改 `write_ccb_request()` 函数
- `05-verification/ccb-runs/*.request.json` - CCB request 文件
- `.claude/agents/*.md` - 角色模板源文件
