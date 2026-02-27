# CCB 安装指南（Windows）

## 当前状态

- ✅ CCB 仓库已克隆到 `/tmp/claude_code_bridge`
- ✅ Python 3.10.11 已安装
- ✅ watchdog 依赖已安装
- ❌ 缺少终端复用器（WezTerm 或 tmux）

## 安装选项

### 选项 1: 安装 WezTerm（推荐）

WezTerm 是 CCB 推荐的终端，支持原生 Windows。

**下载地址**: https://wezfurlong.org/wezterm/

**安装步骤**:
1. 访问 https://github.com/wez/wezterm/releases/latest
2. 下载 `WezTerm-windows-*.zip`
3. 解压并运行安装程序
4. 重新运行 CCB 安装

**安装 CCB**:
```bash
cd /tmp/claude_code_bridge
bash ./install.sh install
```

### 选项 2: 使用 WSL（推荐用于开发）

如果你有 WSL，可以在 WSL 中安装 CCB 和 tmux。

**在 WSL 中**:
```bash
# 安装 tmux
sudo apt-get update
sudo apt-get install -y tmux

# 克隆并安装 CCB
cd ~
git clone https://github.com/bfly123/claude_code_bridge.git
cd claude_code_bridge
./install.sh install
```

### 选项 3: 安装 MSYS2 + tmux

如果你想在当前 Git Bash 环境使用 tmux：

1. 下载 MSYS2: https://www.msys2.org/
2. 安装后，在 MSYS2 终端运行:
   ```bash
   pacman -S tmux
   ```
3. 将 MSYS2 的 bin 目录添加到 PATH
4. 重新运行 CCB 安装

## CCB 安装后配置

### 1. 创建配置文件

在项目根目录创建 `.ccb/ccb.config`:

```bash
mkdir -p E:/moxton-ccb/.ccb
```

**配置内容** (`.ccb/ccb.config`):
```
codex
```

或者如果需要多个 AI:
```
codex,claude
```

### 2. 验证安装

```bash
ccb -v
```

应该显示版本号（如 v5.2.6）

### 3. 测试 CCB

```bash
# 启动单个 Codex 会话
ccb codex

# 启动多个 AI 会话
ccb codex claude
```

## 集成到 Moxton-CCB 项目

### 当前项目使用情况分析

查看 `scripts/assign_task.py` 和 `scripts/ccb_start.ps1`，发现：

**问题 1**: 项目中提到 "CCB ask/pend/ping"，但这些是 CCB 工具的命令，不是自定义脚本。

**问题 2**: `ccb_start.ps1` 直接启动 Codex，没有使用 CCB 工具。

**当前启动方式**:
```powershell
codex --cd E:\nuxt-moxton --sandbox workspace-write
```

**应该改为使用 CCB**:
```bash
ccb codex
```

### 修改建议

#### 1. 更新 `scripts/ccb_start.ps1`

将直接启动 Codex 改为使用 CCB：

```powershell
# 旧方式（不使用 CCB）
Start-Process wt.exe -ArgumentList "new-tab --title \"shop-fe-dev\" powershell -NoExit -Command \"codex --cd E:\nuxt-moxton\""

# 新方式（使用 CCB）
Start-Process wt.exe -ArgumentList "new-tab --title \"shop-fe-dev\" powershell -NoExit -Command \"cd E:\moxton-ccb; ccb codex\""
```

#### 2. 使用 CCB 的 ask/pend/ping 命令

CCB 提供了进程间通信命令：

**ask**: 向运行中的 AI 发送问题
```bash
ask codex "请实现 BACKEND-001 任务"
```

**pend**: 等待 AI 响应
```bash
pend codex
```

**ping**: 检查 AI 是否在线
```bash
ping codex
```

#### 3. 修改 `write_ccb_request()` 使用 CCB 命令

当前 `write_ccb_request()` 只是写入 JSON 文件，应该改为使用 CCB 的 `ask` 命令：

```python
def dispatch_to_ccb(task: TaskInfo, worker: str):
    # 构建提示词
    prompt = f"""
你的角色定义：
{role_prompt_content}

任务文档：{task.task_path}
工作目录：{task.workdir}

请阅读任务文档并开始实现。
"""

    # 使用 CCB ask 命令发送给 Codex
    subprocess.run(['ask', worker, prompt])
```

## 下一步行动

### 立即行动

1. **安装 WezTerm**（最简单）
   - 下载: https://github.com/wez/wezterm/releases/latest
   - 安装后重新运行: `cd /tmp/claude_code_bridge && bash ./install.sh install`

2. **验证安装**
   ```bash
   ccb -v
   ```

3. **测试 CCB**
   ```bash
   cd E:/moxton-ccb
   ccb codex
   ```

### 后续集成

1. 阅读 CCB 文档了解 ask/pend/ping 命令
2. 修改 `scripts/ccb_start.ps1` 使用 CCB 启动
3. 修改 `scripts/assign_task.py` 使用 CCB 命令而不是 JSON 文件
4. 测试完整的 Team Lead → CCB → Codex 工作流

## 参考文档

- CCB GitHub: https://github.com/bfly123/claude_code_bridge
- CCB 中文文档: https://github.com/bfly123/claude_code_bridge/blob/main/README_zh.md
- WezTerm 官网: https://wezfurlong.org/wezterm/

## 当前项目与 CCB 的差异

| 当前实现 | CCB 标准方式 |
|---------|-------------|
| 写入 JSON 文件到 `05-verification/ccb-runs/` | 使用 `ask` 命令直接通信 |
| 手动轮询 JSON 文件 | 使用 `pend` 命令等待响应 |
| 直接启动 Codex | 使用 `ccb codex` 启动 |
| 自定义通信协议 | 使用 CCB 内置通信机制 |

需要重构项目以正确使用 CCB 工具。
