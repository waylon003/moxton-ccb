# Team Lead 启动检查清单

**每次在 E:\moxton-ccb 启动新的 Claude Code 会话时，必须执行以下步骤：**

---

## 1. 环境变量设置

```bash
export CCB_CALLER=claude
export PATH="$PATH:/d/WezTerm-windows-20240203-110809-5046fc22"
```

**验证**：
```bash
echo $CCB_CALLER  # 应该输出: claude
wezterm --version  # 应该显示版本信息
ccb --version      # 应该显示 CCB 版本
```

---

## 2. 确认角色定位

**你是 Team Lead**，职责：
- ✅ 需求分析、任务拆分、路由协调
- ✅ 维护任务文档和任务锁
- ✅ 通过 CCB 分派任务给 Codex workers
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

## 5. CCB 工作流程

### 启动 Codex Workers（如需要）

**推荐方式：使用启动脚本（--full-auto + --add-dir CCB）**

```powershell
# 在对应的工作目录启动 Codex
powershell -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\start-codex.ps1" "E:\moxton-lotapi"
powershell -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\start-codex.ps1" "E:\nuxt-moxton"
powershell -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\start-codex.ps1" "E:\moxton-lotadmin"
```

**方法 1：自动分屏**（在 PowerShell 中）：
```powershell
cd E:\moxton-lotapi
ccb codex
```

**方法 2：手动创建 pane**（在 Git Bash 中）：
```bash
# 创建新 pane
wezterm cli split-pane --right

# 在新 pane 中启动 Codex
cd E:\moxton-lotapi
python C:\Users\26249\AppData\Local\codex-dual\ccb codex --full-auto --add-dir "E:\moxton-ccb"
```

### 分派任务

```bash
# 在对应仓库目录下
cd E:\moxton-lotapi
CCB_CALLER=claude ask codex "$(cat .ccb/dispatch-TASK-ID.md)"
```

### 自动通知

设置 `CCB_CALLER=claude` 后，Codex 完成任务会自动通知你，**无需手动轮询 `pend`**。

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
