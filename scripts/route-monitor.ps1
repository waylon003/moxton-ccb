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
$docSyncStateFile = Join-Path $scriptDir "config\api-doc-sync-state.json"
$archiveJobsFile = Join-Path $scriptDir "config\archive-jobs.json"
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

function Convert-ObjectToHashtable($obj) {
    $hash = @{}
    if ($null -eq $obj) { return $hash }
    foreach ($p in $obj.PSObject.Properties) {
        $hash[$p.Name] = $p.Value
    }
    return $hash
}

function Read-DocSyncState {
    $default = @{
        version = "1.0"
        updated_at = (Get-Date -Format "o")
        last_successful_doc_sync_at = ""
        last_round_sync_at = ""
        backend = @{}
    }
    if (-not (Test-Path $docSyncStateFile)) { return $default }
    try {
        $raw = Get-Content $docSyncStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $state = @{
            version = if ($raw.version) { [string]$raw.version } else { "1.0" }
            updated_at = if ($raw.updated_at) { [string]$raw.updated_at } else { (Get-Date -Format "o") }
            last_successful_doc_sync_at = if ($raw.last_successful_doc_sync_at) { [string]$raw.last_successful_doc_sync_at } else { "" }
            last_round_sync_at = if ($raw.last_round_sync_at) { [string]$raw.last_round_sync_at } else { "" }
            backend = @{}
        }
        if ($raw.backend) {
            $state.backend = Convert-ObjectToHashtable $raw.backend
        }
        return $state
    } catch {
        return $default
    }
}

function Write-DocSyncState($state) {
    $state.updated_at = Get-Date -Format "o"
    Write-Utf8NoBomFile -path $docSyncStateFile -content ($state | ConvertTo-Json -Depth 12)
}

function Read-ArchiveJobs {
    $default = @{
        version = "1.0"
        updated_at = (Get-Date -Format "o")
        jobs = @{}
    }
    if (-not (Test-Path $archiveJobsFile)) { return $default }
    try {
        $raw = Get-Content $archiveJobsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $raw.jobs) {
            $raw | Add-Member -NotePropertyName jobs -NotePropertyValue @{} -Force
        }
        return $raw
    } catch {
        return $default
    }
}

function Write-ArchiveJobs($state) {
    $state.updated_at = Get-Date -Format "o"
    Write-Utf8NoBomFile -path $archiveJobsFile -content ($state | ConvertTo-Json -Depth 12)
}

function Mark-BackendDocSyncPending([string]$BackendTaskId, [string]$QaWorker) {
    if (-not $BackendTaskId) { return }
    $state = Read-DocSyncState
    if (-not $state.backend.ContainsKey($BackendTaskId)) {
        $state.backend[$BackendTaskId] = @{}
    }
    $entry = $state.backend[$BackendTaskId]
    $now = Get-Date -Format "o"
    $entry.qa_completed_at = $now
    $entry.qa_worker = $QaWorker
    $entry.doc_sync_required = $true
    $entry.doc_sync_status = "pending"
    $entry.expected_doc_task_id = "DOC-UPDATE-" + $BackendTaskId
    $entry.updated_at = $now
    $state.backend[$BackendTaskId] = $entry
    Write-DocSyncState $state
    Write-Host ("  API doc sync marked pending: " + $BackendTaskId) -ForegroundColor DarkYellow
}

