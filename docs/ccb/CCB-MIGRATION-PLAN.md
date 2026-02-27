# CCB 迁移方案 - 从自定义 JSON 通信到标准 CCB 工具

## 项目概述

将 Moxton-CCB 项目从自定义 JSON 文件通信方案迁移到标准 CCB 工具（claude_code_bridge）。

## 迁移目标

- ✅ 使用 CCB 的 `ask/pend/ping` 命令替代 JSON 文件通信
- ✅ 使用 CCB 启动和管理 Codex workers
- ✅ 保留角色模板注入功能
- ✅ 保持 Team Lead 工作流程不变
- ✅ 利用 CCB 的可视化分割窗格

## 前置条件

- ✅ WezTerm 已安装: `D:\WezTerm-windows-20240203-110809-5046fc22`
- ✅ CCB 仓库已克隆: `/tmp/claude_code_bridge`
- ✅ Python 3.10+ 已安装
- ✅ Codex CLI 已安装

## 迁移步骤

### 阶段 1: 完成 CCB 安装

**任务 1.1: 将 WezTerm 添加到 PATH**

```powershell
# 添加 WezTerm 到系统 PATH
$wezterm_path = "D:\WezTerm-windows-20240203-110809-5046fc22"
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";$wezterm_path", [EnvironmentVariableTarget]::User)

# 验证
wezterm --version
```

**任务 1.2: 完成 CCB 安装**

```bash
cd /tmp/claude_code_bridge
bash ./install.sh install
```

**验证**:
```bash
ccb -v
# 应该显示: ccb v5.2.6
```

**任务 1.3: 配置 CCB 全局路径**

确保 `ccb` 命令在 PATH 中：
```bash
which ccb
# 应该显示: ~/.local/bin/ccb 或类似路径
```

---

### 阶段 2: 创建 CCB 配置文件

**任务 2.1: 创建项目 CCB 配置**

在 `E:\moxton-ccb\.ccb\ccb.config` 创建配置：

```
shop-fe-dev,admin-fe-dev,backend-dev,qa
```

**说明**:
- `shop-fe-dev`: 商城前端开发 worker
- `admin-fe-dev`: 管理后台开发 worker
- `backend-dev`: 后端开发 worker
- `qa`: QA 验收 worker

**任务 2.2: 创建 worker 启动脚本**

在 `E:\moxton-ccb\.ccb\` 创建各个 worker 的启动配置。

**文件**: `.ccb/shop-fe-dev.sh`
```bash
#!/bin/bash
cd /mnt/e/nuxt-moxton
codex --sandbox workspace-write --ask-for-approval on-request --add-dir /mnt/e/moxton-ccb
```

**文件**: `.ccb/admin-fe-dev.sh`
```bash
#!/bin/bash
cd /mnt/e/moxton-lotadmin
codex --sandbox workspace-write --ask-for-approval on-request --add-dir /mnt/e/moxton-ccb
```

**文件**: `.ccb/backend-dev.sh`
```bash
#!/bin/bash
cd /mnt/e/moxton-lotapi
codex --sandbox workspace-write --ask-for-approval on-request --add-dir /mnt/e/moxton-ccb
```

**文件**: `.ccb/qa.sh`
```bash
#!/bin/bash
cd /mnt/e/moxton-ccb
codex --sandbox workspace-write --ask-for-approval on-request --add-dir /mnt/e/nuxt-moxton --add-dir /mnt/e/moxton-lotadmin --add-dir /mnt/e/moxton-lotapi
```

---

### 阶段 3: 重构 `scripts/assign_task.py`

**任务 3.1: 添加 CCB 命令包装函数**

在 `scripts/assign_task.py` 中添加：

```python
import subprocess
from typing import Optional

def ccb_ask(worker: str, message: str) -> bool:
    """使用 CCB ask 命令向 worker 发送消息"""
    try:
        result = subprocess.run(
            ['ask', worker, message],
            capture_output=True,
            text=True,
            timeout=10
        )
        return result.returncode == 0
    except Exception as e:
        print(f"[ERROR] ccb_ask failed: {e}")
        return False

def ccb_pend(worker: str, timeout: int = 300) -> Optional[str]:
    """使用 CCB pend 命令等待 worker 响应"""
    try:
        result = subprocess.run(
            ['pend', worker],
            capture_output=True,
            text=True,
            timeout=timeout
        )
        if result.returncode == 0:
            return result.stdout.strip()
        return None
    except Exception as e:
        print(f"[ERROR] ccb_pend failed: {e}")
        return None

