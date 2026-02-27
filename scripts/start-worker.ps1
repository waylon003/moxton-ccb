#!/usr/bin/env pwsh
# 启动 Worker 并注入强制通信协议
# 用法: .\start-worker.ps1 -WorkDir "E:\moxton-lotapi" -WorkerName "backend-dev" -TeamLeadPaneId "5"

param(
    [Parameter(Mandatory=$true)]
    [string]$WorkDir,

    [Parameter(Mandatory=$true)]
    [string]$WorkerName,

    [Parameter(Mandatory=$true)]
    [string]$TeamLeadPaneId,

    [Parameter(Mandatory=$false)]
    [ValidateSet("codex", "gemini")]
    [string]$Engine = "codex"
)

$ErrorActionPreference = "Stop"

# 1. 生成强制指令
$instructions = & "$PSScriptRoot\worker-instructions.ps1" `
    -WorkerName $WorkerName `
    -WorkDir $WorkDir `
    -TeamLeadPaneId $TeamLeadPaneId `
    -Engine $Engine

# 2. 保存指令到临时文件
$tempFile = "$env:TEMP\$WorkerName-instructions-$(Get-Random).md"
$instructions | Set-Content -Path $tempFile -Encoding UTF8
Write-Host "Instructions saved to: $tempFile"

# 3. 设置环境变量
$env:TEAM_LEAD_PANE_ID = $TeamLeadPaneId
$env:WORKER_NAME = $WorkerName
$env:WORK_DIR = $WorkDir

# 4. 启动 Worker
Write-Host ""
Write-Host "=========================================="
Write-Host "Starting $Engine Worker: $WorkerName"
Write-Host "WorkDir: $WorkDir"
Write-Host "Team Lead Pane: $TeamLeadPaneId"
Write-Host "=========================================="

if ($Engine -eq "codex") {
    # Codex: 使用 --prompt 注入指令
    $env:CURRENT_INSTRUCTIONS = $tempFile

    # 切换到工作目录启动
    Set-Location $WorkDir

    # 启动 Codex（指令已通过环境变量和 prompt 注入）
    # 用户会看到强制协议，必须遵守
    codex --prompt $instructions

} else {
    # Gemini: 直接注入到环境变量
    $env:GEMINI_INSTRUCTIONS = $instructions

    Set-Location $WorkDir

    # Gemini CLI 会读取环境变量中的指令
    gemini
}