function Update-DocSyncStateFromRoute {
    param(
        [string]$TaskId,
        [string]$Status,
        [string]$WorkerName,
        [string]$Body
    )

    if ($WorkerName -ne "doc-updater") { return }
    if (-not $TaskId) { return }
    $statusLower = if ($Status) { $Status.ToLower() } else { "" }
    $taskUpper = $TaskId.ToUpper()
    $state = Read-DocSyncState
    $now = Get-Date -Format "o"

    if ($taskUpper -match '^DOC-UPDATE-(BACKEND-\d+)$') {
        $backendTask = $Matches[1]
        if (-not $state.backend.ContainsKey($backendTask)) {
            $state.backend[$backendTask] = @{}
        }
        $entry = $state.backend[$backendTask]
        $entry.last_doc_task_id = $taskUpper
        $entry.last_doc_route_status = $statusLower
        if ($statusLower -eq "success") {
            $entry.doc_sync_status = "synced"
            $entry.doc_synced_at = $now
            $state.last_successful_doc_sync_at = $now
        } elseif ($statusLower -eq "blocked") {
            $entry.doc_sync_status = "blocked"
            $entry.last_blocked_at = $now
        } elseif ($statusLower -eq "fail") {
            $entry.doc_sync_status = "fail"
            $entry.last_fail_at = $now
        }
        $entry.updated_at = $now
        $state.backend[$backendTask] = $entry
        Write-DocSyncState $state
        Write-Host ("  API doc sync state updated: " + $backendTask + " -> " + $entry.doc_sync_status) -ForegroundColor Cyan
        return
    }

    if ($taskUpper -match '^DOC-UPDATE-ROUND-' -and $statusLower -eq "success") {
        $state.last_round_sync_at = $now
        Write-DocSyncState $state
        Write-Host "  Round doc sync marked success." -ForegroundColor Cyan
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

function Get-PropValue($obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    if ($obj -is [System.Collections.IDictionary]) {
        if ($obj.Contains($name)) { return $obj[$name] }
        return $null
    }
    $p = $obj.PSObject.Properties[$name]
    if ($p) { return $p.Value }
    return $null
}

function Convert-ToStringArray($value) {
    if ($null -eq $value) { return @() }
    if ($value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($value)) { return @() }
        return @($value.Trim())
    }
    if ($value -is [System.Collections.IEnumerable]) {
        $arr = @()
        foreach ($v in $value) {
            if ($null -eq $v) { continue }
            $s = [string]$v
            if (-not [string]::IsNullOrWhiteSpace($s)) { $arr += $s.Trim() }
        }
        return $arr
    }
    $single = [string]$value
    if ([string]::IsNullOrWhiteSpace($single)) { return @() }
    return @($single.Trim())
}

function Convert-ToBoolean($value, [bool]$default = $false) {
    if ($value -is [bool]) { return $value }
    if ($value -is [string]) {
        $v = $value.Trim().ToLower()
        if ($v -in @("true", "1", "yes", "y")) { return $true }
        if ($v -in @("false", "0", "no", "n")) { return $false }
    }
    return $default
}

function Resolve-EvidencePath([string]$pathText) {
    if ([string]::IsNullOrWhiteSpace($pathText)) { return $null }
    $trimmed = $pathText.Trim().Replace("/", "\")
    if ([System.IO.Path]::IsPathRooted($trimmed)) { return $trimmed }
    return Join-Path $scriptDir $trimmed
}

function Validate-EvidencePaths {
    param(
        [string[]]$Paths,
        [string]$FieldName,
        [System.Collections.Generic.List[string]]$Errors
    )
    if ($Paths.Count -eq 0) {
        $Errors.Add($FieldName + ".evidence 不能为空") | Out-Null
        return
    }
    foreach ($p in $Paths) {
        $resolved = Resolve-EvidencePath -pathText $p
        if (-not $resolved -or -not (Test-Path $resolved)) {
            $Errors.Add($FieldName + ".evidence 文件不存在: " + $p) | Out-Null
        }
    }
}

function Validate-QaSuccessBody {
    param(
        [string]$TaskId,
        [string]$WorkerName,
        [string]$Body
    )

    $errors = New-Object 'System.Collections.Generic.List[string]'
    if ([string]::IsNullOrWhiteSpace($Body)) {
        $errors.Add("body 不能为空（QA success 必须为 JSON）") | Out-Null
        return @{ valid = $false; errors = @($errors) }
    }

    try {
        $payload = $Body | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $errors.Add("body 不是合法 JSON: " + $_.Exception.Message) | Out-Null
        return @{ valid = $false; errors = @($errors) }
    }

    $taskInBody = [string](Get-PropValue $payload "task_id")
    if ([string]::IsNullOrWhiteSpace($taskInBody)) {
        $errors.Add("缺少 task_id") | Out-Null
    } elseif ($taskInBody.ToUpper() -ne $TaskId.ToUpper()) {
        $errors.Add("task_id 不匹配（body=" + $taskInBody + ", route=" + $TaskId + "）") | Out-Null
    }

    $workerInBody = [string](Get-PropValue $payload "worker")
    if ([string]::IsNullOrWhiteSpace($workerInBody)) {
        $errors.Add("缺少 worker") | Out-Null
    } elseif ($workerInBody.ToLower() -ne $WorkerName.ToLower()) {
        $errors.Add("worker 不匹配（body=" + $workerInBody + ", route=" + $WorkerName + "）") | Out-Null
    }

    $verdictRaw = [string](Get-PropValue $payload "verdict")
    if ([string]::IsNullOrWhiteSpace($verdictRaw)) {
        $errors.Add("缺少 verdict（PASS/FAIL/BLOCKED）") | Out-Null
    } elseif ($verdictRaw.Trim().ToUpper() -ne "PASS") {
        $errors.Add("status=success 时 verdict 必须是 PASS") | Out-Null
    }

    $checks = Get-PropValue $payload "checks"
    if ($null -eq $checks) {
        $errors.Add("缺少 checks 对象") | Out-Null
    } else {
        $isFrontendQa = ($WorkerName -in @("shop-fe-qa", "admin-fe-qa"))
        $requiredCheckKeys = if ($isFrontendQa) {
            @("ui", "console", "network", "failure_path")
        } else {
            @("contract", "network", "failure_path")
        }

        foreach ($k in $requiredCheckKeys) {
            $node = Get-PropValue $checks $k
            if ($null -eq $node) {
                $errors.Add("缺少 checks." + $k) | Out-Null
                continue
            }

            $passVal = Get-PropValue $node "pass"
            if (-not (Convert-ToBoolean -value $passVal -default $false)) {
                $errors.Add("checks." + $k + ".pass 必须为 true") | Out-Null
            }

            $evidence = Convert-ToStringArray (Get-PropValue $node "evidence")
            Validate-EvidencePaths -Paths $evidence -FieldName ("checks." + $k) -Errors $errors
        }

        $network = Get-PropValue $checks "network"
        if ($network) {
            $has5xxVal = Get-PropValue $network "has_5xx"
            if ($null -eq $has5xxVal) {
                $errors.Add("checks.network.has_5xx 缺失") | Out-Null
            } elseif (Convert-ToBoolean -value $has5xxVal -default $false) {
                $errors.Add("checks.network.has_5xx=true，不允许回传 success") | Out-Null
            }
        }

        if ($isFrontendQa) {
            $console = Get-PropValue $checks "console"
            if ($console) {
                $errorCount = Get-PropValue $console "error_count"
                $tmp = 0
                if ($null -eq $errorCount -or -not [int]::TryParse(([string]$errorCount), [ref]$tmp)) {
                    $errors.Add("checks.console.error_count 必须是数字") | Out-Null
                }
            }
        }

        $failureNode = Get-PropValue $checks "failure_path"
        if ($failureNode) {
            $scenario = [string](Get-PropValue $failureNode "scenario")
            if ([string]::IsNullOrWhiteSpace($scenario)) {
                $errors.Add("checks.failure_path.scenario 不能为空") | Out-Null
            }
        }
    }

    if ($errors.Count -gt 0) {
        return @{ valid = $false; errors = @($errors) }
    }
    return @{ valid = $true; errors = @() }
}

function Apply-QaSuccessGate {
    param([object]$Route)

    $statusLower = if ($Route.status) { ([string]$Route.status).ToLower() } else { "" }
    $fromText = if ($Route.from) { [string]$Route.from } else { "" }

    if ($statusLower -ne "success" -or $fromText -notmatch "-qa$") {
        return @{
            route = $Route
            downgraded = $false
            reason = ""
        }
    }

    $taskId = if ($Route.task) { [string]$Route.task } else { "" }
    $bodyText = if ($Route.body) { [string]$Route.body } else { "" }
    $validation = Validate-QaSuccessBody -TaskId $taskId -WorkerName $fromText -Body $bodyText
    if ($validation.valid) {
        return @{
            route = $Route
            downgraded = $false
            reason = ""
        }
    }

    $errList = @($validation.errors | Select-Object -First 6)
    $errText = [string]::Join(" | ", $errList)
    $blockedBody = "blocker_type=qa_report_invalid; question=请补齐 QA 结构化证据并重新回传 success; attempted=route-monitor 校验失败; next_action_needed=重新派遣 QA 补证据; validation_errors=" + $errText

    $downgradedRoute = [PSCustomObject]@{
        id = $Route.id
        from = $Route.from
        task = $Route.task
        status = "blocked"
        body = $blockedBody
        created_at = $Route.created_at
        processed = $Route.processed
    }

    return @{
        route = $downgradedRoute
        downgraded = $true
        reason = $errText
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
    if ($lockState -eq "completed" -and $TaskId -match "^BACKEND-" -and $WorkerName -match "-qa$") {
        Mark-BackendDocSyncPending -BackendTaskId $TaskId -QaWorker $WorkerName
        if (Test-Path $docTriggerScript) {
            Write-Host "  Triggering doc-updater (backend_qa)..." -ForegroundColor Cyan
            Start-Job -ScriptBlock {
                param($script, $task, $pane)
                & $script -TaskId $task -TeamLeadPaneId $pane -Reason backend_qa -Force
            } -ArgumentList $docTriggerScript, $TaskId, $TeamLeadPaneId | Out-Null
        } else {
            Write-Host "  [WARN] trigger-doc-updater.ps1 missing, backend doc sync remains pending." -ForegroundColor Yellow
        }
    }

}

function Set-TaskLockState {
    param(
        [string]$TaskId,
        [string]$State,
        [string]$UpdatedBy,
        [string]$Note
    )
    if (-not (Test-Path $locksFile)) { return }
    $locks = Read-Json -path $locksFile
    if (-not $locks -or -not $locks.locks) { return }
    if ($locks.locks.PSObject.Properties.Name -notcontains $TaskId) { return }
    $locks.locks.$TaskId.state = $State
    $locks.locks.$TaskId.updated_at = Get-Date -Format "o"
    $locks.locks.$TaskId.updated_by = $UpdatedBy
    if ($Note) {
        $locks.locks.$TaskId.note = $Note
    }
    $locks.updated_at = Get-Date -Format "o"
    Write-Utf8NoBomFile -path $locksFile -content ($locks | ConvertTo-Json -Depth 12)
}

function Normalize-SubTaskStatus([string]$RouteStatus) {
    $s = if ($RouteStatus) { $RouteStatus.ToLower() } else { "" }
    switch ($s) {
        "success" { return "success" }
        "fail" { return "blocked" }
        "blocked" { return "blocked" }
        "in_progress" { return "in_progress" }
        default { return "pending" }
    }
}

function Update-ArchiveJobsFromRoute {
    param(
        [string]$RouteTaskId,
        [string]$RouteStatus,
        [string]$WorkerName,
        [string]$Body
    )
    if (-not $RouteTaskId) { return }
    $jobs = Read-ArchiveJobs
    if (-not $jobs.jobs) { return }

    $jobHash = @{}
    foreach ($p in $jobs.jobs.PSObject.Properties) {
        $jobHash[$p.Name] = $p.Value
    }

    $changed = $false
    foreach ($jobId in @($jobHash.Keys)) {
        $job = $jobHash[$jobId]
        if (-not $job) { continue }
        $docTaskId = if ($job.doc_task_id) { [string]$job.doc_task_id } else { "" }
        $commitTaskId = if ($job.commit_task_id) { [string]$job.commit_task_id } else { "" }
        if ($RouteTaskId -ne $docTaskId -and $RouteTaskId -ne $commitTaskId) { continue }

        $subStatus = Normalize-SubTaskStatus -RouteStatus $RouteStatus
        if ($RouteTaskId -eq $docTaskId) {
            $job.doc_status = $subStatus
        }
        if ($RouteTaskId -eq $commitTaskId) {
            $job.commit_status = $subStatus
        }

        $docState = if ($job.doc_status) { [string]$job.doc_status } else { "pending" }
        $commitState = if ($job.commit_status) { [string]$job.commit_status } else { "pending" }
        $taskId = if ($job.task_id) { [string]$job.task_id } else { "" }

        if ($docState -eq "blocked" -or $commitState -eq "blocked") {
            $job.status = "blocked"
            $job.updated_at = Get-Date -Format "o"
            $job.updated_by = "route-monitor/archive"
            $job.blocked_reason = "doc=" + $docState + ", commit=" + $commitState + ", route=" + $RouteTaskId + ", worker=" + $WorkerName
            if ($taskId) {
                Set-TaskLockState -TaskId $taskId -State "blocked" -UpdatedBy "route-monitor/archive" -Note ("Archive blocked: " + $job.blocked_reason)
            }
            Write-Host ("  [ARCHIVE-JOB] " + $taskId + " blocked (doc=" + $docState + ", commit=" + $commitState + ")") -ForegroundColor Red
        } elseif ($docState -eq "success" -and $commitState -eq "success") {
            $job.status = "success"
            $job.updated_at = Get-Date -Format "o"
            $job.updated_by = "route-monitor/archive"
            $job.completed_at = Get-Date -Format "o"
            if ($taskId) {
                Set-TaskLockState -TaskId $taskId -State "completed" -UpdatedBy "route-monitor/archive" -Note "Archive finalized: doc-updater + repo-committer success"
            }
            Write-Host ("  [ARCHIVE-JOB] " + $taskId + " finalized -> completed") -ForegroundColor Green
        } else {
            $job.status = "running"
            $job.updated_at = Get-Date -Format "o"
            $job.updated_by = "route-monitor/archive"
            if ($taskId) {
                Set-TaskLockState -TaskId $taskId -State "archiving" -UpdatedBy "route-monitor/archive" -Note ("Archive running: doc=" + $docState + ", commit=" + $commitState)
            }
            Write-Host ("  [ARCHIVE-JOB] " + $taskId + " running (doc=" + $docState + ", commit=" + $commitState + ")") -ForegroundColor Cyan
        }

        $jobHash[$jobId] = $job
        $changed = $true
    }

    if ($changed) {
        $jobs.jobs = $jobHash
        Write-ArchiveJobs $jobs
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
        $gate = Apply-QaSuccessGate -Route $r
        $effectiveRoute = $gate.route
        if ($gate.downgraded) {
            Write-Host ("  [QA GATE] success -> blocked: " + $gate.reason) -ForegroundColor Yellow
        }
        Show-RouteNotification -route $effectiveRoute
        Update-DocSyncStateFromRoute -TaskId $effectiveRoute.task -Status $effectiveRoute.status -WorkerName $effectiveRoute.from -Body $effectiveRoute.body
        Update-ArchiveJobsFromRoute -RouteTaskId ([string]$effectiveRoute.task) -RouteStatus ([string]$effectiveRoute.status) -WorkerName ([string]$effectiveRoute.from) -Body ([string]$effectiveRoute.body)
        Update-TaskLockFromRoute -TaskId $effectiveRoute.task -Status $effectiveRoute.status -WorkerName $effectiveRoute.from -Body $effectiveRoute.body
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

    if ($movedToCompletedNow -and (Test-Path $docTriggerScript)) {
        $idsText = ($removedToCompleted -join ", ")
        Write-Host ("[ARCHIVE] active->completed transition detected (" + $idsText + "), trigger doc-updater archive_move") -ForegroundColor Cyan
        foreach ($movedTaskId in $removedToCompleted) {
            Start-Job -ScriptBlock {
                param($script, $task, $pane)
                & $script -TaskId $task -TeamLeadPaneId $pane -Reason archive_move -Force
            } -ArgumentList $docTriggerScript, $movedTaskId, $TeamLeadPaneId | Out-Null
        }
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