def ccb_ping(worker: str) -> bool:
    """使用 CCB ping 命令检查 worker 状态"""
    try:
        result = subprocess.run(
            ['ping', worker],
            capture_output=True,
            text=True,
            timeout=5
        )
        return result.returncode == 0
    except Exception as e:
        return False
```

**任务 3.2: 重构 `write_ccb_request()` 函数**

替换原有的 JSON 文件写入方式：

```python
def dispatch_ccb_task(root: Path, task: TaskInfo, worker: str, note: str) -> tuple[str, bool]:
    """使用 CCB ask 命令分派任务"""

    # 读取角色模板
    dev_prompt_path = root / task.codex_dev_prompt
    dev_prompt_content = ""
    if dev_prompt_path.exists():
        dev_prompt_content = dev_prompt_path.read_text(encoding="utf-8")

    # 读取任务文档
    task_content = ""
    task_path = Path(task.task_path)
    if task_path.exists():
        task_content = task_path.read_text(encoding="utf-8")

    # 构建完整提示词
    prompt = f"""# 角色定义

{dev_prompt_content}

---

# 任务文档

{task_content}

---

# 工作指令

1. 你的工作目录: {task.workdir}
2. 请阅读上述任务文档并实现所有要求
3. 完成后报告修改的文件列表和测试证据
4. 如有跨角色依赖，使用 [ROUTE] 信封格式向 Team Lead 发送消息

开始工作。
"""

    # 生成请求 ID（用于追踪）
    req_id = f"CCB-{datetime.now().astimezone().strftime('%Y%m%d-%H%M%S-%f')}-{task.task_id}"

    # 使用 CCB ask 命令发送
    success = ccb_ask(worker, prompt)

    if success:
        # 记录到日志文件（可选，用于审计）
        log_dir = root / "05-verification" / "ccb-runs"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_file = log_dir / f"{req_id}.log"
        log_file.write_text(
            f"Dispatched at: {datetime.now().isoformat()}\n"
            f"Task: {task.task_id}\n"
            f"Worker: {worker}\n"
            f"Note: {note}\n",
            encoding="utf-8"
        )

    return req_id, success
```

**任务 3.3: 重构 `--dispatch-ccb` 处理逻辑**

修改 `args.dispatch_ccb` 的处理部分：

```python
if args.dispatch_ccb:
    task_id = normalize_task_id(args.dispatch_ccb)
    task = find_task(tasks, task_id)
    if not task:
        print(f"[ERROR] task not found in active dirs: {task_id}")
        return 1

    # 检查 worker 是否在线
    worker = args.ccb_worker.strip() or default_ccb_worker(task)
    if not ccb_ping(worker):
        print(f"[ERROR] worker '{worker}' is not online")
        print(f"  Start CCB first: ccb {worker}")
        return 2

    # 分派任务
    req_id, success = dispatch_ccb_task(root, task, worker, args.ccb_note.strip())

    if success:
        # 更新任务锁
        upsert_task_lock(
            root,
            task_id=task_id,
            runner="claude",
            owner=worker,
            state="in_progress",
            note=f"ccb dispatch {req_id}",
        )

        print(f"[CCB] dispatched {task_id}")
        print(f"  req_id: {req_id}")
        print(f"  worker: {worker}")
        print(f"  Use 'pend {worker}' to wait for response")
    else:
        print(f"[ERROR] failed to dispatch task to {worker}")
        return 1

    did_work = True
```

**任务 3.4: 添加 `--poll-ccb` 的 CCB 实现**

```python
if args.poll_ccb:
    worker = args.ccb_worker.strip()
    if not worker:
        print("[ERROR] --poll-ccb requires --ccb-worker <WORKER-NAME>")
        return 1

    print(f"[CCB] polling worker: {worker}")
    print("  Waiting for response (Ctrl+C to cancel)...")

    response = ccb_pend(worker, timeout=args.ccb_timeout or 300)

    if response:
        print(f"[CCB] received response from {worker}:")
        print(response)

        # 解析响应并更新任务锁
        # TODO: 定义响应格式，例如 JSON 或特定标记

    else:
        print(f"[CCB] no response from {worker} (timeout or error)")

    did_work = True
