#!/usr/bin/env pwsh
# Doc-Updater 自动触发器
# 在检测到 Backend API 变更完成后自动更新文档

param(
    [Parameter(Mandatory=$true)]
    [string]$TaskId,

    [Parameter(Mandatory=$false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID
)

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
$rootDir = Split-Path $scriptDir -Parent

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "      Doc-Updater 自动触发检查" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "任务: $TaskId" -ForegroundColor White
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# 1. 检查任务是否涉及 API 变更
$taskFile = Get-ChildItem -Path "$rootDir\01-tasks\active\*\$TaskId*.md" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $taskFile) {
    Write-Host "⚠️ 任务文件未找到，跳过 Doc-Updater 检查" -ForegroundColor Yellow
    exit 0
}

$taskContent = Get-Content $taskFile.FullName -Raw

# 检查是否涉及 API 变更的标志
$apiKeywords = @('API', '接口', 'endpoint', 'controller', 'route', 'REST', 'GraphQL')
$involvesApi = $false

foreach ($kw in $apiKeywords) {
    if ($taskContent -match $kw) {
        $involvesApi = $true
        Write-Host "检测到 API 相关关键词: $kw" -ForegroundColor Gray
    }
}

# 检查任务标题或描述
if ($taskContent -match 'api|接口|endpoint' -or $TaskId -match 'BACKEND') {
    $involvesApi = $true
}

if (-not $involvesApi) {
    Write-Host "✅ 任务不涉及 API 变更，无需更新文档" -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "📝 任务涉及 API 变更，需要更新文档" -ForegroundColor Yellow
Write-Host ""

# 2. 检查后端仓库是否有 API 变更
$backendDir = "$rootDir\..\moxton-lotapi"
if (-not (Test-Path $backendDir)) {
    $backendDir = "E:\moxton-lotapi"  # 回退到绝对路径
}

if (Test-Path $backendDir) {
    Write-Host "检查后端仓库变更..." -ForegroundColor Cyan

    # 检查最近的变更文件（通过 git 或其他方式）
    Set-Location $backendDir

    # 查找最近修改的 API 相关文件
    $apiFiles = Get-ChildItem -Path "$backendDir\src\routes\*" -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        $_.LastWriteTime -gt (Get-Date).AddHours(-1)  # 最近1小时修改
    }

    if ($apiFiles) {
        Write-Host "发现 $($apiFiles.Count) 个最近修改的 API 文件:" -ForegroundColor Yellow
        $apiFiles | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
    }
}

# 3. 触发 Doc-Updater
Write-Host ""
Write-Host "准备触发 Doc-Updater..." -ForegroundColor Green
Write-Host ""

# 构建 doc-updater 任务内容
$docUpdateContent = @"
## Doc-Updater 任务

触发原因: 任务 $TaskId 涉及 API 变更，需要同步更新文档。

### 需要执行的操作

1. 检查后端 API 变更
   - 查看最近修改的路由文件
   - 确认新增/修改的接口

2. 更新 02-api/ 文档
   - 如果是新接口：创建新的 API 文档
   - 如果是修改：更新现有文档
   - 确保文档与代码一致

3. 验证文档完整性
   - 检查参数列表
   - 检查响应示例
   - 检查错误码

### 参考

任务文件: $taskFile
后端目录: $backendDir

开始执行文档更新。
"@

# 查找 doc-updater worker
$registryScript = "$scriptDir\worker-registry.ps1"
$docUpdaterPane = & $registryScript -Action get -WorkerName "doc-updater" 2>$null

if (-not $docUpdaterPane) {
    Write-Host "⚠️  doc-updater worker 未启动" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "建议操作:" -ForegroundColor Cyan
    Write-Host "1. 启动 doc-updater worker:" -ForegroundColor White
    Write-Host "   .\scripts\start-worker.ps1 -WorkDir 'E:\moxton-ccb' -WorkerName 'doc-updater' -Engine codex" -ForegroundColor White
    Write-Host ""
    Write-Host "2. 然后手动分派文档更新任务" -ForegroundColor White
    Write-Host ""

    # 记录待处理的文档更新
    $pendingDocUpdate = @{
        taskId = $TaskId
        triggeredAt = Get-Date -Format "o"
        status = "pending"
        reason = "doc-updater worker not available"
    }

    $pendingFile = "$rootDir\config\pending-doc-updates.json"
    $pendingUpdates = @()
    if (Test-Path $pendingFile) {
        $existing = Get-Content $pendingFile -Raw | ConvertFrom-Json
        if ($existing) { $pendingUpdates = @($existing) }
    }
    $pendingUpdates += $pendingDocUpdate
    ConvertTo-Json $pendingUpdates -Depth 10 | Set-Content $pendingFile -Encoding UTF8

    Write-Host "已记录到待处理队列: config\pending-doc-updates.json" -ForegroundColor Gray
    exit 0
}

# 分派 doc-updater 任务
Write-Host "发送文档更新任务到 doc-updater (pane $docUpdaterPane)..." -ForegroundColor Green

& "$scriptDir\dispatch-task.ps1" `
    -WorkerPaneId $docUpdaterPane `
    -WorkerName "doc-updater" `
    -TaskId "DOC-UPDATE-$TaskId" `
    -TaskContent $docUpdateContent `
    -TeamLeadPaneId $TeamLeadPaneId

Write-Host ""
Write-Host "✅ Doc-Updater 任务已分派" -ForegroundColor Green
Write-Host ""

# 记录触发历史
$triggerRecord = @{
    taskId = $TaskId
    triggeredAt = Get-Date -Format "o"
    docUpdaterPane = $docUpdaterPane
    status = "dispatched"
}

$historyFile = "$rootDir\config\doc-update-history.json"
$history = @()
if (Test-Path $historyFile) {
    $existing = Get-Content $historyFile -Raw | ConvertFrom-Json
    if ($existing) { $history = @($existing) }
}
$history += $triggerRecord
ConvertTo-Json $history -Depth 10 | Set-Content $historyFile -Encoding UTF8

exit 0
