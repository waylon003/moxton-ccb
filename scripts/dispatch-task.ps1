#!/usr/bin/env pwsh
# 派遣任务到 Worker（强制协议注入版）
# 用法: .\dispatch-task.ps1 -WorkerPaneId <id> -TaskId <id> -TaskContent <内容>

param(
    [Parameter(Mandatory=$true)]
    [string]$WorkerPaneId,

    [Parameter(Mandatory=$true)]
    [string]$TaskId,

    [Parameter(Mandatory=$true)]
    [string]$TaskContent,

    [Parameter(Mandatory=$false)]
    [string]$WorkerName = "unknown",

    [Parameter(Mandatory=$false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID
)

$ErrorActionPreference = "Stop"

# 验证环境
if (-not $TeamLeadPaneId) {
    Write-Error "TEAM_LEAD_PANE_ID 未设置。请先运行: `$env:TEAM_LEAD_PANE_ID = (wezterm cli list --format json | ConvertFrom-Json | Where-Object { `$_.title -like '*claude*' } | Select-Object -First 1).pane_id"
    exit 1
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
Write-Host "📤 派遣任务 $TaskId 到 Worker (pane_id=$WorkerPaneId)..."

# 发送任务内容
wezterm cli send-text --pane-id $WorkerPaneId --no-paste $fullTask

# 发送回车提交
Start-Sleep -Milliseconds 100
wezterm cli send-text --pane-id $WorkerPaneId --no-paste "`r"

Write-Host "✅ 任务已派遣"
Write-Host "   任务ID: $TaskId"
Write-Host "   Worker: $WorkerName"
Write-Host "   Worker Pane: $WorkerPaneId"
Write-Host "   Team Lead Pane: $TeamLeadPaneId"