```

---

### 阶段 4: 重构 `scripts/ccb_start.ps1`

**任务 4.1: 简化启动脚本**

替换整个 `scripts/ccb_start.ps1` 为：

```powershell
Param(
    [string]$Config = ".ccb\ccb.config"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "[CCB-START] Starting CCB with config: $Config"

# 检查 CCB 是否安装
$ccb_path = Get-Command ccb -ErrorAction SilentlyContinue
if (-not $ccb_path) {
    Write-Error "CCB not found. Please install CCB first."
    exit 1
}

# 启动 CCB
& ccb

Write-Host "[CCB-START] CCB started successfully"
Write-Host "  Use 'ask <worker> <message>' to send tasks"
Write-Host "  Use 'pend <worker>' to wait for responses"
Write-Host "  Use 'ping <worker>' to check status"
```

**任务 4.2: 创建快速启动脚本**

创建 `scripts/ccb_quick_start.sh`:

```bash
#!/bin/bash
# 快速启动 CCB 的便捷脚本

cd "$(dirname "$0")/.."

echo "[CCB] Starting workers..."
ccb

echo ""
echo "[CCB] Workers started. Available commands:"
echo "  ask shop-fe-dev 'message'   - Send to shop frontend"
echo "  ask admin-fe-dev 'message'  - Send to admin frontend"
echo "  ask backend-dev 'message'   - Send to backend"
echo "  ask qa 'message'            - Send to QA"
echo "  pend <worker>               - Wait for response"
echo "  ping <worker>               - Check status"
```

---

### 阶段 5: 更新文档

**任务 5.1: 更新 `CLAUDE.md`**

在 "工作流程" 章节添加 CCB 使用说明：

```markdown
## CCB 工作流程

### 启动 CCB Workers

```bash
# 方式 1: 使用配置文件启动所有 workers
ccb

# 方式 2: 启动特定 workers
ccb shop-fe-dev backend-dev
```

### 分派任务

```bash
# Team Lead 分派任务
python scripts/assign_task.py --dispatch-ccb BACKEND-001 --ccb-worker backend-dev
```

内部会调用:
```bash
ask backend-dev "角色定义 + 任务文档 + 工作指令"
```

### 等待响应

```bash
# 等待 worker 完成
pend backend-dev
```

### 检查状态

```bash
# 检查 worker 是否在线
ping backend-dev
```
```

**任务 5.2: 更新 `README.md`**

替换 "Quick Start" 章节：

```markdown
## Quick Start

1. 安装 WezTerm 和 CCB（一次性设置）

2. 启动 Claude Code 作为 Team Lead:
```bash
cd E:\moxton-ccb
# Claude Code 会自动加载 Team Lead 角色
```

3. 启动 CCB workers:
```bash
ccb
# 或使用脚本
powershell -ExecutionPolicy Bypass -File scripts/ccb_start.ps1
```

4. 创建和分派任务:
```bash
# 创建任务
python scripts/assign_task.py --intake "实现订单支付状态查询接口"

# 分派任务
python scripts/assign_task.py --dispatch-ccb BACKEND-001 --ccb-worker backend-dev

# 等待完成
pend backend-dev
```
```

**任务 5.3: 创建 CCB 迁移完成报告**

创建 `CCB-MIGRATION-COMPLETE.md` 记录迁移前后对比。

---

### 阶段 6: 测试和验证

**任务 6.1: 单元测试 CCB 命令包装**

创建 `tests/test_ccb_commands.py`:

```python
import pytest
from scripts.assign_task import ccb_ask, ccb_pend, ccb_ping

def test_ccb_ping():
    """测试 ping 命令"""
    # 假设 backend-dev 在线
    assert ccb_ping("backend-dev") == True
    # 假设不存在的 worker
    assert ccb_ping("nonexistent-worker") == False

def test_ccb_ask():
    """测试 ask 命令"""
    result = ccb_ask("backend-dev", "Hello, are you there?")
    assert result == True

def test_ccb_pend():
    """测试 pend 命令"""
    response = ccb_pend("backend-dev", timeout=10)
    assert response is not None
```

**任务 6.2: 端到端测试**

创建测试任务并完整走一遍流程：

```bash
# 1. 启动 CCB
ccb

# 2. 创建测试任务
python scripts/assign_task.py --intake "测试 CCB 集成：创建一个简单的 Hello World API"

# 3. 分派任务
python scripts/assign_task.py --dispatch-ccb BACKEND-001 --ccb-worker backend-dev

# 4. 在另一个终端等待响应
pend backend-dev

# 5. 验证任务完成
python scripts/assign_task.py --list
```

**任务 6.3: 验证角色模板注入**

确认 worker 收到的消息包含完整的角色定义：

```bash
# 在 CCB 窗格中查看 backend-dev 收到的消息
# 应该包含:
# 1. 角色定义（来自 .claude/agents/backend.md）
# 2. 任务文档内容
# 3. 工作指令
```

---

## 迁移前后对比

| 功能 | 迁移前（自定义） | 迁移后（CCB） |
|------|----------------|--------------|
| 通信方式 | JSON 文件 | CCB ask/pend 命令 |
| 启动 workers | 直接启动 Codex | ccb 命令启动 |
| 可视化 | 无 | WezTerm 分割窗格 |
| 实时性 | 需要轮询文件 | 实时通信 |
| 角色注入 | JSON 文件中 | ask 命令参数中 |
| 状态检查 | 检查文件存在 | ping 命令 |
| 响应获取 | 读取 response.json | pend 命令 |

## 迁移风险和缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| CCB 安装失败 | 无法启动 | 提供详细安装文档，测试多个环境 |
| Worker 无法启动 | 任务无法执行 | 保留原有 JSON 方式作为后备 |
| 角色模板未注入 | Worker 不知道身份 | 在 ask 命令中明确包含角色定义 |
| 响应格式不兼容 | 无法解析结果 | 定义标准响应格式 |
| 性能问题 | 通信延迟 | 监控并优化 |

## 回滚计划

如果迁移失败，可以快速回滚：

1. 恢复原有的 `scripts/assign_task.py`（保留备份）
2. 恢复原有的 `scripts/ccb_start.ps1`
3. 继续使用 JSON 文件通信方式

备份命令：
```bash
cp scripts/assign_task.py scripts/assign_task.py.backup
cp scripts/ccb_start.ps1 scripts/ccb_start.ps1.backup
```

## 成功标准

迁移成功的标准：

- ✅ CCB 成功安装并可运行
- ✅ 所有 workers 可以通过 CCB 启动
- ✅ `ask` 命令可以发送任务
- ✅ `pend` 命令可以接收响应
- ✅ 角色模板正确注入到 worker
- ✅ 完整的任务流程可以走通
- ✅ 所有测试通过

## 时间估算

| 阶段 | 预计时间 |
|------|---------|
| 阶段 1: 完成 CCB 安装 | 30 分钟 |
| 阶段 2: 创建 CCB 配置 | 1 小时 |
| 阶段 3: 重构 assign_task.py | 3 小时 |
| 阶段 4: 重构启动脚本 | 1 小时 |
| 阶段 5: 更新文档 | 1 小时 |
| 阶段 6: 测试和验证 | 2 小时 |
| **总计** | **8-9 小时** |

## 执行建议

### 给 Codex 的指令

```
请按照 E:\moxton-ccb\CCB-MIGRATION-PLAN.md 中的迁移方案执行以下任务：

1. 阶段 1: 完成 CCB 安装
   - WezTerm 已安装在 D:\WezTerm-windows-20240203-110809-5046fc22
   - 将其添加到 PATH
   - 完成 CCB 安装
   - 验证 ccb 命令可用

2. 阶段 2: 创建 CCB 配置文件
   - 在 .ccb/ 目录创建配置
   - 创建各个 worker 的启动脚本

3. 阶段 3: 重构 scripts/assign_task.py
   - 添加 ccb_ask, ccb_pend, ccb_ping 函数
   - 重构 dispatch_ccb_task 函数
   - 修改 --dispatch-ccb 和 --poll-ccb 处理逻辑

4. 阶段 4-6: 按文档继续执行

请在每个阶段完成后报告进度和遇到的问题。
```

### 分阶段执行

建议分多次执行，每次完成一个阶段后验证：

1. 第一次：完成阶段 1-2（安装和配置）
2. 第二次：完成阶段 3（重构代码）
3. 第三次：完成阶段 4-5（脚本和文档）
4. 第四次：完成阶段 6（测试验证）

## 参考资料

- CCB GitHub: https://github.com/bfly123/claude_code_bridge
- CCB 中文文档: https://github.com/bfly123/claude_code_bridge/blob/main/README_zh.md
- WezTerm 文档: https://wezfurlong.org/wezterm/
- 当前项目文档: `E:\moxton-ccb\CLAUDE.md`
