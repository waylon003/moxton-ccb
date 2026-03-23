#!/usr/bin/env pwsh
# Doc-Updater 自动触发器
# Phase 1: doc-updater 改为 headless codex worker。

param(
    [Parameter(Mandatory = $true)]
    [string]$TaskId,

    [Parameter(Mandatory = $false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID,

    [Parameter(Mandatory = $false)]
    [ValidateSet('backend_qa', 'archive_move', 'round_complete', 'manual')]
    [string]$Reason = 'backend_qa',

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$EmitJson
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$rootDir = Split-Path $scriptDir -Parent

function Exit-WithResult([int]$Code, [string]$Status, [string]$Message, [hashtable]$Extra = @{}) {
    if ($EmitJson.IsPresent) {
        $payload = @{
            status = $Status
            message = $Message
            taskId = $TaskId
            reason = $Reason
            timestamp = (Get-Date -Format 'o')
        }
        foreach ($k in $Extra.Keys) {
            $payload[$k] = $Extra[$k]
        }
        Write-Output ($payload | ConvertTo-Json -Compress)
    }
    exit $Code
}

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

function Normalize-ToList($value) {
    if ($null -eq $value) { return @() }
    if ($value -is [System.Array]) { return $value }
    if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string]) -and -not ($value -is [hashtable])) {
        return @($value)
    }
    return @($value)
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

Write-Host ''
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host '      Doc-Updater 自动触发检查' -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ('任务: ' + $TaskId) -ForegroundColor White
Write-Host ('触发原因: ' + $Reason) -ForegroundColor White
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ''

$taskFile = Resolve-TaskFile -id $TaskId
$taskContent = ''
if ($taskFile) {
    $taskContent = Get-Content -Path $taskFile.FullName -Raw -Encoding UTF8
}

$requiresDocUpdate = $Force.IsPresent -or ($Reason -eq 'round_complete') -or ($Reason -eq 'archive_move')
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
    Write-Host '✅ 任务不涉及 API/文档变更，无需触发 doc-updater' -ForegroundColor Green
    Exit-WithResult -Code 0 -Status 'noop' -Message 'no_doc_update_needed'
}

Write-Host '📝 需要触发 doc-updater' -ForegroundColor Yellow

if ($Reason -eq 'backend_qa') {
    $backendDir = if (Test-Path "$rootDir\..\moxton-lotapi") { "$rootDir\..\moxton-lotapi" } else { 'E:\moxton-lotapi' }
    if (Test-Path $backendDir) {
        try {
            $recentApiFiles = Get-ChildItem -Path "$backendDir\src\routes\*" -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                $_.LastWriteTime -gt (Get-Date).AddHours(-2)
            }
            if ($recentApiFiles.Count -gt 0) {
                Write-Host ('检测到最近变更的 API 文件: ' + $recentApiFiles.Count) -ForegroundColor Gray
            }
        } catch {}
    }
}

$safeTaskToken = ($TaskId -replace '[^A-Za-z0-9\-]', '-')
$docTaskId = if ($Reason -eq 'round_complete') {
    'DOC-UPDATE-ROUND-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
} else {
    'DOC-UPDATE-' + $safeTaskToken
}
$taskFileRef = if ($taskFile) { $taskFile.FullName } else { '(task file not found)' }
$historyFile = Join-Path $rootDir 'config\doc-update-history.json'
$history = Read-Json -path $historyFile
$historyList = @(Normalize-ToList -value $history)

$reasonText = switch ($Reason) {
    'backend_qa' { '后端 QA 成功后实时同步 API 文档' }
    'archive_move' { '开发任务归档（active -> completed）后触发文档一致性同步' }
    'round_complete' { '当前无活跃任务，执行全量文档一致性兜底检查' }
    default { '手动触发文档同步' }
}

$docLines = @(
    "# $docTaskId",
    '',
    '## 触发信息',
    "- 原任务: $TaskId",
    "- 触发原因: $reasonText",
    "- 参考任务文件: $taskFileRef",
    '',
    '## 必做事项',
    '1. 检查并同步 `02-api/`（接口、字段、状态码、错误示例）。',
    '2. 检查并同步 `04-projects/`（模块说明、依赖关系、`last_verified`）。',
    '3. 若发现历史遗漏，补充到对应文档并注明依据。',
    '4. 完成后通过 `report_route` 回传 Team Lead，列出修改文件与摘要。',
    '',
    '## 参考',
    '- Agent 规则: `E:\moxton-ccb\.claude\agents\doc-updater.md`',
    '- 文档根目录: `E:\moxton-ccb`'
)
$docContent = $docLines -join "`n"

