#!/usr/bin/env pwsh
# 派遣任务到 Worker（支持 Worker Pane Registry）
# Worker 通过文件路径自行读取任务内容，避免 send-text 超长截断
# 用法:
#   .\dispatch-task.ps1 -WorkerPaneId 42 -WorkerName "backend-dev" -TaskId "BACKEND-008" -TaskFilePath "E:\moxton-ccb\01-tasks\active\backend\BACKEND-008-xxx.md"

param(
    [Parameter(Mandatory=$false)]
    [string]$WorkerPaneId,

    [Parameter(Mandatory=$true)]
    [string]$TaskId,

    [Parameter(Mandatory=$true)]
    [string]$TaskFilePath,

    [Parameter(Mandatory=$false)]
    [string]$WorkerName,

    [Parameter(Mandatory=$false)]
    [ValidateSet("codex", "gemini")]
    [string]$Engine = "codex",

    [Parameter(Mandatory=$false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 验证环境
if (-not $TeamLeadPaneId) {
    Write-Error "TEAM_LEAD_PANE_ID 未设置。请先运行: `$env:TEAM_LEAD_PANE_ID = (wezterm cli list --format json | ConvertFrom-Json | Where-Object { `$_.title -like '*claude*' } | Select-Object -First 1).pane_id"
    exit 1
}

# 如果没有直接提供 PaneId，尝试从 Registry 获取
if (-not $WorkerPaneId) {
    if (-not $WorkerName) {
        Write-Error "必须提供 -WorkerPaneId 或 -WorkerName。`n用法: .\dispatch-task.ps1 -WorkerName 'backend-dev' -TaskId 'xxx' -TaskFilePath 'path/to/task.md'"
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

# 验证任务文件存在
if (-not (Test-Path $TaskFilePath)) {
    Write-Error "任务文件不存在: $TaskFilePath"
    exit 1
}

# 构建派遣指令（短内容：协议头 + 文件路径引用 + 完成提醒）
$fullTask = @"
===================================================================
  PROTOCOL REMINDER
===================================================================

你在接受任务前必须确认：

1. 任务完成后，必须使用 wezterm cli 通知 Team Lead
2. 通知格式必须是 [ROUTE] ... [/ROUTE]
3. 禁止不通知就声明完成！

当前任务ID: $TaskId
Team Lead Pane ID: $TeamLeadPaneId
Worker: $WorkerName

===================================================================
  TASK CONTENT
===================================================================

请读取以下文件获取完整任务内容，严格按照文件中的要求执行：

$TaskFilePath

===================================================================
  COMPLETION REMINDER
===================================================================

任务完成后，执行以下命令通知 Team Lead：

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

===================================================================
"@

# 发送到 Worker
Write-Host ""
Write-Host "派遣任务 $TaskId 到 Worker..."
Write-Host "   Worker: $WorkerName"
Write-Host "   Worker Pane: $WorkerPaneId"
Write-Host "   Engine: $Engine"
Write-Host "   Task file: $TaskFilePath"
Write-Host ""

# 等待 Worker CLI 就绪（避免 CLI 未加载完就发送导致内容丢失）
$readyPatterns = if ($Engine -eq "gemini") {
    @("Type your message", "? for shortcuts")
} else {
    @("codex>", "Codex is ready", "full-auto", "OpenAI Codex")
}

$maxWait = 60
$waited = 0
$ready = $false

Write-Host "Waiting for $Engine CLI to be ready..." -ForegroundColor Yellow
while ($waited -lt $maxWait) {
    try {
        $paneText = wezterm cli get-text --pane-id $WorkerPaneId 2>$null
        foreach ($pattern in $readyPatterns) {
            if ($paneText -match [regex]::Escape($pattern)) {
                Write-Host ('[OK] Worker CLI ready (matched: ' + $pattern + ')') -ForegroundColor Green
                $ready = $true
                break
            }
        }
    } catch {}
    if ($ready) { break }
    Start-Sleep -Seconds 2
    $waited += 2
    if ($waited % 10 -eq 0) {
        $lastLines = if ($paneText) { ($paneText -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 3) -join " | " } else { "(empty)" }
        Write-Host ('  ... still waiting (' + $waited + 's) pane text: ' + $lastLines) -ForegroundColor DarkGray
    }
}

if (-not $ready) {
    Write-Host ('[FAIL] Worker CLI not ready after ' + $maxWait + 's, aborting dispatch') -ForegroundColor Red
    exit 1
}

# 发送任务指令 + 回车（合并为一次 send-text，避免时序问题）
wezterm cli send-text --pane-id $WorkerPaneId --no-paste "$fullTask`r`n"
if ($LASTEXITCODE -ne 0) {
    Write-Host '[FAIL] wezterm send-text failed' -ForegroundColor Red
    exit 1
}

Write-Host "Task dispatched." -ForegroundColor Green
