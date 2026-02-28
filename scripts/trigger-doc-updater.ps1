#!/usr/bin/env pwsh
# Doc-Updater 自动触发器
# 支持两种触发：
# 1) backend_qa：后端 QA 成功后实时触发
# 2) round_complete：当前无活跃任务时兜底触发

param(
    [Parameter(Mandatory = $true)]
    [string]$TaskId,

    [Parameter(Mandatory = $false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID,

    [Parameter(Mandatory = $false)]
    [ValidateSet("backend_qa", "round_complete", "manual")]
    [string]$Reason = "backend_qa",

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot
$rootDir = Split-Path $scriptDir -Parent

function Write-Utf8NoBomFile([string]$path, [string]$content) {
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

function Read-Json([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    try {
        return (Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Resolve-TaskFile([string]$id) {
    $candidates = @(
        "$rootDir\01-tasks\active\*\$id*.md",
        "$rootDir\01-tasks\completed\*\$id*.md"
    )
    foreach ($pattern in $candidates) {
        $file = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($file) { return $file }
    }
    return $null
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "      Doc-Updater 自动触发检查" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "任务: $TaskId" -ForegroundColor White
Write-Host "触发原因: $Reason" -ForegroundColor White
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

$taskFile = Resolve-TaskFile -id $TaskId
$taskContent = ""
if ($taskFile) {
    $taskContent = Get-Content -Path $taskFile.FullName -Raw -Encoding UTF8
}

$requiresDocUpdate = $Force.IsPresent -or ($Reason -eq "round_complete")
if (-not $requiresDocUpdate) {
    $apiKeywords = @('API', '接口', 'endpoint', 'controller', 'route', 'REST', 'GraphQL')
    foreach ($kw in $apiKeywords) {
        if ($taskContent -match [regex]::Escape($kw)) {
            $requiresDocUpdate = $true
            break
        }
    }
    if ($TaskId -match '^BACKEND-') { $requiresDocUpdate = $true }
}

if (-not $requiresDocUpdate) {
    Write-Host "✅ 任务不涉及 API/文档变更，无需触发 doc-updater" -ForegroundColor Green
    exit 0
}

Write-Host "📝 需要触发 doc-updater" -ForegroundColor Yellow

# 检查后端变更（仅 backend_qa 场景，失败不阻断）
if ($Reason -eq "backend_qa") {
    $backendDir = if (Test-Path "$rootDir\..\moxton-lotapi") { "$rootDir\..\moxton-lotapi" } else { "E:\moxton-lotapi" }
    if (Test-Path $backendDir) {
        try {
            $recentApiFiles = Get-ChildItem -Path "$backendDir\src\routes\*" -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                $_.LastWriteTime -gt (Get-Date).AddHours(-2)
            }
            if ($recentApiFiles.Count -gt 0) {
                Write-Host ("检测到最近变更的 API 文件: " + $recentApiFiles.Count) -ForegroundColor Gray
            }
        } catch {}
    }
}

# 生成 doc-updater 任务文件，走统一 dispatch-task 协议
$safeTaskToken = ($TaskId -replace '[^A-Za-z0-9\-]', '-')
$docTaskId = if ($Reason -eq "round_complete") {
    "DOC-UPDATE-ROUND-" + (Get-Date -Format "yyyyMMdd-HHmmss")
} else {
    "DOC-UPDATE-$safeTaskToken"
}
$docTaskDir = Join-Path $rootDir "01-tasks\active\doc-updater"
$docTaskFile = Join-Path $docTaskDir "$docTaskId.md"
$taskFileRef = if ($taskFile) { $taskFile.FullName } else { "(task file not found)" }

$reasonText = switch ($Reason) {
    "backend_qa" { "后端 QA 成功后实时同步 API 文档" }
    "round_complete" { "当前无活跃任务，执行全量文档一致性兜底检查" }
    default { "手动触发文档同步" }
}

$docContent = @"
# $docTaskId

## 触发信息
- 原任务: $TaskId
- 触发原因: $reasonText
- 参考任务文件: $taskFileRef

## 必做事项
1. 检查并同步 `02-api/`（接口、字段、状态码、错误示例）。
2. 检查并同步 `04-projects/`（模块说明、依赖关系、`last_verified`）。
3. 若发现历史遗漏，补充到对应文档并注明依据。
4. 完成后通过 `report_route` 回传 Team Lead，列出修改文件与摘要。

## 参考
- Agent 规则: `E:\moxton-ccb\.claude\agents\doc-updater.md`
- 文档根目录: `E:\moxton-ccb`
"@

Write-Utf8NoBomFile -path $docTaskFile -content $docContent
Write-Host "已生成 doc-updater 任务文件: $docTaskFile" -ForegroundColor Gray

# 获取/启动 doc-updater worker
$registryScript = Join-Path $scriptDir "worker-registry.ps1"
$startWorkerScript = Join-Path $scriptDir "start-worker.ps1"
$docUpdaterPane = & $registryScript -Action get -WorkerName "doc-updater" 2>$null

if (-not $docUpdaterPane) {
    Write-Host "doc-updater worker 未在线，尝试自动启动..." -ForegroundColor Yellow
    if (-not $TeamLeadPaneId) {
        try {
            $panes = wezterm cli list --format json 2>$null | ConvertFrom-Json
            $tlPane = $panes | Where-Object { $_.title -like '*claude*' } | Select-Object -First 1
            if ($tlPane) { $TeamLeadPaneId = $tlPane.pane_id.ToString() }
        } catch {}
    }
    if ($TeamLeadPaneId -and (Test-Path $startWorkerScript)) {
        try {
            & $startWorkerScript -WorkDir $rootDir -WorkerName "doc-updater" -Engine codex -TeamLeadPaneId $TeamLeadPaneId | Out-Null
            Start-Sleep -Seconds 3
            $docUpdaterPane = & $registryScript -Action get -WorkerName "doc-updater" 2>$null
        } catch {}
    }
}

if (-not $docUpdaterPane) {
    Write-Host "⚠️ 无法获取 doc-updater worker，记录待处理队列" -ForegroundColor Yellow
    $pendingFile = Join-Path $rootDir "config\pending-doc-updates.json"
    $pending = Read-Json -path $pendingFile
    $pendingList = if ($pending) { @($pending) } else { @() }
    $pendingList += @{
        taskId = $TaskId
        docTaskId = $docTaskId
        taskFile = $docTaskFile
        reason = $Reason
        status = "pending"
        triggeredAt = (Get-Date -Format "o")
    }
    Write-Utf8NoBomFile -path $pendingFile -content ($pendingList | ConvertTo-Json -Depth 10)
    exit 0
}

# 分派任务
$dispatchScript = Join-Path $scriptDir "dispatch-task.ps1"
& $dispatchScript `
    -WorkerPaneId $docUpdaterPane `
    -WorkerName "doc-updater" `
    -TaskId $docTaskId `
    -TaskFilePath $docTaskFile `
    -Engine codex `
    -TeamLeadPaneId $TeamLeadPaneId

Write-Host "✅ Doc-Updater 任务已分派: $docTaskId (pane $docUpdaterPane)" -ForegroundColor Green

# 记录触发历史
$historyFile = Join-Path $rootDir "config\doc-update-history.json"
$history = Read-Json -path $historyFile
$historyList = if ($history) { @($history) } else { @() }
$historyList += @{
    taskId = $TaskId
    docTaskId = $docTaskId
    reason = $Reason
    docUpdaterPane = $docUpdaterPane
    status = "dispatched"
    triggeredAt = (Get-Date -Format "o")
}
Write-Utf8NoBomFile -path $historyFile -content ($historyList | ConvertTo-Json -Depth 10)

exit 0