$recentExisting = $historyList | Where-Object {
    $_.docTaskId -eq $docTaskId -and $_.status -in @('dispatched', 'in_progress', 'success')
} | Sort-Object triggeredAt -Descending | Select-Object -First 1
if ($recentExisting) {
    $recentAt = $null
    try { $recentAt = [DateTimeOffset]::Parse([string]$recentExisting.triggeredAt) } catch {}
    if ($recentAt) {
        $ageSec = ([DateTimeOffset]::Now - $recentAt).TotalSeconds
        if ($ageSec -lt 120) {
            Write-Host ('跳过重复触发 doc-updater: ' + $docTaskId + ' (age=' + [int]$ageSec + 's)') -ForegroundColor Yellow
            Exit-WithResult -Code 0 -Status 'already_dispatched' -Message 'doc_updater_recently_dispatched' -Extra @{
                docTaskId = $docTaskId
                dispatchMode = 'headless'
                runId = if ($recentExisting.runId) { [string]$recentExisting.runId } else { '' }
                runDir = if ($recentExisting.runDir) { [string]$recentExisting.runDir } else { '' }
            }
        }
    }
}

Write-Host '使用 headless 派遣 doc-updater（不写入 active 任务文件）' -ForegroundColor Gray

$headlessScript = Join-Path $scriptDir 'start-headless-run.ps1'
if (-not (Test-Path $headlessScript)) {
    Write-Host ('❌ 缺少 headless runner: ' + $headlessScript) -ForegroundColor Red
    Exit-WithResult -Code 1 -Status 'dispatch_failed' -Message 'headless_runner_missing' -Extra @{
        docTaskId = $docTaskId
        dispatchMode = 'headless'
    }
}

$dispatchJson = & $headlessScript `
    -TaskId $docTaskId `
    -WorkerName 'doc-updater' `
    -WorkDir $rootDir `
    -Engine codex `
    -InlineTaskBody $docContent `
    -EmitJson

$dispatchExit = $LASTEXITCODE
if ($dispatchExit -ne 0) {
    Write-Host ('❌ Doc-Updater headless 派遣失败: exit=' + $dispatchExit) -ForegroundColor Red
    Exit-WithResult -Code 1 -Status 'dispatch_failed' -Message ('headless_dispatch_exit_' + $dispatchExit) -Extra @{
        docTaskId = $docTaskId
        dispatchMode = 'headless'
    }
}

$dispatchResp = $null
try {
    $dispatchResp = $dispatchJson | ConvertFrom-Json
} catch {
    Write-Host '❌ Doc-Updater headless 派遣返回了不可解析结果' -ForegroundColor Red
    Exit-WithResult -Code 1 -Status 'dispatch_failed' -Message 'headless_dispatch_invalid_json' -Extra @{
        docTaskId = $docTaskId
        dispatchMode = 'headless'
        raw = [string]$dispatchJson
    }
}

if (-not $dispatchResp -or [string]$dispatchResp.status -ne 'dispatched') {
    Write-Host ('❌ Doc-Updater headless 派遣异常: status=' + [string]$dispatchResp.status + ' message=' + [string]$dispatchResp.message) -ForegroundColor Red
    $dispatchMessage = if ($dispatchResp -and $dispatchResp.message) { [string]$dispatchResp.message } else { 'headless_dispatch_unknown' }
    Exit-WithResult -Code 1 -Status 'dispatch_failed' -Message $dispatchMessage -Extra @{
        docTaskId = $docTaskId
        dispatchMode = 'headless'
        runId = if ($dispatchResp.runId) { [string]$dispatchResp.runId } else { '' }
    }
}

Write-Host ('✅ Doc-Updater headless 任务已启动: ' + $docTaskId + ' (pid ' + [string]$dispatchResp.pid + ')') -ForegroundColor Green

$historyList += @{
    taskId = $TaskId
    docTaskId = $docTaskId
    reason = $Reason
    dispatchMode = 'headless'
    status = 'dispatched'
    triggeredAt = (Get-Date -Format 'o')
    runId = [string]$dispatchResp.runId
    runDir = [string]$dispatchResp.runDir
    pid = [int]$dispatchResp.pid
}
Write-Utf8NoBomFile -path $historyFile -content ($historyList | ConvertTo-Json -Depth 10)

Exit-WithResult -Code 0 -Status 'dispatched' -Message 'doc_updater_dispatched' -Extra @{
    docTaskId = $docTaskId
    dispatchMode = 'headless'
    runId = [string]$dispatchResp.runId
    runDir = [string]$dispatchResp.runDir
    pid = [int]$dispatchResp.pid
}
