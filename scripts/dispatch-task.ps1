#!/usr/bin/env pwsh
# 派遣任务到 Worker（支持 Worker Pane Registry）
# 用法:
#   方式1: 通过 WorkerName 自动查表
#     .\dispatch-task.ps1 -WorkerName "backend-dev" -TaskId "BACKEND-008" -TaskContent "内容"
#   方式2: 直接指定 Pane ID（旧方式）
#     .\dispatch-task.ps1 -WorkerPaneId 42 -WorkerName "backend-dev" -TaskId "BACKEND-008" -TaskContent "内容"

param(
    [Parameter(Mandatory=$false)]
    [string]$WorkerPaneId,

    [Parameter(Mandatory=$true)]
    [string]$TaskId,

    [Parameter(Mandatory=$true)]
    [string]$TaskContent,

    [Parameter(Mandatory=$false)]
    [string]$WorkerName,

    [Parameter(Mandatory=$false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID
)

$ErrorActionPreference = "Stop"

# 验证环境
if (-not $TeamLeadPaneId) {
    Write-Error "TEAM_LEAD_PANE_ID 未设置。请先运行: `$env:TEAM_LEAD_PANE_ID = (wezterm cli list --format json | ConvertFrom-Json | Where-Object { `$_.title -like '*claude*' } | Select-Object -First 1).pane_id"
    exit 1
}

# 如果没有直接提供 PaneId，尝试从 Registry 获取
if (-not $WorkerPaneId) {
    if (-not $WorkerName) {
        Write-Error "必须提供 -WorkerPaneId 或 -WorkerName。`n用法: .\dispatch-task.ps1 -WorkerName 'backend-dev' -TaskId 'xxx' -TaskContent 'xxx'"
        exit 1
    }

    Write-Host "🔍 从 Worker Pane Registry 查找 $WorkerName ..." -ForegroundColor Cyan

    $registryScript = Join-Path $PSScriptRoot "worker-registry.ps1"
    $foundPaneId = & $registryScript -Action get -WorkerName $WorkerName 2>&1

    if (-not $foundPaneId) {
        Write-Error "Worker '$WorkerName' 未在 Registry 中找到。请先启动 Worker:`n  .\scripts\start-worker.ps1 -WorkDir '...' -WorkerName '$WorkerName' -Engine codex"
        exit 1
    }

    $WorkerPaneId = $foundPaneId
    Write-Host "✅ 找到 Worker: $WorkerName -> pane $WorkerPaneId" -ForegroundColor Green
}
else {
    # 直接提供了 PaneId，如果也提供了 WorkerName，用于显示
    if (-not $WorkerName) {
        $WorkerName = "unknown"
    }
}

# 构建强制协议头
$protocolHeader = @"
═══════════════════════════════════════════════════════════════════
⚠️  强制协议提醒 ⚠️
═══════════════════════════════════════════════════════════════════

你在接受任务前必须确认：

1. 任务完成后，必须使用 wezterm cli 通知 Team Lead
2. 通知格式必须是 [ROUTE] ... [/ROUTE]
3. 禁止不通知就声明完成！

当前任务ID: $TaskId
Team Lead Pane ID: $TeamLeadPaneId
Worker: $WorkerName

═══════════════════════════════════════════════════════════════════

"@

# 构建完整任务内容
$fullTask = $protocolHeader + $TaskContent + "`n`n" + @"
═══════════════════════════════════════════════════════════════════
⚠️  完成提醒 ⚠️
═══════════════════════════════════════════════════════════════════

任务完成后，执行以下命令通知 Team Lead：

```powershell
wezterm cli send-text --pane-id "$TeamLeadPaneId" --no-paste @'
[ROUTE]
from: $WorkerName
to: team-lead
type: status
task: $TaskId
status: success
body: |
  <填写：修改的文件、执行的命令、测试结果>
[/ROUTE]
'@
wezterm cli send-text --pane-id "$TeamLeadPaneId" --no-paste "`r"
```

═══════════════════════════════════════════════════════════════════
"@

# 发送到 Worker
Write-Host ""
Write-Host "📤 派遣任务 $TaskId 到 Worker..."
Write-Host "   Worker: $WorkerName"
Write-Host "   Worker Pane: $WorkerPaneId"
Write-Host ""

# 发送任务内容
wezterm cli send-text --pane-id $WorkerPaneId --no-paste $fullTask

# 发送回车提交
Start-Sleep -Milliseconds 100
wezterm cli send-text --pane-id $WorkerPaneId --no-paste "`r"

Write-Host "Task dispatched." -ForegroundColor Green
