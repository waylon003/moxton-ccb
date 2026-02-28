#!/usr/bin/env pwsh
# [ROUTE] Message Monitor - Poll route inbox, update task locks, trigger doc-updater
# Usage: .\route-monitor.ps1 -TeamLeadPaneId <id> [-Continuous]

param(
    [Parameter(Mandatory = $false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID,

    [Parameter(Mandatory = $false)]
    [switch]$Continuous,

    [Parameter(Mandatory = $false)]
    [int]$PollIntervalSeconds = 5
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path $PSScriptRoot -Parent
$locksFile = Join-Path $scriptDir "01-tasks\TASK-LOCKS.json"
$inboxFile = Join-Path $scriptDir "mcp\route-server\data\route-inbox.json"
$docTriggerScript = Join-Path $scriptDir "scripts\trigger-doc-updater.ps1"
$commitTriggerScript = Join-Path $scriptDir "scripts\trigger-repo-committer.ps1"
$processedRoutes = @{}
$processedRoutesFile = Join-Path $env:TEMP "moxton-ccb-processed-routes.json"
$activeSnapshotFile = Join-Path $env:TEMP "moxton-active-snapshot.json"
$activeTaskIds = @()

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

function Load-ProcessedRoutes {
    $saved = Read-Json -path $processedRoutesFile
    if (-not $saved) { return }
    foreach ($key in $saved.PSObject.Properties.Name) {
        $processedRoutes[$key] = $saved.$key
    }
}

function Save-ProcessedRoutes {
    $recent = @{}
    $keys = $processedRoutes.Keys | Sort-Object -Descending | Select-Object -First 300
    foreach ($k in $keys) { $recent[$k] = $processedRoutes[$k] }
    Write-Utf8NoBomFile -path $processedRoutesFile -content ($recent | ConvertTo-Json -Depth 4)
}

function Get-ShortHash([string]$text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLower().Substring(0, 16)
    } finally {
        $sha.Dispose()
    }
}

function Update-TaskLockFromRoute {
    param(
        [string]$TaskId,
        [string]$Status,
        [string]$WorkerName,
        [string]$Body
    )

    if (-not (Test-Path $locksFile)) { return }
    $locks = Read-Json -path $locksFile
    if (-not $locks -or -not $locks.locks) { return }
    if ($locks.locks.PSObject.Properties.Name -notcontains $TaskId) { return }

    $previousState = [string]$locks.locks.$TaskId.state
    $safeStatus = if ($null -eq $Status) { "" } else { [string]$Status }
    $lockState = switch ($safeStatus.ToLower()) {
        "success" {
            if ($WorkerName -match "-qa$") { "completed" }
            elseif ($WorkerName -match "-dev$") { "waiting_qa" }
            else { "waiting_qa" }
        }
        "fail" { "blocked" }
        "blocked" { "blocked" }
        "in_progress" { "in_progress" }
        "qa" { "qa" }
        "waiting_qa" { "waiting_qa" }
        default { $Status }
    }

    $locks.locks.$TaskId.state = $lockState
    $locks.locks.$TaskId.updated_at = Get-Date -Format "o"
    $locks.locks.$TaskId.updated_by = "route-monitor"
    $safeBody = if ($null -eq $Body) { "" } else { [string]$Body }
    $bodyPreview = if ($safeBody.Length -gt 100) { $safeBody.Substring(0, 100) + "..." } else { $safeBody }
    $locks.locks.$TaskId.routeUpdate = @{
        worker = $WorkerName
        timestamp = (Get-Date -Format "o")
        bodyPreview = $bodyPreview
    }
    $locks.updated_at = Get-Date -Format "o"
    Write-Utf8NoBomFile -path $locksFile -content ($locks | ConvertTo-Json -Depth 12)

    Write-Host ("  Task lock updated: " + $TaskId + " -> " + $lockState) -ForegroundColor Green

    # 后端 QA 成功后实时触发 doc-updater
    if ($lockState -eq "completed" -and $TaskId -match "^BACKEND-" -and $WorkerName -match "-qa$" -and (Test-Path $docTriggerScript)) {
        Write-Host "  Triggering doc-updater (backend_qa)..." -ForegroundColor Cyan
        Start-Job -ScriptBlock {
            param($script, $task, $pane)
            & $script -TaskId $task -TeamLeadPaneId $pane -Reason backend_qa -Force
        } -ArgumentList $docTriggerScript, $TaskId, $TeamLeadPaneId | Out-Null
    }

    # QA success 后触发对应仓库自动提交（仅 qa -> completed 首次过渡）
    if ($previousState -eq "qa" -and $lockState -eq "completed" -and $WorkerName -match "-qa$" -and $TaskId -match "^(BACKEND|SHOP-FE|ADMIN-FE)-" -and (Test-Path $commitTriggerScript)) {
        Write-Host "  Triggering repo-committer..." -ForegroundColor Cyan
        Start-Job -ScriptBlock {
            param($script, $task, $pane)
            & $script -TaskId $task -TeamLeadPaneId $pane
        } -ArgumentList $commitTriggerScript, $TaskId, $TeamLeadPaneId | Out-Null
    }
}

function Show-RouteNotification($route) {
    $statusText = if ($null -eq $route.status) { "" } else { [string]$route.status }
    $status = $statusText.ToLower()
    $color = if ($status -eq "success") { "Green" } elseif ($status -eq "fail") { "Red" } else { "Yellow" }
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor $color
    Write-Host "  [ROUTE] Message Received" -ForegroundColor White
    Write-Host "==============================================" -ForegroundColor $color
    Write-Host ("  From:   " + $route.from) -ForegroundColor White
    Write-Host ("  Task:   " + $route.task) -ForegroundColor White
    Write-Host ("  Status: " + $route.status) -ForegroundColor White
    Write-Host "==============================================" -ForegroundColor $color
}

function Process-InboxRoutes {
    $inbox = Read-Json -path $inboxFile
    if (-not $inbox -or -not $inbox.routes) { return }
    $routes = @($inbox.routes | Where-Object { $_.task -and $_.from -and $_.status -and -not $_.processed })
    foreach ($r in $routes) {
        $routeId = if ($r.id) { $r.id } else { Get-ShortHash("$($r.task)|$($r.from)|$($r.status)|$($r.created_at)") }
        if ($processedRoutes.ContainsKey($routeId)) { continue }
        $processedRoutes[$routeId] = Get-Date -Format "o"
        Save-ProcessedRoutes
        Show-RouteNotification -route $r
        Update-TaskLockFromRoute -TaskId $r.task -Status $r.status -WorkerName $r.from -Body $r.body
    }
}

function Get-ActiveTaskIds {
    $activeRoot = Join-Path $scriptDir "01-tasks\active"
    if (-not (Test-Path $activeRoot)) { return @() }

    $ids = New-Object System.Collections.Generic.List[string]
    $files = @(Get-ChildItem -Path $activeRoot -Recurse -File -Filter *.md -ErrorAction SilentlyContinue)
    foreach ($f in $files) {
        $m = [regex]::Match($f.BaseName, '^([A-Z]+(?:-[A-Z]+)?-\d+)')
        if ($m.Success) {
            $ids.Add($m.Groups[1].Value.ToUpper())
        } else {
            $ids.Add($f.BaseName.ToUpper())
        }
    }
    return @($ids | Sort-Object -Unique)
}

function Read-ActiveSnapshotIds {
    $saved = Read-Json -path $activeSnapshotFile
    if (-not $saved -or -not $saved.active_task_ids) { return $null }
    return @($saved.active_task_ids | ForEach-Object { $_.ToString().ToUpper() } | Sort-Object -Unique)
}

function Save-ActiveSnapshotIds([string[]]$ids) {
    $payload = @{
        updated_at = (Get-Date -Format "o")
        active_task_ids = @($ids)
    }
    Write-Utf8NoBomFile -path $activeSnapshotFile -content ($payload | ConvertTo-Json -Depth 5)
}

function Test-TaskMovedToCompleted([string]$taskId) {
    $completedRoot = Join-Path $scriptDir "01-tasks\completed"
    if (-not (Test-Path $completedRoot)) { return $false }
    $matches = Get-ChildItem -Path "$completedRoot\*\$taskId*.md" -File -ErrorAction SilentlyContinue
    return ($matches.Count -gt 0)
}

function Check-RoundCompleteTrigger {
    $currentActive = @(Get-ActiveTaskIds)
    $previousActive = @($script:activeTaskIds)

    # 首次启动只建立基线，不触发
    if ($null -eq $previousActive) {
        $previousActive = @()
    }
    if ($script:activeTaskIds.Count -eq 0 -and -not (Test-Path $activeSnapshotFile)) {
        $script:activeTaskIds = @($currentActive)
        Save-ActiveSnapshotIds -ids $script:activeTaskIds
        return
    }

    $removed = @($previousActive | Where-Object { $_ -notin $currentActive })
    $removedToCompleted = @($removed | Where-Object { Test-TaskMovedToCompleted $_ })
    $movedToCompletedNow = ($removedToCompleted.Count -gt 0)
    $becameEmpty = ($previousActive.Count -gt 0 -and $currentActive.Count -eq 0)

    if ($becameEmpty -and $movedToCompletedNow -and (Test-Path $docTriggerScript)) {
        $idsText = ($removedToCompleted -join ", ")
        Write-Host ("[ROUND] active->completed transition detected (" + $idsText + "), trigger doc-updater round_complete") -ForegroundColor Cyan
        Start-Job -ScriptBlock {
            param($script, $pane)
            & $script -TaskId "ROUND-COMPLETE" -TeamLeadPaneId $pane -Reason round_complete -Force
        } -ArgumentList $docTriggerScript, $TeamLeadPaneId | Out-Null
    }

    $script:activeTaskIds = @($currentActive)
    Save-ActiveSnapshotIds -ids $script:activeTaskIds
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "       [ROUTE] Message Monitor Started" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ("Team Lead Pane ID: " + $TeamLeadPaneId) -ForegroundColor Cyan
Write-Host ("Mode: " + ($(if ($Continuous) { "Continuous monitoring" } else { "Single check" }))) -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

Load-ProcessedRoutes
$loadedActive = Read-ActiveSnapshotIds
if ($null -ne $loadedActive) {
    $script:activeTaskIds = @($loadedActive)
} else {
    $script:activeTaskIds = @(Get-ActiveTaskIds)
    Save-ActiveSnapshotIds -ids $script:activeTaskIds
}

do {
    try {
        Process-InboxRoutes
        Check-RoundCompleteTrigger
    } catch {
        Write-Host ("Monitor error: " + $_.Exception.Message) -ForegroundColor Yellow
    }

    if ($Continuous) {
        Start-Sleep -Seconds $PollIntervalSeconds
    }
} while ($Continuous)

Write-Host ""
Write-Host "Monitor stopped." -ForegroundColor Cyan
