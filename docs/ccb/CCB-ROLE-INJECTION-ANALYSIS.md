# CCB 角色模板注入分析报告

## 问题

CCB 是否将角色模板的上下文注入到 Codex workers？

## 分析结果

### ❌ 原始状态：**没有自动注入机制**

### ✅ 已修复：**现在 CCB Request 包含完整角色模板**

## 实施的解决方案

### 修改了 `write_ccb_request()` 函数

**位置**: `scripts/assign_task.py:616-656`

**改动**:
```python
def write_ccb_request(root: Path, task: TaskInfo, worker: str, note: str):
    # 读取开发者和 QA 角色模板内容
    dev_prompt_content = read_file(root / task.codex_dev_prompt)
    qa_prompt_content = read_file(root / task.codex_qa_prompt)

    payload = {
        # ... 原有字段 ...
        "role_prompts": {
            "dev_prompt_path": task.codex_dev_prompt,
            "dev_prompt_content": dev_prompt_content,  # ✅ 新增
            "qa_prompt_path": task.codex_qa_prompt,
            "qa_prompt_content": qa_prompt_content,    # ✅ 新增
        },
    }
```

### 新的 Request 格式

```json
{
  "req_id": "CCB-20260226-143022-123456-BACKEND-001",
  "task_id": "BACKEND-001",
  "role_code": "BACKEND",
  "worker": "backend-dev",
  "repo": "E:\\moxton-lotapi",
  "task_path": "E:\\moxton-ccb\\01-tasks\\active\\backend\\BACKEND-001.md",
  "role_prompts": {
    "dev_prompt_content": "# Agent: Backend Developer\n\n你是后端工程师...",
    "qa_prompt_content": "# Agent: Backend QA\n\n你是 QA 工程师..."
  }
}
```

## 为什么方案 3 不可行

### ❌ 方案 3: 在代码仓库添加 AGENTS.md

**问题**:
```
E:\nuxt-moxton\AGENTS.md (包含 shop-frontend.md)
    ↓
Dev Worker 启动 → ✅ 看到开发者角色
QA Worker 启动 → ❌ 也看到开发者角色（身份混淆！）
```

**根本原因**:
- 同一个仓库中，Dev 和 QA 需要不同的角色定义
- `AGENTS.md` 只能有一个文件
- 无法区分 Dev 和 QA 的身份

### ✅ 当前方案: CCB Request 包含两个角色模板

**优势**:
```
CCB Request 包含:
  - dev_prompt_content (开发者角色)
  - qa_prompt_content (QA 角色)
    ↓
Dev Worker: 读取 dev_prompt_content ✅
QA Worker: 读取 qa_prompt_content ✅
```

**解决了**:
- ✅ 身份明确，不会混淆
- ✅ 完整的上下文传递
- ✅ 支持动态角色定义
- ✅ 便于调试和追踪

## 工作流程

```
Team Lead 分派任务
    ↓
write_ccb_request() 读取角色模板文件
    ↓
生成 request.json (包含 dev 和 qa 角色模板完整内容)
    ↓
CCB 系统读取 request.json
    ↓
启动 Codex Dev Worker
    ↓ (注入 role_prompts.dev_prompt_content)
Dev Worker 获得开发者身份和职责定义
    ↓
开发完成
    ↓
启动 Codex QA Worker
    ↓ (注入 role_prompts.qa_prompt_content)
QA Worker 获得 QA 身份和验收标准
    ↓
验收完成，写入 response.json
```

## 下一步行动

### 1. 安装 CCB 本体

需要了解：
- CCB 是什么系统？
- 如何安装和配置？
- 如何读取 request.json？
- 如何启动 Codex workers 并注入角色上下文？

### 2. 测试 Request 生成

```bash
# 创建测试任务
python scripts/assign_task.py --intake "测试角色模板注入"

# 分派任务
python scripts/assign_task.py --dispatch-ccb BACKEND-001

# 查看生成的 request
cat 05-verification/ccb-runs/CCB-*.request.json | jq '.role_prompts'
```

验证 `role_prompts` 包含完整内容。

### 3. 更新 CCB 系统

确保 CCB 能够：
- 解析 `role_prompts.dev_prompt_content`
- 在启动 Dev Worker 时注入该内容到会话上下文
- 解析 `role_prompts.qa_prompt_content`
- 在启动 QA Worker 时注入该内容到会话上下文

## 相关文档

- `CCB-REQUEST-FORMAT.md` - 详细的 Request 格式说明
- `scripts/assign_task.py` - 已修改的脚本
- `.claude/agents/*.md` - 角色模板源文件
