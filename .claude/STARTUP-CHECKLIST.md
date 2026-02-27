# Team Lead 启动检查清单

**每次在 E:\moxton-ccb 启动新的 Claude Code 会话时，必须执行以下步骤：**

---

## 1. 环境变量设置

```powershell
# 设置 WezTerm 路径
$env:PATH += ";D:\WezTerm-windows-20240203-110809-5046fc22"

# 获取 Team Lead 自己的 pane_id
$env:TEAM_LEAD_PANE_ID = (wezterm cli list --format json | ConvertFrom-Json | Where-Object { $_.title -like '*claude*' } | Select-Object -First 1).pane_id
Write-Host "Team Lead Pane ID: $env:TEAM_LEAD_PANE_ID"
```

**验证**：
```powershell
wezterm --version  # 应该显示版本信息
$env:TEAM_LEAD_PANE_ID  # 应该显示 pane ID
```

---

## 2. 确认角色定位

**你是 Team Lead**，职责：
- ✅ 需求分析、任务拆分、路由协调
- ✅ 维护任务文档和任务锁
- ✅ 通过 WezTerm 分派任务给 Workers
- ✅ 汇总 QA 证据并向用户报告

**你不是**：
- ❌ 代码实现者（不直接修改业务仓库代码）
- ❌ 任务执行者（不绕过 Codex workers）

---

## 3. 读取关键文档

**必读**：
1. `E:\moxton-ccb\CLAUDE.md` - Team Lead 工作流程
2. `E:\moxton-ccb\01-tasks\ACTIVE-RUNNER.md` - 当前活跃任务
3. `E:\moxton-ccb\.claude\agents\` - 各角色定义

**快速命令**：
```bash
python scripts/assign_task.py --standard-entry
```

---

## 4. 检查任务状态

```bash
# 查看所有任务
python scripts/assign_task.py --list

# 查看任务锁
python scripts/assign_task.py --show-task-locks

# 扫描 active 任务
python scripts/assign_task.py --scan
```

---

## 5. WezTerm 工作流程

### 启动 Workers（自动注册到 Registry）

```powershell
# 启动后端 Worker (Codex)
.\scripts\start-worker.ps1 -WorkDir "E:\moxton-lotapi" -WorkerName "backend-dev" -Engine codex -TeamLeadPaneId $env:TEAM_LEAD_PANE_ID

# 启动前端 Worker (Gemini)
.\scripts\start-worker.ps1 -WorkDir "E:\nuxt-moxton" -WorkerName "shop-fe-dev" -Engine gemini -TeamLeadPaneId $env:TEAM_LEAD_PANE_ID

# 启动管理后台 Worker (Codex)
.\scripts\start-worker.ps1 -WorkDir "E:\moxton-lotadmin" -WorkerName "admin-fe-dev" -Engine codex -TeamLeadPaneId $env:TEAM_LEAD_PANE_ID
```

Worker 启动后会自动注册到 `config/worker-panels.json`，无需手动记录 pane ID。

### 分派任务（通过 WorkerName 自动查表）

```powershell
# 方式1: 通过 WorkerName 自动查表（推荐）
.\scripts\dispatch-task.ps1 `
  -WorkerName "backend-dev" `
  -TaskId "BACKEND-008" `
  -TaskContent (Get-Content "01-tasks\active\backend\BACKEND-008.md" -Raw)

# 方式2: 直接指定 Pane ID（备用）
.\scripts\dispatch-task.ps1 `
  -WorkerPaneId <worker-pane-id> `
  -WorkerName "backend-dev" `
  -TaskId "BACKEND-008" `
  -TaskContent (Get-Content "01-tasks\active\backend\BACKEND-008.md" -Raw)
```

### 等待 Worker 回调

Worker 完成后会自动推送 `[ROUTE]` 消息到 Team Lead，无需手动轮询。
```

### 自动通知

Worker 通过 wrapper 脚本启动，**无论任务成功、失败或超时**，都会强制发送 `[ROUTE]` 通知到 Team Lead。

---

## 6. 关键路径速查

| 路径 | 用途 |
|------|------|
| `01-tasks/active/` | 活跃任务文档 |
| `01-tasks/TASK-LOCKS.json` | 任务锁状态 |
| `01-tasks/ACTIVE-RUNNER.md` | 当前执行者 |
| `.claude/agents/` | 角色定义 |
| `config/ccb-routing.json` | CCB 路由配置 |
| `05-verification/ccb-runs/` | QA 验收报告 |

---

## 7. 常见问题

### Q: 如何知道当前有哪些任务？
```bash
python scripts/assign_task.py --list
```

### Q: 如何分派任务给 Codex？
```bash
cd <对应仓库>
CCB_CALLER=claude ask codex "任务内容"
```

### Q: 如何检查 Codex 是否完成？
**不需要手动检查**，设置 `CCB_CALLER=claude` 后会自动通知。

### Q: 如何更新任务状态？
```bash
python scripts/assign_task.py --lock-task TASK-ID --task-state <状态> --lock-note "备注"
```

---

## 8. 启动后第一件事

运行标准入口点：
```bash
python scripts/assign_task.py --standard-entry
```

这会自动：
- 检测是否有 active 任务
- 进入执行模式或规划模式
- 显示下一步操作建议

---

## 9. 记住

- **你是协调者，不是执行者**
- **所有代码修改都通过 Codex workers**
- **所有任务都要经过 QA 验证**
- **CCB_CALLER=claude 启用自动通知**

---

**最后检查**：
```bash
# 确认环境
echo "CCB_CALLER: $CCB_CALLER"
echo "当前目录: $(pwd)"
echo "WezTerm: $(wezterm --version 2>&1 | head -1)"
echo "CCB: $(ccb --version 2>&1 | head -1)"

# 确认角色
echo "我是 Team Lead，负责协调而非执行"
```
