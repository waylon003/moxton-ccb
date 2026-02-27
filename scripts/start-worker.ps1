#!/usr/bin/env pwsh
# 启动 Worker（使用 Wrapper 强制回执）
# 用法: .\start-worker.ps1 -WorkDir "E:\moxton-lotapi" -WorkerName "backend-dev" -Engine codex

param(
    [Parameter(Mandatory=$true)]
    [string]$WorkDir,

    [Parameter(Mandatory=$true)]
    [string]$WorkerName,

    [Parameter(Mandatory=$false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID,

    [Parameter(Mandatory=$false)]
    [ValidateSet("codex", "gemini")]
    [string]$Engine = "codex",

    [Parameter(Mandatory=$false)]
    [int]$TimeoutSeconds = 3600
)

$ErrorActionPreference = "Stop"

# 验证 TeamLeadPaneId
if (-not $TeamLeadPaneId) {
    Write-Error "TEAM_LEAD_PANE_ID 未设置。请设置环境变量或在参数中指定。"
    Write-Host "示例: `$env:TEAM_LEAD_PANE_ID = (wezterm cli list --format json | ConvertFrom-Json | Where-Object { `$_.title -like '*claude*' } | Select-Object -First 1).pane_id"
    exit 1
}

# 获取 Wrapper 脚本路径
$wrapperScript = Join-Path $PSScriptRoot "worker-wrapper.ps1"

if (-not (Test-Path $wrapperScript)) {
    Write-Error "Worker wrapper 脚本未找到: $wrapperScript"
    exit 1
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "启动 Worker (强制回执模式)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Worker: $WorkerName"
Write-Host "Engine: $Engine"
Write-Host "WorkDir: $WorkDir"
Write-Host "Team Lead Pane: $TeamLeadPaneId"
Write-Host "Timeout: $TimeoutSeconds seconds"
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# 构建启动命令
$command = @"
& "$wrapperScript" -Engine $Engine -WorkDir "$WorkDir" -WorkerName "$WorkerName" -TeamLeadPaneId "$TeamLeadPaneId" -TimeoutSeconds $TimeoutSeconds
"@

Write-Host "🚀 启动 Worker: $WorkerName ..." -ForegroundColor Cyan

# 获取当前所有 pane（用于找到新创建的）
$panesBefore = wezterm cli list --format json | ConvertFrom-Json
$existingPaneIds = $panesBefore | ForEach-Object { $_.pane_id }

# 在新 WezTerm pane 中启动 Wrapper
$newPaneOutput = wezterm cli spawn --cwd "$PSScriptRoot" -- powershell -NoExit -Command $command 2>&1

# 等待 pane 创建
Start-Sleep -Seconds 2

# 获取新的 pane_id
$panesAfter = wezterm cli list --format json | ConvertFrom-Json
$newPane = $panesAfter | Where-Object { $_.pane_id -notin $existingPaneIds -and $_.title -like "*$WorkerName*" } | Select-Object -First 1

if (-not $newPane) {
    # 如果没找到匹配的 title，尝试找最新创建的
    $newPane = $panesAfter | Where-Object { $_.pane_id -notin $existingPaneIds } | Select-Object -Last 1
}

if ($newPane) {
    $paneId = $newPane.pane_id
    Write-Host "✅ Worker 已启动: $WorkerName -> pane $paneId" -ForegroundColor Green

    # 注册到 Worker Pane Registry
    $registryScript = Join-Path $PSScriptRoot "worker-registry.ps1"
    & $registryScript -Action register -WorkerName $WorkerName -PaneId $paneId -WorkDir $WorkDir -Engine $Engine

    Write-Host ""
    Write-Host "使用以下命令分派任务:" -ForegroundColor Yellow
    Write-Host "  .\scripts\dispatch-task.ps1 -WorkerName `"$WorkerName`" -TaskId `"<TASK-ID>`" -TaskContent `"<内容>`"" -ForegroundColor White
}
else {
    Write-Warning "无法获取新创建的 pane ID，请手动检查: wezterm cli list"
}
