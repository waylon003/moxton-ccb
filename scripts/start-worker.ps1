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

# 在新 WezTerm pane 中启动 Wrapper
wezterm cli spawn --cwd "$PSScriptRoot" -- powershell -NoExit -Command $command
