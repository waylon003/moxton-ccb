#!/usr/bin/env pwsh
# 确保 Codex Worker 已启动（--full-auto + --add-dir CCB）
# 用法: .\ensure_codex_worker.ps1 -WorkDir "E:\moxton-lotapi" -Worker "backend-dev"

param(
    [Parameter(Mandatory=$true)]
    [string]$WorkDir,

    [Parameter(Mandatory=$true)]
    [string]$Worker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $PSCommandPath

Write-Host "=========================================="
Write-Host "🔍 检查 Codex Worker: $Worker"
Write-Host "=========================================="

# 1. 检查 worker 是否已经在运行
Write-Host ""
Write-Host "📝 检查连通性..."

$pingResult = & cping 2>&1
if ($pingResult -match "✅.*$Worker.*OK") {
    Write-Host "✅ Worker '$Worker' 已在运行"
    exit 0
}

Write-Host "⚠️  Worker '$Worker' 未运行，准备启动..."

# 2. 查找可用的 WezTerm pane
Write-Host ""
Write-Host "📝 查找可用的 WezTerm pane..."

$panes = wezterm cli list --format json 2>$null | ConvertFrom-Json
$availablePane = $null

foreach ($pane in $panes) {
    # 查找空闲的 pane（没有运行 codex 的）
    $paneText = wezterm cli get-text --pane-id $pane.pane_id 2>$null
    if ($paneText -notmatch "codex>" -and $paneText -notmatch "CCB.*Session") {
        $availablePane = $pane.pane_id
        break
    }
}

if (-not $availablePane) {
    Write-Host "📝 创建新的 pane..."
    $newPaneId = wezterm cli split-pane --right 2>&1
    if ($LASTEXITCODE -eq 0) {
        $availablePane = $newPaneId
    } else {
        Write-Error "无法创建新 pane"
        exit 1
    }
}

Write-Host "✅ 使用 pane: $availablePane"

# 3. 在 pane 中启动 Codex（使用 start-codex.ps1）
Write-Host ""
Write-Host "📝 在 pane 中启动 Codex..."

$startScript = "E:\moxton-ccb\scripts\start-codex.ps1"
$command = "powershell -ExecutionPolicy Bypass -File `"$startScript`" `"$WorkDir`""

wezterm cli send-text --pane-id $availablePane --no-paste "$command`r"

# 4. 等待 Codex 启动
Write-Host "⏳ 等待 Codex 启动（最多 30 秒）..."
$maxWait = 30
$waited = 0

while ($waited -lt $maxWait) {
    Start-Sleep -Seconds 2
    $waited += 2

    $pingResult = & cping 2>&1
    if ($pingResult -match "✅.*$Worker.*OK") {
        Write-Host ""
        Write-Host "=========================================="
        Write-Host "✅ Worker '$Worker' 已成功启动"
        Write-Host "=========================================="
        exit 0
    }
}

Write-Host ""
Write-Host "=========================================="
Write-Host "⚠️  Worker '$Worker' 启动超时"
Write-Host "=========================================="
Write-Host "请手动检查 pane $availablePane"
exit 1
