#!/usr/bin/env pwsh
# teamlead-control.ps1 - Team Lead Unified Controller
# Single entry point, hard gates, minimal freedom
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action bootstrap
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action dispatch -TaskId BACKEND-009
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action dispatch-qa -TaskId BACKEND-009
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action dispatch -TaskId BACKEND-009 -DispatchEngine codex
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action status
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action requeue -TaskId BACKEND-009 -TargetState waiting_qa -RequeueReason "review_reject"
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action recover -RecoverAction reap-stale
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action recover -RecoverAction baseline-clean
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action recover -RecoverAction full-clean
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action archive -TaskId SHOP-FE-004
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action approve-request -RequestId APR-20260228120000-0001
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action deny-request -RequestId APR-20260228120000-0001

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("bootstrap", "dispatch", "dispatch-qa", "status", "requeue", "recover", "add-lock", "archive", "approve-request", "deny-request")]
    [string]$Action,

    [Parameter(Mandatory=$false)]
    [string]$TaskId,

    [Parameter(Mandatory=$false)]
    [ValidateSet("reap-stale", "restart-worker", "reset-task", "normalize-locks", "baseline-clean", "full-clean")]
    [string]$RecoverAction,

    [Parameter(Mandatory=$false)]
    [string]$WorkerName,

    [Parameter(Mandatory=$false)]
    [string]$TargetState,

    [Parameter(Mandatory=$false)]
    [string]$RequestId,

    [Parameter(Mandatory=$false)]
    [string]$RequeueReason,

    [Parameter(Mandatory=$false)]
    [switch]$NoPush,

    [Parameter(Mandatory=$false)]
    [string]$CommitMessage,

    [Parameter(Mandatory=$false)]
    [switch]$DryRun,

    [Parameter(Mandatory=$false)]
    [ValidateSet("codex", "gemini")]
    [string]$DispatchEngine
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
$taskLocksPath = Join-Path $rootDir "01-tasks\TASK-LOCKS.json"
$workerMapPath = Join-Path $rootDir "config\worker-map.json"
$registryPath = Join-Path $rootDir "config\worker-panels.json"
$bootstrapFlag = Join-Path $env:TEMP "moxton-bootstrap-done.flag"
$monitorPidFile = Join-Path $env:TEMP "moxton-route-monitor.pid"
$approvalRouterPidFile = Join-Path $env:TEMP "moxton-approval-router-pids.json"
$approvalRequestsPath = Join-Path $rootDir "mcp\route-server\data\approval-requests.json"
$docSyncStatePath = Join-Path $rootDir "config\api-doc-sync-state.json"
$archiveJobsPath = Join-Path $rootDir "config\archive-jobs.json"
$taskAttemptHistoryPath = Join-Path $rootDir "config\task-attempt-history.json"
$dispatchMutexName = "Global\MoxtonTeamLeadDispatchMutex"
$taskLocksMutexName = "Global\MoxtonTaskLocksFileMutex"

# ============================================================
# Internal Functions
# ============================================================

function Write-Utf8NoBomFile([string]$path, [string]$content) {
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

function Resolve-TeamLeadPaneId {
    if ($env:TEAM_LEAD_PANE_ID) {
        return $env:TEAM_LEAD_PANE_ID
    }
    try {
        $panes = wezterm cli list --format json 2>$null | ConvertFrom-Json
        $tlPane = $panes | Where-Object { $_.title -like '*claude*' } | Select-Object -First 1
        if ($tlPane) {
            $env:TEAM_LEAD_PANE_ID = $tlPane.pane_id.ToString()
            return $env:TEAM_LEAD_PANE_ID
        }
    } catch {}
    Write-Host '[FAIL] Cannot detect Team Lead Pane ID. Set $env:TEAM_LEAD_PANE_ID manually.' -ForegroundColor Red
    exit 1
}

function Resolve-TaskPrefix($tid) {
    $prefixes = @("ADMIN-FE", "SHOP-FE", "BACKEND")
    foreach ($p in $prefixes) {
        if ($tid.StartsWith("$p-")) { return $p }
    }
    return $null
}

function Assert-CanonicalTaskId([string]$tid) {
    if (-not $tid) {
        Write-Host '[FAIL] TaskId is required.' -ForegroundColor Red
        exit 1
    }
    $normalized = $tid.Trim().ToUpper()
    if ($normalized -notmatch '^(BACKEND|SHOP-FE|ADMIN-FE)-\d+$') {
        Write-Host ('[FAIL] Invalid TaskId format: ' + $tid) -ForegroundColor Red
        Write-Host '       Expected canonical format: BACKEND-001 / SHOP-FE-001 / ADMIN-FE-001' -ForegroundColor Yellow
        Write-Host '       Do not append suffixes like -FIX to TaskId. Put fix info in file title/note.' -ForegroundColor Yellow
        exit 1
    }
}

function Get-InvalidTaskLockKeys($locks) {
    $invalid = New-Object System.Collections.Generic.List[string]
    if (-not $locks -or -not $locks.locks) { return @() }
    foreach ($p in $locks.locks.PSObject.Properties) {
        $k = [string]$p.Name
        if ($k -notmatch '^(BACKEND|SHOP-FE|ADMIN-FE)-\d+$') {
            $invalid.Add($k) | Out-Null
        }
    }
    return @($invalid.ToArray())
}

function Assert-NoInvalidTaskLockEntries($locks) {
    $invalid = @(Get-InvalidTaskLockKeys $locks)
    if ($invalid.Count -eq 0) { return }
    Write-Host '[FAIL] TASK-LOCKS.json contains non-canonical TaskId keys:' -ForegroundColor Red
    foreach ($k in $invalid) {
        Write-Host ('  - ' + $k) -ForegroundColor Yellow
    }
    Write-Host '       Please normalize locks before dispatch:' -ForegroundColor Yellow
    Write-Host ('       powershell -NoProfile -ExecutionPolicy Bypass -File "' + $scriptDir + '\teamlead-control.ps1" -Action recover -RecoverAction normalize-locks') -ForegroundColor White
    exit 1
}

function Read-TaskLocks {
    if (-not (Test-Path $taskLocksPath)) {
        return @{ version = "1.0"; rev = 0; updated_at = (Get-Date -Format "o"); locks = @{} }
    }
    $raw = Get-Content $taskLocksPath -Raw -Encoding UTF8
    $parsed = $raw | ConvertFrom-Json
    if (-not $parsed.PSObject.Properties['rev']) {
        $parsed | Add-Member -NotePropertyName rev -NotePropertyValue 0 -Force
    }
    if (-not $parsed.PSObject.Properties['version']) {
        $parsed | Add-Member -NotePropertyName version -NotePropertyValue "1.0" -Force
    }
    return $parsed
}

function Write-TaskLocks($data) {
    if (-not $data.version) { $data.version = "1.0" }
    if (-not $data.PSObject.Properties['rev']) {
        $data | Add-Member -NotePropertyName rev -NotePropertyValue 0 -Force
    }
    $data.rev = [int]$data.rev + 1
    $data.updated_at = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    $json = ($data | ConvertTo-Json -Depth 10)
    Write-Utf8NoBomFile -path $taskLocksPath -content $json
}

function Invoke-WithTaskLocksMutex([scriptblock]$Script, [int]$TimeoutMs = 10000, [int]$RetryMs = 120) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $mutex = $null
    try {
        $mutex = New-Object System.Threading.Mutex($false, $taskLocksMutexName)
        $acquired = $false
        while (-not $acquired) {
            try {
                $acquired = $mutex.WaitOne($RetryMs)
            } catch [System.Threading.AbandonedMutexException] {
                $acquired = $true
            }
            if ($acquired) { break }
            if ($sw.ElapsedMilliseconds -ge $TimeoutMs) {
                throw "Timeout acquiring TASK-LOCKS mutex."
            }
        }
        return & $Script
    } finally {
        if ($mutex) {
            try { $mutex.ReleaseMutex() | Out-Null } catch {}
            try { $mutex.Dispose() } catch {}
        }
    }
}

function Update-TaskLocksData([scriptblock]$Mutator) {
    return Invoke-WithTaskLocksMutex {
        $latest = Read-TaskLocks
        if (-not $latest.locks) {
            $latest | Add-Member -NotePropertyName locks -NotePropertyValue @{} -Force
        }
        $result = & $Mutator $latest
        Write-TaskLocks $latest
        return $result
    }
}

function New-TaskRunId([string]$TaskId, [string]$Phase) {
    return ("RUN-" + (Get-Date -Format "yyyyMMddHHmmssfff") + "-" + $TaskId + "-" + $Phase + "-" + (Get-Random -Minimum 1000 -Maximum 9999))
}

function Read-TaskAttemptHistory {
    $default = @{ version = "1.0"; updated_at = (Get-Date -Format "o"); attempts = @() }
    if (-not (Test-Path $taskAttemptHistoryPath)) {
        return $default
    }
    try {
        $raw = Get-Content $taskAttemptHistoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $raw.attempts) {
            $raw | Add-Member -NotePropertyName attempts -NotePropertyValue @() -Force
        }
        if (-not $raw.version) {
            $raw | Add-Member -NotePropertyName version -NotePropertyValue "1.0" -Force
        }
        return $raw
    } catch {
        return $default
    }
}

function Write-TaskAttemptHistory($data) {
    if (-not $data.version) {
        $data.version = "1.0"
    }
    if (-not $data.attempts) {
        $data.attempts = @()
    }
    $data.updated_at = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    $json = ($data | ConvertTo-Json -Depth 12)
    Write-Utf8NoBomFile -path $taskAttemptHistoryPath -content $json
}

function Get-TaskAttemptList($history) {
    if (-not $history -or -not $history.attempts) { return @() }
    return @($history.attempts)
}

function New-TaskAttemptId([string]$TaskId, [string]$Phase) {
    return ("ATT-" + (Get-Date -Format "yyyyMMddHHmmssfff") + "-" + $TaskId + "-" + $Phase + "-" + (Get-Random -Minimum 1000 -Maximum 9999))
}

function Resolve-PhaseFromWorkerName([string]$WorkerName) {
    if (-not $WorkerName) { return $null }
    if ($WorkerName -match '-qa(?:-\d+)?$') { return "qa" }
    if ($WorkerName -match '-dev(?:-\d+)?$') { return "dev" }
    return $null
}

function Get-TaskLatestRouteWorker($lock) {
    if (-not $lock) { return "" }
    if ($lock.PSObject.Properties.Name -contains "routeUpdate" -and $lock.routeUpdate -and $lock.routeUpdate.worker) {
        return [string]$lock.routeUpdate.worker
    }
    return ""
}

function Get-TaskLatestActivityUtc($lock) {
    if (-not $lock) { return $null }
    if ($lock.PSObject.Properties.Name -contains "routeUpdate" -and $lock.routeUpdate -and $lock.routeUpdate.timestamp) {
        $routeUtc = ConvertTo-UtcDateSafe $lock.routeUpdate.timestamp
        if ($routeUtc) { return $routeUtc }
    }
    if ($lock.updated_at) {
        return ConvertTo-UtcDateSafe $lock.updated_at
    }
    return $null
}

function Get-TaskActivityAgeText($ActivityUtc) {
    if (-not $ActivityUtc) { return "-" }
    $span = ((Get-Date).ToUniversalTime() - $ActivityUtc)
    if ($span.TotalMinutes -lt 1) { return "<1m" }
    if ($span.TotalHours -lt 1) { return ([int][Math]::Floor($span.TotalMinutes)).ToString() + "m" }
    if ($span.TotalDays -lt 1) { return ([int][Math]::Floor($span.TotalHours)).ToString() + "h" }
    return ([int][Math]::Floor($span.TotalDays)).ToString() + "d"
}

function Get-StaleRunThresholdMinutes {
    return Get-EnvIntOrDefault -name "TEAMLEAD_STALE_RUN_MINUTES" -defaultValue 30
}

function Add-TaskAttemptRecord {
    param(
        [string]$TaskId,
        [ValidateSet("dev", "qa")]
        [string]$Phase,
        [string]$Worker,
        [string]$Engine,
        [string]$RunId,
        [string]$DispatchAction,
        [string]$StartedAt
    )

    $history = Read-TaskAttemptHistory
    $attempts = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-TaskAttemptList $history)) {
        $attempts.Add($item) | Out-Null
    }

    if (-not $StartedAt) {
        $StartedAt = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    }

    $entry = [ordered]@{
        attempt_id = (New-TaskAttemptId -TaskId $TaskId -Phase $Phase)
        task_id = $TaskId
        phase = $Phase
        worker = $Worker
        engine = $Engine
        dispatch_action = $DispatchAction
        run_id = $RunId
        started_at = $StartedAt
        ended_at = ""
        result = "running"
        final_state = ""
        requeue_reason = ""
        updated_by = "teamlead-control/" + $DispatchAction
    }

    $attempts.Add([pscustomobject]$entry) | Out-Null
    $history.attempts = @($attempts.ToArray())
    Write-TaskAttemptHistory $history
    return [pscustomobject]$entry
}

function Update-LatestTaskAttempt {
    param(
        [string]$TaskId,
        [string]$Phase,
        [string]$Result,
        [string]$FinalState,
        [string]$EndedAt,
        [string]$RequeueReason,
        [string]$UpdatedBy
    )

    $history = Read-TaskAttemptHistory
    $attempts = @(Get-TaskAttemptList $history)
    $changed = $false

    for ($i = $attempts.Count - 1; $i -ge 0; $i--) {
        $attempt = $attempts[$i]
        if (-not $attempt) { continue }
        if ([string]$attempt.task_id -ne $TaskId) { continue }
        if ($Phase -and [string]$attempt.phase -ne $Phase) { continue }

        if ($Result) { $attempt.result = $Result }
        if ($FinalState) { $attempt.final_state = $FinalState }
        if ($EndedAt) { $attempt.ended_at = $EndedAt }
        if ($RequeueReason) { $attempt.requeue_reason = $RequeueReason }
        if ($UpdatedBy) { $attempt.updated_by = $UpdatedBy }
        $changed = $true
        break
    }

    if ($changed) {
        $history.attempts = $attempts
        Write-TaskAttemptHistory $history
    }
    return $changed
}

function Sync-TaskAttemptHistoryFromLocks([string]$TaskId = "") {
    $locks = Read-TaskLocks
    $history = Read-TaskAttemptHistory
    $attempts = @(Get-TaskAttemptList $history)
    if ($attempts.Count -eq 0) {
        return $history
    }

    $changed = $false
    $lockNames = @($locks.locks.PSObject.Properties.Name)
    foreach ($tid in $lockNames) {
        if ($TaskId -and $tid -ne $TaskId) { continue }
        $lock = $locks.locks.$tid
        if (-not $lock) { continue }

        $state = if ($lock.state) { ([string]$lock.state).ToLower() } else { "" }
        $routeWorker = Get-TaskLatestRouteWorker -lock $lock
        $phase = Resolve-PhaseFromWorkerName -WorkerName $routeWorker
        if (-not $phase) {
            $phase = Resolve-PhaseFromWorkerName -WorkerName (Get-AssignedWorkerFromLock -TaskId $tid -lock $lock -State $state -WorkerMap (Get-WorkerMap))
        }

        $result = ""
        switch ($state) {
            "waiting_qa" {
                $phase = "dev"
                $result = "success"
            }
            "qa_passed" {
                $phase = "qa"
                $result = "success"
            }
            "completed" {
                if ($phase -eq "qa") {
                    $result = "success"
                }
            }
            "blocked" {
                if (-not $phase) { $phase = "dev" }
                $result = "blocked"
            }
        }

        if (-not $phase -or -not $result) { continue }
        $endedAt = if ($lock.updated_at) { [string]$lock.updated_at } else { (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz") }

        for ($i = $attempts.Count - 1; $i -ge 0; $i--) {
            $attempt = $attempts[$i]
            if (-not $attempt) { continue }
            if ([string]$attempt.task_id -ne $tid) { continue }
            if ([string]$attempt.phase -ne $phase) { continue }

            $attemptResult = if ($attempt.result) { [string]$attempt.result } else { "" }
            if ($attemptResult -notin @("running", "stale")) { break }

            $attempt.result = $result
            $attempt.final_state = $state
            $attempt.ended_at = $endedAt
            $attempt.updated_by = "teamlead-control/sync"
            $changed = $true
            break
        }
    }

    if ($changed) {
        $history.attempts = $attempts
        Write-TaskAttemptHistory $history
    }
    return $history
}

function Get-LatestTaskAttemptSummary([string]$TaskId, [string]$Phase = "") {
    $history = Read-TaskAttemptHistory
    $attempts = @(Get-TaskAttemptList $history)
    for ($i = $attempts.Count - 1; $i -ge 0; $i--) {
        $attempt = $attempts[$i]
        if (-not $attempt) { continue }
        if ([string]$attempt.task_id -ne $TaskId) { continue }
        if ($Phase -and [string]$attempt.phase -ne $Phase) { continue }
        return $attempt
    }
    return $null
}

function Set-NoteField($obj, [string]$value) {
    if (-not $obj) { return }
    if (-not $obj.PSObject.Properties['note']) {
        $obj | Add-Member -NotePropertyName note -NotePropertyValue $value -Force
    } else {
        $obj.note = $value
    }
}

function Set-ObjectField($obj, [string]$name, $value) {
    if (-not $obj -or -not $name) { return }
    if (-not $obj.PSObject.Properties[$name]) {
        $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
    } else {
        $obj.$name = $value
    }
}

function Enter-DispatchMutex() {
    try {
        $m = New-Object System.Threading.Mutex($false, $dispatchMutexName)
        $acquired = $false
        try {
            $acquired = $m.WaitOne(0)
        } catch [System.Threading.AbandonedMutexException] {
            $acquired = $true
        }
        if (-not $acquired) {
            Write-Host '[FAIL] Another dispatch/dispatch-qa action is already running.' -ForegroundColor Red
            Write-Host '       Rule: Team Lead must run dispatch commands serially (one-by-one).' -ForegroundColor Yellow
            Write-Host '       Multi-worker parallelism is handled by worker pool assignment, not concurrent dispatch commands.' -ForegroundColor DarkGray
            exit 1
        }
        return $m
    } catch {
        # 如果互斥锁不可用，继续执行但给出告警，避免硬阻塞主流程
        Write-Host '[WARN] Dispatch mutex unavailable; continuing without inter-process lock.' -ForegroundColor Yellow
        return $null
    }
}

function Read-ArchiveJobs {
    $default = @{ version = "1.0"; updated_at = (Get-Date -Format "o"); jobs = @{} }
    if (-not (Test-Path $archiveJobsPath)) {
        return $default
    }
    try {
        $raw = Get-Content $archiveJobsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $state = @{
            version = if ($raw.version) { [string]$raw.version } else { "1.0" }
            updated_at = if ($raw.updated_at) { [string]$raw.updated_at } else { (Get-Date -Format "o") }
            jobs = Convert-ToArchiveJobMap $raw.jobs
        }
        return $state
    } catch {
        return $default
    }
}

function Write-ArchiveJobs($data) {
    if (-not $data.version) { $data.version = "1.0" }
    $data.jobs = Convert-ToArchiveJobMap $data.jobs
    $data.updated_at = Get-Date -Format "o"
    $json = ($data | ConvertTo-Json -Depth 12)
    Write-Utf8NoBomFile -path $archiveJobsPath -content $json
}

function Convert-ToArchiveJobMap($jobsObj) {
    $map = @{}
    if ($null -eq $jobsObj) { return $map }

    if ($jobsObj -is [System.Collections.IDictionary]) {
        foreach ($k in $jobsObj.Keys) {
            $name = [string]$k
            if ($name -match '^ARCHIVE-[A-Z0-9\-]+$') {
                $map[$name] = $jobsObj[$k]
            }
        }
        return $map
    }

    foreach ($p in $jobsObj.PSObject.Properties) {
        $name = [string]$p.Name
        if ($name -match '^ARCHIVE-[A-Z0-9\-]+$') {
            $map[$name] = $p.Value
        }
    }
    return $map
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
    if (-not (Test-Path $docSyncStatePath)) {
        return $default
    }
    try {
        $raw = Get-Content $docSyncStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
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
        Write-Host ('[WARN] Invalid api-doc-sync-state.json, fallback to default: ' + $docSyncStatePath) -ForegroundColor Yellow
        return $default
    }
}

function Get-TaskDependenciesFromFile([string]$TaskFilePath, [string]$CurrentTaskId) {
    if (-not (Test-Path $TaskFilePath)) { return @() }
    $raw = Get-Content $TaskFilePath -Raw -Encoding UTF8
    $lines = @($raw -split "(`r`n|`n)")
    $depLines = @($lines | Where-Object { $_ -match "前置依赖|Dependencies|depends on" })
    if ($depLines.Count -eq 0) { return @() }

    $collector = New-Object System.Collections.Generic.List[string]
    foreach ($line in $depLines) {
        $matches = [regex]::Matches($line.ToUpper(), '[A-Z]+(?:-[A-Z]+)?-\d+')
        foreach ($m in $matches) {
            $depId = $m.Value.Trim().ToUpper()
            if ($depId -and $depId -ne $CurrentTaskId.ToUpper() -and -not $collector.Contains($depId)) {
                $collector.Add($depId) | Out-Null
            }
        }
    }
    return @($collector.ToArray())
}

function Test-TaskArchivedInCompleted([string]$TaskId) {
    $completedRoot = Join-Path $rootDir "01-tasks\completed"
    if (-not (Test-Path $completedRoot)) { return $false }
    $matches = @(Get-ChildItem -Path "$completedRoot\*\$TaskId*.md" -File -ErrorAction SilentlyContinue)
    return ($matches.Count -gt 0)
}

function Assert-DependenciesReady([string]$TaskId, [string[]]$Dependencies, $locks) {
    if (-not $Dependencies -or $Dependencies.Count -eq 0) { return }

    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($depId in $Dependencies) {
        if ($locks.locks.PSObject.Properties.Name -notcontains $depId) {
            if (Test-TaskArchivedInCompleted -TaskId $depId) {
                continue
            }
            $errors.Add($depId + ": missing in TASK-LOCKS.json and not found in completed") | Out-Null
            continue
        }
        $depLock = $locks.locks.$depId
        $depState = if ($depLock -and $depLock.state) { [string]$depLock.state } else { "" }
        if ($depState -notin @("completed", "qa_passed")) {
            if (Test-TaskArchivedInCompleted -TaskId $depId) {
                continue
            }
            $errors.Add($depId + ": state=" + $depState + " (required: completed|qa_passed)") | Out-Null
        }
    }

    if ($errors.Count -gt 0) {
        Write-Host ('[FAIL] Dependency gate blocked dispatch for ' + $TaskId) -ForegroundColor Red
        foreach ($err in $errors) {
            Write-Host ('  - ' + $err) -ForegroundColor Yellow
        }
        Write-Host ('  Resolve dependencies first, then rerun dispatch for ' + $TaskId) -ForegroundColor DarkGray
        exit 1
    }
}

function Trigger-BackendDocUpdater([string]$BackendTaskId, [string]$TeamLeadPaneId, [switch]$SkipTrigger) {
    if ($SkipTrigger) { return }
    $triggerScript = Join-Path $scriptDir "trigger-doc-updater.ps1"
    if (-not (Test-Path $triggerScript)) {
        Write-Host '[WARN] trigger-doc-updater.ps1 not found, cannot auto trigger doc sync.' -ForegroundColor Yellow
        return
    }
    try {
        & $triggerScript -TaskId $BackendTaskId -TeamLeadPaneId $TeamLeadPaneId -Reason backend_qa -Force | Out-Null
        Write-Host ('[INFO] Auto-triggered doc-updater for backend dependency ' + $BackendTaskId) -ForegroundColor Cyan
    } catch {
        Write-Host ('[WARN] Failed to auto-trigger doc-updater for ' + $BackendTaskId + ': ' + $_.Exception.Message) -ForegroundColor Yellow
    }
}

function Assert-FrontendDocSyncReady([string]$TaskId, [string[]]$Dependencies, [string]$TeamLeadPaneId, [switch]$SkipAutoTrigger) {
    $backendDeps = @($Dependencies | Where-Object { $_ -match '^BACKEND-\d+$' })
    if ($backendDeps.Count -eq 0) { return }

    $syncState = Read-DocSyncState
    $issues = New-Object System.Collections.Generic.List[string]
    foreach ($backendTaskId in $backendDeps) {
        $entry = $null
        if ($syncState.backend.ContainsKey($backendTaskId)) {
            $entry = $syncState.backend[$backendTaskId]
        }
        if (-not $entry) {
            $issues.Add($backendTaskId + ": no doc sync record (api-doc-sync-state.json)") | Out-Null
            Trigger-BackendDocUpdater -BackendTaskId $backendTaskId -TeamLeadPaneId $TeamLeadPaneId -SkipTrigger:$SkipAutoTrigger
            continue
        }

        $docStatus = if ($entry.doc_sync_status) { [string]$entry.doc_sync_status } else { "" }
        if ($docStatus -ne "synced") {
            $issues.Add($backendTaskId + ": doc_sync_status=" + $docStatus + " (required: synced)") | Out-Null
            Trigger-BackendDocUpdater -BackendTaskId $backendTaskId -TeamLeadPaneId $TeamLeadPaneId -SkipTrigger:$SkipAutoTrigger
            continue
        }

        $qaAt = ConvertTo-UtcDateSafe $entry.qa_completed_at
        $syncedAt = ConvertTo-UtcDateSafe $entry.doc_synced_at
        if ($qaAt -and $syncedAt -and $syncedAt -lt $qaAt) {
            $issues.Add($backendTaskId + ": doc_synced_at older than qa_completed_at") | Out-Null
            Trigger-BackendDocUpdater -BackendTaskId $backendTaskId -TeamLeadPaneId $TeamLeadPaneId -SkipTrigger:$SkipAutoTrigger
        }
    }

    if ($issues.Count -gt 0) {
        Write-Host ('[FAIL] API doc freshness gate blocked frontend dispatch for ' + $TaskId) -ForegroundColor Red
        foreach ($issue in $issues) {
            Write-Host ('  - ' + $issue) -ForegroundColor Yellow
        }
        Write-Host '  Action: wait doc-updater success for backend dependencies, then re-dispatch.' -ForegroundColor DarkGray
        exit 1
    }
}

function Read-ApprovalRequests {
    if (-not (Test-Path $approvalRequestsPath)) {
        return @{ version = "1.0"; updated_at = (Get-Date -Format "o"); requests = @() }
    }
    try {
        $raw = Get-Content $approvalRequestsPath -Raw -Encoding UTF8
        $parsed = $raw | ConvertFrom-Json
        if (-not $parsed.requests) {
            $parsed | Add-Member -NotePropertyName requests -NotePropertyValue @() -Force
        }
        return $parsed
    } catch {
        Write-Host ('[FAIL] Invalid approval requests file: ' + $approvalRequestsPath) -ForegroundColor Red
        exit 1
    }
}

function Write-ApprovalRequests($data) {
    $data.updated_at = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    $json = ($data | ConvertTo-Json -Depth 10)
    Write-Utf8NoBomFile -path $approvalRequestsPath -content $json
}

function Get-EnvIntOrDefault([string]$name, [int]$defaultValue) {
    $raw = [System.Environment]::GetEnvironmentVariable($name)
    if (-not $raw) { return $defaultValue }
    $parsed = 0
    if ([int]::TryParse($raw, [ref]$parsed) -and $parsed -gt 0) {
        return $parsed
    }
    return $defaultValue
}

function ConvertTo-UtcDateSafe($value) {
    if (-not $value) { return $null }
    try {
        return ([DateTimeOffset]::Parse($value.ToString())).UtcDateTime
    } catch {
        return $null
    }
}

function Cleanup-ExpiredApprovalRequests {
    param([switch]$Persist)

    $ttlSeconds = Get-EnvIntOrDefault -name "APPROVAL_REQUEST_TTL_SECONDS" -defaultValue 600
    $retentionHours = Get-EnvIntOrDefault -name "APPROVAL_RESOLVED_RETENTION_HOURS" -defaultValue 168

    $approvals = Read-ApprovalRequests
    if (-not $approvals.requests) {
        $approvals.requests = @()
    }

    $nowUtc = (Get-Date).ToUniversalTime()
    $changed = $false
    $expired = 0
    $stalePending = 0
    $pruned = 0
    $kept = New-Object System.Collections.Generic.List[object]

    foreach ($req in @($approvals.requests)) {
        $status = if ($null -eq $req.status) { "" } else { [string]$req.status }

        # NOTE:
        # pending 请求不能在 Team Lead 侧“静默过期”，否则 worker 仍停在审批交互里。
        # 这里仅统计 stale pending，真正超时拒绝由 approval-router 负责向 worker 发送 n。
        if ($status -eq "pending" -and $ttlSeconds -gt 0) {
            $createdUtc = ConvertTo-UtcDateSafe $req.created_at
            if ($createdUtc) {
                $ageSec = ($nowUtc - $createdUtc).TotalSeconds
                if ($ageSec -ge $ttlSeconds) {
                    $stalePending++
                }
            }
        }

        if ($status -eq "resolved" -and $retentionHours -gt 0) {
            $resolvedUtc = ConvertTo-UtcDateSafe $req.resolved_at
            if ($resolvedUtc) {
                $ageHours = ($nowUtc - $resolvedUtc).TotalHours
                if ($ageHours -ge $retentionHours) {
                    $pruned++
                    $changed = $true
                    continue
                }
            }
        }

        $kept.Add($req) | Out-Null
    }

    if ($changed) {
        $approvals.requests = @($kept.ToArray())
        if ($Persist) {
            Write-ApprovalRequests $approvals
        }
    }

    return @{
        data = $approvals
        expired = $expired
        pruned = $pruned
        changed = $changed
        ttl_seconds = $ttlSeconds
        retention_hours = $retentionHours
        stale_pending = $stalePending
    }
}

function Send-ApprovalDecisionToPane($paneId, $decision, $promptType) {
    $ptype = if ($promptType) { [string]$promptType } else { "command_approval" }
    if ($ptype -eq "edit_confirm") {
        if ($decision -eq 'approve') {
            wezterm cli send-text --pane-id $paneId --no-paste "`r" | Out-Null
            return ($LASTEXITCODE -eq 0)
        }
        wezterm cli send-text --pane-id $paneId --no-paste "`e" | Out-Null
        return ($LASTEXITCODE -eq 0)
    }

    $key = if ($decision -eq 'approve') { 'y' } else { 'n' }
    wezterm cli send-text --pane-id $paneId --no-paste $key | Out-Null
    if ($LASTEXITCODE -ne 0) {
        return $false
    }
    Start-Sleep -Milliseconds 200
    wezterm cli send-text --pane-id $paneId --no-paste "`r" | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Resolve-WorkerPaneByName([string]$workerName) {
    if (-not $workerName) { return $null }
    try { Reconcile-WorkerRegistryFromPanes | Out-Null } catch {}
    $regScript = Join-Path $scriptDir "worker-registry.ps1"
    if (-not (Test-Path $regScript)) { return $null }
    try {
        $paneId = & $regScript -Action get -WorkerName $workerName 2>$null
        if ($paneId) { return $paneId.ToString().Trim() }
    } catch {}
    return $null
}

function Get-WeztermPanes {
    try {
        $raw = wezterm cli list --format json 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Read-WorkerRegistryData {
    if (-not (Test-Path $registryPath)) {
        return @{ updated_at = (Get-Date -Format "o"); workers = @{} }
    }
    try {
        $raw = Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $raw.workers) {
            $raw | Add-Member -NotePropertyName workers -NotePropertyValue @{} -Force
        }
        return $raw
    } catch {
        return @{ updated_at = (Get-Date -Format "o"); workers = @{} }
    }
}

function Write-WorkerRegistryData($data) {
    $data.updated_at = Get-Date -Format "o"
    $json = ($data | ConvertTo-Json -Depth 10)
    Write-Utf8NoBomFile -path $registryPath -content $json
}

function Get-KnownWorkersFromMap($workerMap) {
    $known = @{}
    if (-not $workerMap) { return $known }
    foreach ($prefixProp in $workerMap.PSObject.Properties) {
        $cfg = $prefixProp.Value
        if (-not $cfg) { continue }
        $devEngine = if ($cfg.dev_engine) { [string]$cfg.dev_engine } else { [string]$cfg.engine }
        foreach ($w in @(Get-WorkerListForPhase -cfg $cfg -phase "dev")) {
            if (-not $w) { continue }
            $known[[string]$w] = @{
                work_dir = [string]$cfg.workdir
                engine = $devEngine
            }
        }

        $qaEngine = if ($cfg.qa_engine) { [string]$cfg.qa_engine } else { [string]$cfg.engine }
        foreach ($w in @(Get-WorkerListForPhase -cfg $cfg -phase "qa")) {
            if (-not $w) { continue }
            $known[[string]$w] = @{
                work_dir = [string]$cfg.workdir
                engine = $qaEngine
            }
        }
    }
    return $known
}

function Reconcile-WorkerRegistryFromPanes {
    $panes = Get-WeztermPanes
    if (-not $panes) { return $false }

    $workerMap = $null
    try { $workerMap = Get-WorkerMap } catch { return $false }
    $knownWorkers = Get-KnownWorkersFromMap -workerMap $workerMap
    if ($knownWorkers.Keys.Count -eq 0) { return $false }

    $registry = Read-WorkerRegistryData
    $workers = @{}
    if ($registry.workers) {
        foreach ($p in $registry.workers.PSObject.Properties) {
            $workers[$p.Name] = $p.Value
        }
    }

    $changed = $false
    foreach ($pane in $panes) {
        $paneId = if ($pane.pane_id) { [string]$pane.pane_id } else { "" }
        if (-not $paneId) { continue }

        $titles = @()
        foreach ($field in @("tab_title", "title", "window_title")) {
            if ($pane.PSObject.Properties.Name -contains $field) {
                $v = [string]$pane.$field
                if ($v) { $titles += $v }
            }
        }
        if ($titles.Count -eq 0) { continue }

        foreach ($workerName in $knownWorkers.Keys) {
            $match = $false
            $escapedWorker = [regex]::Escape([string]$workerName)
            $workerPattern = "(^|[^A-Za-z0-9\-])" + $escapedWorker + "([^A-Za-z0-9\-]|$)"
            foreach ($t in $titles) {
                if ([regex]::IsMatch([string]$t, $workerPattern)) {
                    $match = $true
                    break
                }
            }
            if (-not $match) { continue }

            $cfg = $knownWorkers[$workerName]
            if ($workers.ContainsKey($workerName)) {
                $entry = $workers[$workerName]
                $existingPane = if ($entry.pane_id) { [string]$entry.pane_id } else { "" }
                if ($existingPane -ne $paneId) {
                    $entry.pane_id = $paneId
                    $changed = $true
                }
                $entry.status = "active"
                $entry.last_seen = Get-Date -Format "o"
                if (-not $entry.registered_at) {
                    $entry.registered_at = Get-Date -Format "o"
                }
                if ($cfg.work_dir) { $entry.work_dir = $cfg.work_dir }
                if ($cfg.engine) { $entry.engine = $cfg.engine }
                $workers[$workerName] = $entry
            } else {
                $workers[$workerName] = @{
                    pane_id = $paneId
                    work_dir = $cfg.work_dir
                    engine = $cfg.engine
                    registered_at = Get-Date -Format "o"
                    last_seen = Get-Date -Format "o"
                    status = "active"
                }
                $changed = $true
            }
        }
    }

    if ($changed) {
        $registry.workers = $workers
        Write-WorkerRegistryData $registry
    }
    return $changed
}

function Read-ApprovalRouterPidStore {
    if (-not (Test-Path $approvalRouterPidFile)) {
        return @{ updated_at = (Get-Date -Format "o"); routers = @{} }
    }
    try {
        $raw = Get-Content $approvalRouterPidFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $raw.routers) {
            $raw | Add-Member -NotePropertyName routers -NotePropertyValue @{} -Force
        }
        return $raw
    } catch {
        return @{ updated_at = (Get-Date -Format "o"); routers = @{} }
    }
}

function Convert-ToRouterEntryMap($routersObj) {
    $map = @{}
    if ($null -eq $routersObj) { return $map }

    if ($routersObj -is [System.Collections.IDictionary]) {
        foreach ($k in $routersObj.Keys) {
            $name = [string]$k
            if ($name -and $name -match '\|') {
                $map[$name] = $routersObj[$k]
            }
        }
        return $map
    }

    foreach ($p in $routersObj.PSObject.Properties) {
        $name = [string]$p.Name
        if ($name -and $name -match '\|') {
            $map[$name] = $p.Value
        }
    }
    return $map
}

function Write-ApprovalRouterPidStore($data) {
    $data.updated_at = Get-Date -Format "o"
    $json = ($data | ConvertTo-Json -Depth 10)
    Write-Utf8NoBomFile -path $approvalRouterPidFile -content $json
}

function Get-LivePaneIdSet {
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    $panes = Get-WeztermPanes
    if (-not $panes) { return $set }
    foreach ($pane in $panes) {
        $paneIdStr = if ($pane.pane_id) { [string]$pane.pane_id } else { "" }
        if ($paneIdStr) { [void]$set.Add($paneIdStr) }
    }
    return $set
}

function Cleanup-StaleApprovalRouters([string]$KeepTaskId = "", [string]$KeepWorkerName = "", [switch]$Verbose) {
    $store = Read-ApprovalRouterPidStore
    $routers = Convert-ToRouterEntryMap $store.routers
    if ($routers.Keys.Count -eq 0) {
        return @{ removed = 0; killed = 0; kept = 0 }
    }

    $livePanes = Get-LivePaneIdSet
    $keepKey = ""
    if ($KeepTaskId -and $KeepWorkerName) {
        $keepKey = ($KeepTaskId + "|" + $KeepWorkerName).ToUpper()
    }
    $keepWorkerUpper = if ($KeepWorkerName) { $KeepWorkerName.ToUpper() } else { "" }

    $nextRouters = @{}
    $removed = 0
    $killed = 0
    $kept = 0

    foreach ($name in $routers.Keys) {
        $entry = $routers[$name]
        $routerPid = 0
        $pidStr = if ($entry.pid) { [string]$entry.pid } else { "" }
        $proc = $null
        $alive = $false
        if ([int]::TryParse($pidStr, [ref]$routerPid) -and $routerPid -gt 0) {
            $proc = Get-Process -Id $routerPid -ErrorAction SilentlyContinue
            $alive = ($null -ne $proc)
        }

        $paneId = if ($entry.worker_pane_id) { [string]$entry.worker_pane_id } else { "" }
        $paneAlive = $false
        if ($paneId -and $livePanes) {
            try { $paneAlive = [bool]$livePanes.Contains($paneId) } catch { $paneAlive = $false }
        }
        $entryWorkerUpper = if ($entry.worker) { ([string]$entry.worker).ToUpper() } else { "" }
        $sameWorkerDifferentTask = ($keepWorkerUpper -and $entryWorkerUpper -eq $keepWorkerUpper -and $name -ne $keepKey)

        $drop = (-not $alive) -or (-not $paneAlive) -or $sameWorkerDifferentTask
        if ($drop) {
            if ($alive -and $routerPid -gt 0) {
                Stop-Process -Id $routerPid -Force -ErrorAction SilentlyContinue
                $killed++
            }
            $removed++
            if ($Verbose) {
                Write-Host ('[INFO] Removed stale approval-router: ' + $name + ' pid=' + $pidStr + ' pane=' + $paneId) -ForegroundColor DarkGray
            }
            continue
        }

        $nextRouters[$name] = $entry
        $kept++
    }

    if ($removed -gt 0) {
        $store.routers = $nextRouters
        Write-ApprovalRouterPidStore $store
    }

    return @{
        removed = $removed
        killed = $killed
        kept = $kept
    }
}

function Ensure-ApprovalRouter([string]$TaskId, [string]$WorkerName, [string]$WorkerPaneId, [string]$TeamLeadPaneId) {
    $routerScript = Join-Path $scriptDir "approval-router.ps1"
    if (-not (Test-Path $routerScript)) {
        Write-Host '[WARN] approval-router.ps1 not found, skip auto start' -ForegroundColor Yellow
        return
    }

    $key = ($TaskId + "|" + $WorkerName).ToUpper()
    $store = Read-ApprovalRouterPidStore
    $routers = Convert-ToRouterEntryMap $store.routers

    $needStart = $true
    if ($routers.ContainsKey($key)) {
        $existing = $routers[$key]
        $existingPid = 0
        $pidStr = if ($existing.pid) { [string]$existing.pid } else { "" }
        if ([int]::TryParse($pidStr, [ref]$existingPid) -and $existingPid -gt 0) {
            $proc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
            if ($proc) {
                $samePane = ([string]$existing.worker_pane_id -eq [string]$WorkerPaneId)
                $sameTl = ([string]$existing.team_lead_pane_id -eq [string]$TeamLeadPaneId)
                if ($samePane -and $sameTl) {
                    $needStart = $false
                    Write-Host ('[OK] approval-router running (PID ' + $existingPid + ', task=' + $TaskId + ', worker=' + $WorkerName + ')') -ForegroundColor Green
                } else {
                    Stop-Process -Id $existingPid -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    if (-not $needStart) { return }

    $proc = Start-Process powershell -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$routerScript,"-WorkerPaneId",$WorkerPaneId,"-WorkerName",$WorkerName,"-TaskId",$TaskId,"-TeamLeadPaneId",$TeamLeadPaneId,"-Timeout","0","-Continuous" -WindowStyle Hidden -PassThru
    $routers[$key] = @{
        pid = $proc.Id
        task = $TaskId
        worker = $WorkerName
        worker_pane_id = $WorkerPaneId
        team_lead_pane_id = $TeamLeadPaneId
        started_at = Get-Date -Format "o"
    }
    $store.routers = $routers
    Write-ApprovalRouterPidStore $store
    Write-Host ('[OK] approval-router started (PID ' + $proc.Id + ', task=' + $TaskId + ', worker=' + $WorkerName + ')') -ForegroundColor Green
}

function Convert-CommandOutputToJson($output) {
    if ($null -eq $output) { return $null }
    $lines = @()
    if ($output -is [System.Array]) {
        $lines = @($output | ForEach-Object { [string]$_ })
    } else {
        $lines = @(([string]$output) -split "`r?`n")
    }
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i].Trim()
        if (-not $line) { continue }
        if ($line.StartsWith("{") -or $line.StartsWith("[")) {
            try {
                return ($line | ConvertFrom-Json)
            } catch {}
        }
    }
    return $null
}

function Assert-TaskState($tid, [string[]]$allowedStates, $locks) {
    $lock = $null
    if ($locks.locks.PSObject.Properties.Name -contains $tid) {
        $lock = $locks.locks.$tid
    }
    if (-not $lock) {
        Write-Host ('[FAIL] Task ' + $tid + ' not in TASK-LOCKS.json. Create lock first.') -ForegroundColor Red
        exit 1
    }
    if ($lock.state -notin $allowedStates) {
        $st = $lock.state
        $allowed = $allowedStates -join ', '
        $suggestedTarget = if ($allowedStates -contains "waiting_qa") {
            "waiting_qa"
        } elseif ($allowedStates -contains "assigned") {
            "assigned"
        } elseif ($allowedStates.Count -gt 0) {
            [string]$allowedStates[0]
        } else {
            "assigned"
        }
        Write-Host ('[FAIL] Task ' + $tid + " state='" + $st + "' not allowed.") -ForegroundColor Red
        Write-Host ('       Allowed: ' + $allowed) -ForegroundColor Yellow
        Write-Host ('       Next: powershell -File scripts/teamlead-control.ps1 -Action requeue -TaskId ' + $tid + ' -TargetState ' + $suggestedTarget + ' -RequeueReason "manual_requeue"') -ForegroundColor DarkGray
        if ($suggestedTarget -eq "waiting_qa") {
            Write-Host ('       Then: powershell -File scripts/teamlead-control.ps1 -Action dispatch-qa -TaskId ' + $tid) -ForegroundColor DarkGray
        } elseif ($suggestedTarget -eq "assigned") {
            Write-Host ('       Then: powershell -File scripts/teamlead-control.ps1 -Action dispatch -TaskId ' + $tid) -ForegroundColor DarkGray
        }
        exit 1
    }
    return $lock
}

function Get-WorkerMap {
    if (-not (Test-Path $workerMapPath)) {
        Write-Host ('[FAIL] worker-map.json not found: ' + $workerMapPath) -ForegroundColor Red
        exit 1
    }
    return Get-Content $workerMapPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-RegisteredWorkerEngine([string]$WorkerName) {
    if (-not $WorkerName) { return $null }
    if (-not (Test-Path $registryPath)) { return $null }
    try {
        $reg = Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $reg -or -not $reg.workers) { return $null }
        foreach ($prop in $reg.workers.PSObject.Properties) {
            if ($prop.Name -eq $WorkerName) {
                if ($prop.Value -and $prop.Value.engine) {
                    return ([string]$prop.Value.engine).Trim()
                }
                return $null
            }
        }
    } catch {}
    return $null
}

function Ensure-WorkerRunning($wName, $wConfig, $tlPaneId, [switch]$ForceRestart) {
    $regScript = Join-Path $scriptDir "worker-registry.ps1"
    $existingPane = $null
    try {
        $existingPane = & $regScript -Action get -WorkerName $wName 2>$null
        if ($existingPane -and $LASTEXITCODE -eq 0 -and -not $ForceRestart) {
            Write-Host ('[OK] Worker ' + $wName + ' online (pane ' + $existingPane + ')') -ForegroundColor Green
            return $existingPane
        }
    } catch {}

    if ($ForceRestart) {
        if ($existingPane) {
            Write-Host ('[INFO] Worker ' + $wName + ' force restart for fresh context (old pane ' + $existingPane + ')') -ForegroundColor Yellow
            try {
                wezterm cli kill-pane --pane-id $existingPane 2>$null | Out-Null
                Start-Sleep -Milliseconds 300
                $paneStillAlive = $false
                try {
                    $panes = Get-WeztermPanes
                    if ($panes) {
                        $paneStillAlive = @($panes | Where-Object { ([string]$_.pane_id) -eq ([string]$existingPane) }).Count -gt 0
                    }
                } catch {}
                if ($paneStillAlive) {
                    Write-Host ('[WARN] Failed to close old pane ' + $existingPane + ' for ' + $wName + ', continue with unregister/start.') -ForegroundColor Yellow
                } else {
                    Write-Host ('[OK] Closed old pane ' + $existingPane + ' for ' + $wName) -ForegroundColor Green
                }
            } catch {
                Write-Host ('[WARN] kill-pane error for old pane ' + $existingPane + ' (' + $_.Exception.Message + ')') -ForegroundColor Yellow
            }
        } else {
            Write-Host ('[INFO] Worker ' + $wName + ' fresh context requested, starting new session...') -ForegroundColor Yellow
        }
        try { & $regScript -Action unregister -WorkerName $wName *> $null } catch {}
    }

    Write-Host ('[INFO] Worker ' + $wName + ' offline, starting...') -ForegroundColor Yellow
    $startScript = Join-Path $scriptDir "start-worker.ps1"
    & $startScript -WorkDir $wConfig.workdir -WorkerName $wName -Engine $wConfig.engine -TeamLeadPaneId $tlPaneId

    Start-Sleep -Seconds 3
    try {
        $paneId = & $regScript -Action get -WorkerName $wName 2>$null
        if ($paneId) { return $paneId }
    } catch {}

    Write-Host ('[FAIL] Worker ' + $wName + ' failed to start') -ForegroundColor Red
    exit 1
}

function Ensure-RouteMonitor($tlPaneId) {
    $monitorRunning = $false
    if (Test-Path $monitorPidFile) {
        $savedPid = (Get-Content $monitorPidFile -Raw).Trim()
        try {
            $proc = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
            $monitorRunning = ($null -ne $proc)
        } catch {}
        if (-not $monitorRunning) {
            Remove-Item $monitorPidFile -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $monitorRunning) {
        Write-Host '[INFO] Starting route-monitor...' -ForegroundColor Yellow
        $monitorScript = Join-Path $scriptDir "route-monitor.ps1"
        if (Test-Path $monitorScript) {
            $proc = Start-Process powershell -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$monitorScript,"-Continuous","-TeamLeadPaneId",$tlPaneId -WindowStyle Hidden -PassThru
            Set-Content $monitorPidFile $proc.Id -Force
            $monPid = $proc.Id
            Write-Host ('[OK] route-monitor started (PID ' + $monPid + ')') -ForegroundColor Green
        } else {
            Write-Host '[WARN] route-monitor.ps1 not found, skipping' -ForegroundColor Yellow
        }
    } else {
        Write-Host ('[OK] route-monitor running (PID ' + $savedPid + ')') -ForegroundColor Green
    }
}

function Test-WorkerPaneAlive([string]$WorkerName) {
    if (-not $WorkerName) { return $false }
    $regScript = Join-Path $scriptDir "worker-registry.ps1"
    if (-not (Test-Path $regScript)) { return $false }
    try {
        & $regScript -Action get -WorkerName $WorkerName *> $null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Run-WorkerRegistryHealthCheck {
    try { Reconcile-WorkerRegistryFromPanes | Out-Null } catch {}
    $regScript = Join-Path $scriptDir "worker-registry.ps1"
    if (-not (Test-Path $regScript)) { return }
    try {
        & $regScript -Action health-check *> $null
    } catch {}
}

function Get-WorkerListForPhase($cfg, [string]$phase) {
    $list = New-Object System.Collections.Generic.List[string]
    if (-not $cfg) { return @() }

    $poolKey = if ($phase -eq "qa") { "qa_pool" } else { "dev_pool" }
    $singleKey = if ($phase -eq "qa") { "qa" } else { "dev" }

    if ($cfg.PSObject.Properties.Name -contains $poolKey -and $cfg.$poolKey) {
        foreach ($w in @($cfg.$poolKey)) {
            $name = [string]$w
            if ($name -and -not $list.Contains($name)) {
                $list.Add($name) | Out-Null
            }
        }
    }
    if ($list.Count -eq 0 -and $cfg.PSObject.Properties.Name -contains $singleKey -and $cfg.$singleKey) {
        $name = [string]$cfg.$singleKey
        if ($name) { $list.Add($name) | Out-Null }
    }
    return @($list.ToArray())
}

function Get-ExpectedWorkersForTaskState([string]$TaskId, [string]$State, $WorkerMap) {
    if (-not $TaskId -or -not $State -or -not $WorkerMap) { return $null }
    $prefix = Resolve-TaskPrefix $TaskId
    if (-not $prefix) { return @() }
    $cfg = $WorkerMap.$prefix
    if (-not $cfg) { return @() }
    switch ($State) {
        "in_progress" { return @(Get-WorkerListForPhase -cfg $cfg -phase "dev") }
        "qa" { return @(Get-WorkerListForPhase -cfg $cfg -phase "qa") }
        default { return @() }
    }
}

function Get-ExpectedWorkerForTaskState([string]$TaskId, [string]$State, $WorkerMap) {
    $workers = @(Get-ExpectedWorkersForTaskState -TaskId $TaskId -State $State -WorkerMap $WorkerMap)
    if ($workers.Count -gt 0) { return [string]$workers[0] }
    return $null
}

function Get-AssignedWorkerFromLock([string]$TaskId, $lock, [string]$State, $WorkerMap) {
    if (-not $lock) { return $null }

    if ($lock.PSObject.Properties.Name -contains "assigned_worker") {
        $aw = [string]$lock.assigned_worker
        if ($aw) { return $aw }
    }
    if ($lock.PSObject.Properties.Name -contains "worker") {
        $w = [string]$lock.worker
        if ($w) { return $w }
    }
    if ($lock.PSObject.Properties.Name -contains "routeUpdate" -and $lock.routeUpdate) {
        $rw = if ($lock.routeUpdate.worker) { [string]$lock.routeUpdate.worker } else { "" }
        if ($rw) { return $rw }
    }
    return Get-ExpectedWorkerForTaskState -TaskId $TaskId -State $State -WorkerMap $WorkerMap
}

function Select-WorkerForDispatch([string]$TaskId, [string]$TargetState, $cfg, $locks, $workerMap) {
    $phase = if ($TargetState -eq "qa") { "qa" } else { "dev" }
    $candidates = @(Get-WorkerListForPhase -cfg $cfg -phase $phase)
    if ($candidates.Count -eq 0) {
        Write-Host ('[FAIL] No worker configured for phase=' + $phase + ' task=' + $TaskId) -ForegroundColor Red
        exit 1
    }

    $busy = New-Object 'System.Collections.Generic.HashSet[string]'
    if ($locks -and $locks.locks) {
        foreach ($p in $locks.locks.PSObject.Properties) {
            $otherTaskId = [string]$p.Name
            if (-not $otherTaskId -or $otherTaskId -eq $TaskId) { continue }
            $entry = $p.Value
            if (-not $entry) { continue }
            $state = if ($entry.state) { [string]$entry.state } else { "" }
            if ($state -ne $TargetState) { continue }
            $assigned = Get-AssignedWorkerFromLock -TaskId $otherTaskId -lock $entry -State $state -WorkerMap $workerMap
            if ($assigned) { [void]$busy.Add($assigned) }
        }
    }

    foreach ($w in $candidates) {
        if (-not $busy.Contains([string]$w)) {
            return [string]$w
        }
    }

    Write-Host ('[FAIL] Worker pool exhausted for ' + $TaskId + ' state=' + $TargetState + '; busy=' + (($busy | Sort-Object) -join ', ')) -ForegroundColor Red
    Write-Host ('       Candidates: ' + ($candidates -join ', ')) -ForegroundColor Yellow
    Write-Host '       Wait one task to finish or expand worker-map dev_pool/qa_pool.' -ForegroundColor Yellow
    exit 1
}

function Assert-NoExecutionDrift([string]$TaskId, $locks, $WorkerMap) {
    if (-not $TaskId -or -not $locks -or -not $WorkerMap) { return }
    if ($locks.locks.PSObject.Properties.Name -notcontains $TaskId) { return }
    $lock = $locks.locks.$TaskId
    if (-not $lock) { return }

    $state = if ($lock.state) { [string]$lock.state } else { "" }
    if ($state -notin @("in_progress", "qa")) { return }

    $assignedWorker = Get-AssignedWorkerFromLock -TaskId $TaskId -lock $lock -State $state -WorkerMap $WorkerMap
    if ($assignedWorker -and (Test-WorkerPaneAlive -WorkerName $assignedWorker)) { return }

    $expectedWorkers = @(Get-ExpectedWorkersForTaskState -TaskId $TaskId -State $state -WorkerMap $WorkerMap)
    foreach ($w in $expectedWorkers) {
        if (Test-WorkerPaneAlive -WorkerName $w) { return }
    }

    $displayWorker = if ($assignedWorker) { $assignedWorker } elseif ($expectedWorkers.Count -gt 0) { ($expectedWorkers -join '|') } else { 'unknown' }
    Write-Host ('[FAIL] Execution drift detected: task ' + $TaskId + ' state=' + $state + ' but worker offline (' + $displayWorker + ')') -ForegroundColor Red
    Write-Host '       This usually happens when worker pane was closed manually.' -ForegroundColor Yellow
    Write-Host '       Recover with:' -ForegroundColor Yellow
    Write-Host ('         powershell -NoProfile -ExecutionPolicy Bypass -File "' + $scriptDir + '\teamlead-control.ps1" -Action recover -RecoverAction reap-stale') -ForegroundColor White
    Write-Host ('         powershell -NoProfile -ExecutionPolicy Bypass -File "' + $scriptDir + '\teamlead-control.ps1" -Action recover -RecoverAction reset-task -TaskId ' + $TaskId + ' -TargetState assigned') -ForegroundColor White
    if ($assignedWorker) {
        Write-Host ('         powershell -NoProfile -ExecutionPolicy Bypass -File "' + $scriptDir + '\teamlead-control.ps1" -Action recover -RecoverAction restart-worker -WorkerName ' + $assignedWorker) -ForegroundColor White
    }
    exit 1
}

function Assert-WorkerNotBusy([string]$TaskId, [string]$TargetWorker, [string]$TargetState, $locks, $WorkerMap) {
    if (-not $TaskId -or -not $TargetWorker -or -not $TargetState -or -not $locks -or -not $WorkerMap) { return }
    if (-not $locks.locks) { return }

    $conflicts = New-Object System.Collections.Generic.List[string]
    foreach ($p in $locks.locks.PSObject.Properties) {
        $otherTaskId = [string]$p.Name
        if (-not $otherTaskId -or $otherTaskId -eq $TaskId) { continue }
        $entry = $p.Value
        if (-not $entry) { continue }
        $state = if ($entry.state) { [string]$entry.state } else { "" }
        if ($state -ne $TargetState) { continue }

        $assignedWorker = Get-AssignedWorkerFromLock -TaskId $otherTaskId -lock $entry -State $state -WorkerMap $WorkerMap
        if ($assignedWorker -and $assignedWorker -eq $TargetWorker) {
            $conflicts.Add($otherTaskId) | Out-Null
        }
    }

    if ($conflicts.Count -eq 0) { return }

    $conflictList = @($conflicts.ToArray()) | Sort-Object
    $stateLabel = if ($TargetState -eq "qa") { "QA" } else { "DEV" }
    Write-Host ('[FAIL] Worker busy: ' + $TargetWorker + ' already has active ' + $stateLabel + ' task(s): ' + ($conflictList -join ', ')) -ForegroundColor Red
    Write-Host '       Current controller supports one active task per worker session.' -ForegroundColor Yellow
    Write-Host '       Resolve by waiting current task to finish, or complete/recover stale lock first.' -ForegroundColor Yellow
    Write-Host '       Quick check:' -ForegroundColor Yellow
    Write-Host ('         powershell -NoProfile -ExecutionPolicy Bypass -File "' + $scriptDir + '\teamlead-control.ps1" -Action status') -ForegroundColor White
    exit 1
}

# ============================================================
# Action: bootstrap
# ============================================================
function Invoke-Bootstrap {
    Write-Host ''
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host '  Team Lead Bootstrap' -ForegroundColor Cyan
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host ''

    $tlPaneId = Resolve-TeamLeadPaneId
    Write-Host ('[OK] Team Lead Pane ID: ' + $tlPaneId) -ForegroundColor Green

    # Doctor diagnostics
    Write-Host ''
    Write-Host '--- Doctor Diagnostics ---' -ForegroundColor Cyan
    try {
        python "$rootDir\scripts\assign_task.py" --doctor
    } catch {
        Write-Host '[WARN] doctor check failed, continuing...' -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host '--- Worker Registry Health Check ---' -ForegroundColor Cyan
    try { Reconcile-WorkerRegistryFromPanes | Out-Null } catch {}
    $regScript = Join-Path $scriptDir "worker-registry.ps1"
    if (Test-Path $regScript) {
        & $regScript -Action health-check
    }

    Write-Host ''
    Write-Host '--- MCP Route Inbox ---' -ForegroundColor Cyan
    $inboxPath = Join-Path $rootDir "mcp\route-server\data\route-inbox.json"
    if (Test-Path $inboxPath) {
        Write-Host '[OK] Route inbox exists' -ForegroundColor Green
    } else {
        Write-Host '[INFO] Route inbox will be created on first report_route call' -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host '--- Route Monitor ---' -ForegroundColor Cyan
    Ensure-RouteMonitor $tlPaneId

    Set-Content $bootstrapFlag ('bootstrapped=' + (Get-Date -Format 'o')) -Force
    Write-Host ''
    Write-Host '[OK] Bootstrap flag written' -ForegroundColor Green

    # Standard entry - show execution/planning mode
    Write-Host ''
    Write-Host '--- Standard Entry ---' -ForegroundColor Cyan
    try {
        python "$rootDir\scripts\assign_task.py" --standard-entry
    } catch {
        Write-Host '[WARN] standard-entry check failed, continuing...' -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host '==========================================' -ForegroundColor Green
    Write-Host '  Bootstrap Complete' -ForegroundColor Green
    Write-Host '==========================================' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Available actions:' -ForegroundColor Cyan
    Write-Host '  dispatch    -- powershell -File scripts/teamlead-control.ps1 -Action dispatch -TaskId <ID> [-DispatchEngine codex|gemini]' -ForegroundColor White
    Write-Host '  dispatch-qa -- powershell -File scripts/teamlead-control.ps1 -Action dispatch-qa -TaskId <ID> [-DispatchEngine codex|gemini]' -ForegroundColor White
    Write-Host '  status      -- powershell -File scripts/teamlead-control.ps1 -Action status' -ForegroundColor White
    Write-Host '  requeue     -- powershell -File scripts/teamlead-control.ps1 -Action requeue -TaskId <ID> -TargetState <assigned|waiting_qa> -RequeueReason "..."' -ForegroundColor White
    Write-Host '  recover     -- powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction <action>' -ForegroundColor White
    Write-Host '  archive     -- powershell -File scripts/teamlead-control.ps1 -Action archive -TaskId <ID> [-NoPush] [-CommitMessage "..."]' -ForegroundColor White
    Write-Host '  approve-request -- powershell -File scripts/teamlead-control.ps1 -Action approve-request -RequestId <ID>' -ForegroundColor White
    Write-Host '  deny-request    -- powershell -File scripts/teamlead-control.ps1 -Action deny-request -RequestId <ID>' -ForegroundColor White
    Write-Host ''
    Write-Host 'Approval Priority Rule:' -ForegroundColor Cyan
    Write-Host '  If pending approval requests exist, do NOT run sleep/wait. Approve or deny first.' -ForegroundColor Yellow
    Write-Host '  baseline-clean is now manual-only; run recover -RecoverAction baseline-clean only when you explicitly want cleanup.' -ForegroundColor DarkGray
    Write-Host '  dispatch-qa defaults to fresh QA context (set TEAMLEAD_QA_REUSE_CONTEXT=1 to reuse QA session).' -ForegroundColor DarkGray
    Write-Host '  review reject should use requeue only; do not send reject reason directly into the old worker pane.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'Dispatch Rule:' -ForegroundColor Cyan
    Write-Host '  Team Lead must execute dispatch/dispatch-qa serially (one command at a time).' -ForegroundColor Yellow
    Write-Host '  Do NOT run two dispatch commands concurrently in parallel shells.' -ForegroundColor Yellow
    Write-Host '  True worker parallelism is provided by worker pool auto-assignment (e.g. shop-fe-dev + shop-fe-dev-2).' -ForegroundColor DarkGray
    Write-Host '  Engine can be overridden per dispatch via -DispatchEngine codex|gemini.' -ForegroundColor DarkGray
    Write-Host ''
}

# ============================================================
# Action: dispatch (dev task)
# ============================================================
function Invoke-Dispatch {
    if (-not $TaskId) {
        Write-Host '[FAIL] dispatch requires -TaskId' -ForegroundColor Red
        exit 1
    }
    Assert-CanonicalTaskId $TaskId

    $tlPaneId = Resolve-TeamLeadPaneId
    Write-Host '[INFO] Pre-dispatch baseline-clean is disabled by default; controller will preserve pending routes/approvals unless you run recover -RecoverAction baseline-clean manually.' -ForegroundColor DarkGray

    $workerMap = Get-WorkerMap
    $locks = Read-TaskLocks
    Assert-NoInvalidTaskLockEntries $locks
    Run-WorkerRegistryHealthCheck
    Sync-TaskAttemptHistoryFromLocks -TaskId $TaskId | Out-Null

    # P0-1: Resolve prefix
    $prefix = Resolve-TaskPrefix $TaskId
    if (-not $prefix) {
        Write-Host ('[FAIL] Unknown task prefix: ' + $TaskId) -ForegroundColor Red
        Write-Host '       Supported: BACKEND, SHOP-FE, ADMIN-FE' -ForegroundColor Yellow
        exit 1
    }

    $wConfig = $workerMap.$prefix
    if (-not $wConfig) {
        Write-Host ('[FAIL] No config for prefix ' + $prefix + ' in worker-map.json') -ForegroundColor Red
        exit 1
    }

    $devWorker = Select-WorkerForDispatch -TaskId $TaskId -TargetState "in_progress" -cfg $wConfig -locks $locks -workerMap $workerMap
    $domain = $wConfig.domain
    Assert-NoExecutionDrift -TaskId $TaskId -locks $locks -WorkerMap $workerMap

    # Assert state (only assigned/blocked -> in_progress)
    Assert-TaskState $TaskId @("assigned", "blocked") $locks
    Assert-WorkerNotBusy -TaskId $TaskId -TargetWorker $devWorker -TargetState "in_progress" -locks $locks -WorkerMap $workerMap

    # P0-4: Unique task file validation
    $taskDir = Join-Path $rootDir "01-tasks\active\$domain"
    $taskFiles = Get-ChildItem -Path "$taskDir\$TaskId*.md" -ErrorAction SilentlyContinue

    if ($taskFiles.Count -eq 0) {
        Write-Host ('[FAIL] Task file not found: ' + $TaskId + ' (dir: 01-tasks/active/' + $domain + '/)') -ForegroundColor Red
        exit 1
    }
    if ($taskFiles.Count -gt 1) {
        Write-Host '[FAIL] Multiple task files matched:' -ForegroundColor Red
        $taskFiles | ForEach-Object { $fn = $_.Name; Write-Host ('  - ' + $fn) -ForegroundColor Yellow }
        exit 1
    }
    $taskFile = $taskFiles[0]
    Write-Host ('[OK] Task file: ' + $taskFile.Name) -ForegroundColor Green

    $dependencies = @(Get-TaskDependenciesFromFile -TaskFilePath $taskFile.FullName -CurrentTaskId $TaskId)
    if ($dependencies.Count -gt 0) {
        Write-Host ('[OK] Dependency check: ' + ($dependencies -join ', ')) -ForegroundColor Cyan
    } else {
        Write-Host '[OK] Dependency check: no explicit prerequisites' -ForegroundColor DarkGray
    }
    Assert-DependenciesReady -TaskId $TaskId -Dependencies $dependencies -locks $locks
    if ($prefix -in @("SHOP-FE", "ADMIN-FE")) {
        Assert-FrontendDocSyncReady -TaskId $TaskId -Dependencies $dependencies -TeamLeadPaneId $tlPaneId -SkipAutoTrigger:$DryRun
    }

    # DryRun check
    if ($DryRun) {
        Write-Host ''
        Write-Host '[DRY-RUN] Would dispatch:' -ForegroundColor Magenta
        Write-Host ('  Task:   ' + $TaskId) -ForegroundColor White
        Write-Host ('  Worker: ' + $devWorker) -ForegroundColor White
        Write-Host ('  File:   ' + $taskFile.Name) -ForegroundColor White
        Write-Host ('  Domain: ' + $domain) -ForegroundColor White
        Write-Host '[DRY-RUN] No changes made.' -ForegroundColor Magenta
        return
    }

    # Ensure worker is running
    $defaultDevEngine = if ($wConfig.dev_engine) { [string]$wConfig.dev_engine } else { [string]$wConfig.engine }
    $devEngine = if ($DispatchEngine) { [string]$DispatchEngine } else { $defaultDevEngine }
    $runId = New-TaskRunId -TaskId $TaskId -Phase "dev"
    if ($DispatchEngine) {
        Write-Host ('[INFO] Engine override: ' + $defaultDevEngine + ' -> ' + $devEngine) -ForegroundColor Cyan
    }
    $devConfig = @{ workdir = $wConfig.workdir; engine = $devEngine }
    $registeredDevEngine = Get-RegisteredWorkerEngine -WorkerName $devWorker
    $forceRestartForEngine = $false
    if ($registeredDevEngine -and $registeredDevEngine.ToLowerInvariant() -ne $devEngine.ToLowerInvariant()) {
        Write-Host ('[INFO] Worker ' + $devWorker + ' engine mismatch (' + $registeredDevEngine + ' -> ' + $devEngine + '), forcing restart...') -ForegroundColor Yellow
        $forceRestartForEngine = $true
    }
    $paneId = Ensure-WorkerRunning $devWorker $devConfig $tlPaneId -ForceRestart:$forceRestartForEngine

    # 先确保监控已启动，避免 dispatch 阶段出现审批提示但无人接管
    Ensure-RouteMonitor $tlPaneId
    Ensure-ApprovalRouter -TaskId $TaskId -WorkerName $devWorker -WorkerPaneId $paneId -TeamLeadPaneId $tlPaneId

    # Dispatch task (BEFORE updating lock)
    $dispatchScript = Join-Path $scriptDir "dispatch-task.ps1"
    & $dispatchScript -WorkerPaneId $paneId -WorkerName $devWorker -TaskId $TaskId -TaskFilePath $taskFile.FullName -Engine $devEngine -TeamLeadPaneId $tlPaneId -RunId $runId
    $dispatchExit = $LASTEXITCODE
    if ($dispatchExit -ne 0) {
        Write-Host ('[FAIL] Dispatch failed for ' + $TaskId + ' (worker=' + $devWorker + ', pane=' + $paneId + ', exit=' + $dispatchExit + ')') -ForegroundColor Red
        Write-Host '       Task lock not updated. Please check worker pane output and rerun dispatch.' -ForegroundColor Yellow
        exit 1
    }

    # Update task lock AFTER successful dispatch
    $dispatchUpdatedAt = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    Update-TaskLocksData {
        param($latestLocks)
        if ($latestLocks.locks.PSObject.Properties.Name -notcontains $TaskId) {
            throw ("Task lock missing during dispatch commit: " + $TaskId)
        }
        $latestLock = $latestLocks.locks.$TaskId
        $latestState = if ($latestLock.state) { [string]$latestLock.state } else { "" }
        if ($latestState -notin @("assigned", "blocked")) {
            throw ("Task state drifted before dispatch commit: " + $TaskId + " state=" + $latestState)
        }
        $latestLock.state = "in_progress"
        $latestLock.runner = $devEngine
        Set-ObjectField -obj $latestLock -name "assigned_worker" -value $devWorker
        Set-ObjectField -obj $latestLock -name "run_id" -value $runId
        $latestLock.updated_at = $dispatchUpdatedAt
        $latestLock.updated_by = "teamlead-control/dispatch"
    } | Out-Null
    Add-TaskAttemptRecord -TaskId $TaskId -Phase "dev" -Worker $devWorker -Engine $devEngine -RunId $runId -DispatchAction "dispatch" -StartedAt $dispatchUpdatedAt | Out-Null

    # Ensure route monitor is alive for auto lock/doc-updater processing
    Ensure-RouteMonitor $tlPaneId
    Ensure-ApprovalRouter -TaskId $TaskId -WorkerName $devWorker -WorkerPaneId $paneId -TeamLeadPaneId $tlPaneId

    Write-Host ''
    Write-Host ('[OK] Task ' + $TaskId + ' dispatched to ' + $devWorker + ' (pane ' + $paneId + ')') -ForegroundColor Green
    Write-Host ''
    Write-Host '[NEXT] Background watchers:' -ForegroundColor Cyan
    Write-Host '  route-monitor: auto ensured by controller' -ForegroundColor White
    Write-Host '  approval-router: auto ensured by controller' -ForegroundColor White
    Write-Host '  route-watcher: optional (notification trigger only)' -ForegroundColor DarkGray
    Write-Host '  dispatch/dispatch-qa commands must still be serial from Team Lead side (no parallel command launch).' -ForegroundColor Yellow
    $watcherCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\route-watcher.ps1" -FilterTask ' + $TaskId + ' -Timeout 0'
    Write-Host ('  Optional Bash(run_in_background: true): ' + $watcherCmd) -ForegroundColor DarkGray
    $approvalCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\approval-router.ps1" -WorkerPaneId ' + $paneId + ' -WorkerName ' + $devWorker + ' -TaskId ' + $TaskId + ' -TeamLeadPaneId ' + $tlPaneId + ' -Timeout 0 -Continuous'
    Write-Host ('  (debug manual start): ' + $approvalCmd) -ForegroundColor DarkGray
    Write-Host ''
}

# ============================================================
# Action: dispatch-qa
# ============================================================
function Invoke-DispatchQA {
    if (-not $TaskId) {
        Write-Host '[FAIL] dispatch-qa requires -TaskId' -ForegroundColor Red
        exit 1
    }
    Assert-CanonicalTaskId $TaskId

    $tlPaneId = Resolve-TeamLeadPaneId
    Write-Host '[INFO] Pre-dispatch baseline-clean is disabled by default; controller will preserve pending routes/approvals unless you run recover -RecoverAction baseline-clean manually.' -ForegroundColor DarkGray

    $workerMap = Get-WorkerMap
    $locks = Read-TaskLocks
    Assert-NoInvalidTaskLockEntries $locks
    Run-WorkerRegistryHealthCheck
    Sync-TaskAttemptHistoryFromLocks -TaskId $TaskId | Out-Null

    $prefix = Resolve-TaskPrefix $TaskId
    if (-not $prefix) {
        Write-Host ('[FAIL] Unknown task prefix: ' + $TaskId) -ForegroundColor Red
        exit 1
    }

    $wConfig = $workerMap.$prefix
    $qaWorker = Select-WorkerForDispatch -TaskId $TaskId -TargetState "qa" -cfg $wConfig -locks $locks -workerMap $workerMap
    $domain = $wConfig.domain
    Assert-NoExecutionDrift -TaskId $TaskId -locks $locks -WorkerMap $workerMap

    # Assert state (only waiting_qa -> qa)
    Assert-TaskState $TaskId @("waiting_qa") $locks
    Assert-WorkerNotBusy -TaskId $TaskId -TargetWorker $qaWorker -TargetState "qa" -locks $locks -WorkerMap $workerMap

    # P0-4: Task file validation
    $taskDir = Join-Path $rootDir "01-tasks\active\$domain"
    $taskFiles = Get-ChildItem -Path "$taskDir\$TaskId*.md" -ErrorAction SilentlyContinue
    if ($taskFiles.Count -eq 0) {
        Write-Host ('[FAIL] Task file not found: ' + $TaskId) -ForegroundColor Red
        exit 1
    }
    if ($taskFiles.Count -gt 1) {
        Write-Host '[FAIL] Multiple task files matched:' -ForegroundColor Red
        $taskFiles | ForEach-Object { $fn = $_.Name; Write-Host ('  - ' + $fn) -ForegroundColor Yellow }
        exit 1
    }
    $taskFile = $taskFiles[0]

    # DryRun check
    if ($DryRun) {
        Write-Host ''
        Write-Host '[DRY-RUN] Would dispatch QA:' -ForegroundColor Magenta
        Write-Host ('  Task:   ' + $TaskId) -ForegroundColor White
        Write-Host ('  Worker: ' + $qaWorker) -ForegroundColor White
        Write-Host ('  File:   ' + $taskFile.Name) -ForegroundColor White
        Write-Host '[DRY-RUN] No changes made.' -ForegroundColor Magenta
        return
    }

    $defaultQaEngine = if ($wConfig.qa_engine) { [string]$wConfig.qa_engine } else { [string]$wConfig.engine }
    $qaEngine = if ($DispatchEngine) { [string]$DispatchEngine } else { $defaultQaEngine }
    $runId = New-TaskRunId -TaskId $TaskId -Phase "qa"
    if ($DispatchEngine) {
        Write-Host ('[INFO] Engine override: ' + $defaultQaEngine + ' -> ' + $qaEngine) -ForegroundColor Cyan
    }
    $qaConfig = @{ workdir = $wConfig.workdir; engine = $qaEngine }
    $reuseQaContext = [System.Environment]::GetEnvironmentVariable("TEAMLEAD_QA_REUSE_CONTEXT")
    $forceFreshQaContext = (-not $reuseQaContext -or $reuseQaContext.Trim() -ne "1")
    if ($forceFreshQaContext) {
        Write-Host '[INFO] QA dispatch uses fresh worker context (set TEAMLEAD_QA_REUSE_CONTEXT=1 to reuse existing QA session).' -ForegroundColor Cyan
    }
    $registeredQaEngine = Get-RegisteredWorkerEngine -WorkerName $qaWorker
    $forceRestartForEngine = $false
    if ($registeredQaEngine -and $registeredQaEngine.ToLowerInvariant() -ne $qaEngine.ToLowerInvariant()) {
        Write-Host ('[INFO] Worker ' + $qaWorker + ' engine mismatch (' + $registeredQaEngine + ' -> ' + $qaEngine + '), forcing restart...') -ForegroundColor Yellow
        $forceRestartForEngine = $true
    }
    $forceRestartQa = $forceFreshQaContext -or $forceRestartForEngine
    $paneId = Ensure-WorkerRunning $qaWorker $qaConfig $tlPaneId -ForceRestart:$forceRestartQa

    # 先确保监控已启动，避免 dispatch 阶段出现审批提示但无人接管
    Ensure-RouteMonitor $tlPaneId
    Ensure-ApprovalRouter -TaskId $TaskId -WorkerName $qaWorker -WorkerPaneId $paneId -TeamLeadPaneId $tlPaneId

    # Dispatch FIRST, then update lock
    $dispatchScript = Join-Path $scriptDir "dispatch-task.ps1"
    & $dispatchScript -WorkerPaneId $paneId -WorkerName $qaWorker -TaskId $TaskId -TaskFilePath $taskFile.FullName -Engine $qaEngine -TeamLeadPaneId $tlPaneId -RunId $runId
    $dispatchExit = $LASTEXITCODE
    if ($dispatchExit -ne 0) {
        Write-Host ('[FAIL] Dispatch QA failed for ' + $TaskId + ' (worker=' + $qaWorker + ', pane=' + $paneId + ', exit=' + $dispatchExit + ')') -ForegroundColor Red
        Write-Host '       Task lock not updated. Please check worker pane output and rerun dispatch-qa.' -ForegroundColor Yellow
        exit 1
    }

    # Update task lock AFTER successful dispatch
    $dispatchUpdatedAt = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    Update-TaskLocksData {
        param($latestLocks)
        if ($latestLocks.locks.PSObject.Properties.Name -notcontains $TaskId) {
            throw ("Task lock missing during QA dispatch commit: " + $TaskId)
        }
        $latestLock = $latestLocks.locks.$TaskId
        $latestState = if ($latestLock.state) { [string]$latestLock.state } else { "" }
        if ($latestState -ne "waiting_qa") {
            throw ("Task state drifted before dispatch-qa commit: " + $TaskId + " state=" + $latestState)
        }
        $latestLock.state = "qa"
        $latestLock.runner = $qaEngine
        Set-ObjectField -obj $latestLock -name "assigned_worker" -value $qaWorker
        Set-ObjectField -obj $latestLock -name "run_id" -value $runId
        $latestLock.updated_at = $dispatchUpdatedAt
        $latestLock.updated_by = "teamlead-control/dispatch-qa"
    } | Out-Null
    Add-TaskAttemptRecord -TaskId $TaskId -Phase "qa" -Worker $qaWorker -Engine $qaEngine -RunId $runId -DispatchAction "dispatch-qa" -StartedAt $dispatchUpdatedAt | Out-Null

    # Ensure route monitor is alive for auto lock/doc-updater processing
    Ensure-RouteMonitor $tlPaneId
    Ensure-ApprovalRouter -TaskId $TaskId -WorkerName $qaWorker -WorkerPaneId $paneId -TeamLeadPaneId $tlPaneId

    Write-Host ''
    Write-Host ('[OK] QA task ' + $TaskId + ' dispatched to ' + $qaWorker + ' (pane ' + $paneId + ')') -ForegroundColor Green
    Write-Host ''
    Write-Host '[NEXT] Background watchers:' -ForegroundColor Cyan
    Write-Host '  route-monitor: auto ensured by controller' -ForegroundColor White
    Write-Host '  approval-router: auto ensured by controller' -ForegroundColor White
    Write-Host '  route-watcher: optional (notification trigger only)' -ForegroundColor DarkGray
    Write-Host '  dispatch/dispatch-qa commands must still be serial from Team Lead side (no parallel command launch).' -ForegroundColor Yellow
    $watcherCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\route-watcher.ps1" -FilterTask ' + $TaskId + ' -Timeout 0'
    Write-Host ('  Optional Bash(run_in_background: true): ' + $watcherCmd) -ForegroundColor DarkGray
    $approvalCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\approval-router.ps1" -WorkerPaneId ' + $paneId + ' -WorkerName ' + $qaWorker + ' -TaskId ' + $TaskId + ' -TeamLeadPaneId ' + $tlPaneId + ' -Timeout 0 -Continuous'
    Write-Host ('  (debug manual start): ' + $approvalCmd) -ForegroundColor DarkGray
    Write-Host ''
}

# ============================================================
# Action: requeue
# ============================================================
function Invoke-Requeue {
    if (-not $TaskId) {
        Write-Host '[FAIL] requeue requires -TaskId' -ForegroundColor Red
        exit 1
    }
    Assert-CanonicalTaskId $TaskId

    if (-not $TargetState) {
        Write-Host '[FAIL] requeue requires -TargetState (assigned / waiting_qa)' -ForegroundColor Red
        exit 1
    }
    if ($TargetState -notin @("assigned", "waiting_qa")) {
        Write-Host ('[FAIL] Invalid requeue target: ' + $TargetState + ' (allowed: assigned / waiting_qa)') -ForegroundColor Red
        exit 1
    }

    if (-not $RequeueReason) {
        $RequeueReason = "manual_requeue"
    }

    $workerMap = Get-WorkerMap
    $locks = Read-TaskLocks
    if ($locks.locks.PSObject.Properties.Name -notcontains $TaskId) {
        Write-Host ('[FAIL] Task ' + $TaskId + ' not in TASK-LOCKS.json') -ForegroundColor Red
        exit 1
    }

    Sync-TaskAttemptHistoryFromLocks -TaskId $TaskId | Out-Null

    $lock = $locks.locks.$TaskId
    $prevState = if ($lock.state) { [string]$lock.state } else { "" }
    $assignedWorker = Get-AssignedWorkerFromLock -TaskId $TaskId -lock $lock -State $prevState -WorkerMap $workerMap
    $workerAlive = if ($assignedWorker) { Test-WorkerPaneAlive -WorkerName $assignedWorker } else { $false }
    $phase = Resolve-PhaseFromWorkerName -WorkerName (Get-TaskLatestRouteWorker -lock $lock)
    if (-not $phase) {
        $phase = Resolve-PhaseFromWorkerName -WorkerName $assignedWorker
    }
    if (-not $phase) {
        $phase = if ($TargetState -eq "waiting_qa") { "qa" } else { "dev" }
    }

    $now = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    Update-TaskLocksData {
        param($latest)
        if ($latest.locks.PSObject.Properties.Name -notcontains $TaskId) {
            throw ("Task missing during requeue commit: " + $TaskId)
        }
        $latestLock = $latest.locks.$TaskId
        $latestLock.state = $TargetState
        $latestLock.updated_at = $now
        $latestLock.updated_by = "teamlead-control/requeue"
        Set-NoteField -obj $latestLock -value ("Requeued to " + $TargetState + " by team lead: " + $RequeueReason)
        Set-ObjectField -obj $latestLock -name "run_id" -value ""
        Set-ObjectField -obj $latestLock -name "last_requeue" -value @{
            previous_state = $prevState
            target_state = $TargetState
            reason = $RequeueReason
            requested_at = $now
            requested_by = "teamlead-control/requeue"
        }
        return $null
    }

    Update-LatestTaskAttempt -TaskId $TaskId -Phase $phase -Result "requeued" -FinalState $TargetState -EndedAt $now -RequeueReason $RequeueReason -UpdatedBy "teamlead-control/requeue" | Out-Null

    Write-Host ('[OK] Task ' + $TaskId + ' requeued: ' + $prevState + ' -> ' + $TargetState) -ForegroundColor Green
    Write-Host ('     Reason: ' + $RequeueReason) -ForegroundColor Gray
    Write-Host '     Requeue only updates status/history. It does not notify the old worker and does not auto-dispatch.' -ForegroundColor Cyan
    if ($workerAlive -and $assignedWorker) {
        Write-Host ('[WARN] Previous worker is still online: ' + $assignedWorker) -ForegroundColor Yellow
        Write-Host '       Do not paste the reject reason into that pane. Redispatch later with a fresh context.' -ForegroundColor Yellow
        if ($TargetState -eq "waiting_qa") {
            Write-Host ('       Next: powershell -File scripts/teamlead-control.ps1 -Action dispatch-qa -TaskId ' + $TaskId) -ForegroundColor White
        } else {
            Write-Host ('       Next: powershell -File scripts/teamlead-control.ps1 -Action dispatch -TaskId ' + $TaskId) -ForegroundColor White
        }
    }
}

# ============================================================
# Action: status
# ============================================================
function Get-TaskRecommendation {
    param(
        [string]$TaskId,
        $Lock,
        $PendingApprovals,
        $WorkerMap,
        $GateContext
    )

    if (-not $Lock) { return $null }

    $state = if ($Lock.state) { ([string]$Lock.state).ToLower() } else { "" }
    $commands = New-Object System.Collections.Generic.List[string]
    $assignedWorker = Get-AssignedWorkerFromLock -TaskId $TaskId -lock $Lock -State $state -WorkerMap $WorkerMap
    $workerAlive = if ($assignedWorker) { Test-WorkerPaneAlive -WorkerName $assignedWorker } else { $false }
    $routeWorker = Get-TaskLatestRouteWorker -lock $Lock
    $phase = Resolve-PhaseFromWorkerName -WorkerName $routeWorker
    if (-not $phase) {
        $phase = Resolve-PhaseFromWorkerName -WorkerName $assignedWorker
    }
    $activityUtc = Get-TaskLatestActivityUtc -lock $Lock
    $activityAgeText = Get-TaskActivityAgeText -ActivityUtc $activityUtc
    $pendingApprovalCount = @($PendingApprovals).Count
    $hasPendingApprovals = ($pendingApprovalCount -gt 0)
    $staleThresholdMinutes = Get-StaleRunThresholdMinutes
    $isStaleRun = $false
    if ($state -in @("in_progress", "qa") -and $workerAlive -and $activityUtc -and -not $hasPendingApprovals) {
        $ageMinutes = ((Get-Date).ToUniversalTime() - $activityUtc).TotalMinutes
        if ($ageMinutes -ge $staleThresholdMinutes) {
            $isStaleRun = $true
        }
    }

    $archiveBlocking = @()
    if ($GateContext) {
        $archiveBlocking += @($GateContext.dispatch_todo | Where-Object { $_ -ne $TaskId })
        $archiveBlocking += @($GateContext.running | Where-Object { $_ -ne $TaskId })
        $archiveBlocking += @($GateContext.other_active | Where-Object { -not $_.StartsWith($TaskId + ":") })
    }

    $summary = ""
    $color = "Gray"
    $priority = 500

    switch ($state) {
        "assigned" {
            $summary = "待派遣开发"
            $color = "Yellow"
            $priority = 60
            $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action dispatch -TaskId ' + $TaskId) | Out-Null
        }
        "waiting_qa" {
            $summary = "待派遣 QA"
            $color = "Cyan"
            $priority = 70
            $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action dispatch-qa -TaskId ' + $TaskId) | Out-Null
        }
        "in_progress" {
            if ($hasPendingApprovals) {
                $summary = "开发中，但有待处理审批"
                $color = "Red"
                $priority = 10
                foreach ($req in @($PendingApprovals)) {
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action approve-request -RequestId ' + [string]$req.id) | Out-Null
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action deny-request -RequestId ' + [string]$req.id) | Out-Null
                }
            } elseif (-not $workerAlive) {
                $summary = "开发执行漂移，worker 已离线"
                $color = "Red"
                $priority = 20
                if ($assignedWorker) {
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-worker -WorkerName ' + $assignedWorker) | Out-Null
                }
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action requeue -TaskId ' + $TaskId + ' -TargetState assigned -RequeueReason "offline_drift"') | Out-Null
            } elseif ($isStaleRun) {
                $summary = "开发长时间无新 route [STALE-RUN " + $activityAgeText + "]"
                $color = "Yellow"
                $priority = 25
                if ($assignedWorker) {
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-worker -WorkerName ' + $assignedWorker) | Out-Null
                }
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action requeue -TaskId ' + $TaskId + ' -TargetState assigned -RequeueReason "stale_run"') | Out-Null
            } else {
                $summary = "开发进行中，等待新 route"
            }
        }
        "qa" {
            if ($hasPendingApprovals) {
                $summary = "QA 中，但有待处理审批"
                $color = "Red"
                $priority = 10
                foreach ($req in @($PendingApprovals)) {
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action approve-request -RequestId ' + [string]$req.id) | Out-Null
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action deny-request -RequestId ' + [string]$req.id) | Out-Null
                }
            } elseif (-not $workerAlive) {
                $summary = "QA 执行漂移，worker 已离线"
                $color = "Red"
                $priority = 20
                if ($assignedWorker) {
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-worker -WorkerName ' + $assignedWorker) | Out-Null
                }
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action requeue -TaskId ' + $TaskId + ' -TargetState waiting_qa -RequeueReason "offline_drift"') | Out-Null
            } elseif ($isStaleRun) {
                $summary = "QA 长时间无新 route [STALE-RUN " + $activityAgeText + "]"
                $color = "Yellow"
                $priority = 25
                if ($assignedWorker) {
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-worker -WorkerName ' + $assignedWorker) | Out-Null
                }
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action requeue -TaskId ' + $TaskId + ' -TargetState waiting_qa -RequeueReason "stale_run"') | Out-Null
            } else {
                $summary = "QA 进行中，等待新 route"
            }
        }
        "qa_passed" {
            if ($archiveBlocking.Count -gt 0) {
                $summary = "QA 已通过，等待其它活跃任务收口后再 archive"
                $color = "Yellow"
                $priority = 80
            } else {
                $summary = "QA 已通过，可复审后 archive"
                $color = "Green"
                $priority = 90
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action archive -TaskId ' + $TaskId) | Out-Null
            }
            $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action requeue -TaskId ' + $TaskId + ' -TargetState waiting_qa -RequeueReason "review_reject"') | Out-Null
        }
        "blocked" {
            if ($hasPendingApprovals) {
                $summary = "blocked，先处理审批"
                $color = "Red"
                $priority = 10
                foreach ($req in @($PendingApprovals)) {
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action approve-request -RequestId ' + [string]$req.id) | Out-Null
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action deny-request -RequestId ' + [string]$req.id) | Out-Null
                }
            } elseif ($phase -eq "qa") {
                $summary = "QA 驳回后待回开发"
                $color = "Red"
                $priority = 30
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action requeue -TaskId ' + $TaskId + ' -TargetState assigned -RequeueReason "qa_reject"') | Out-Null
            } else {
                $summary = "开发 blocked，需人工恢复后再派遣"
                $color = "Red"
                $priority = 35
                if ($assignedWorker) {
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-worker -WorkerName ' + $assignedWorker) | Out-Null
                }
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action requeue -TaskId ' + $TaskId + ' -TargetState assigned -RequeueReason "manual_recovery"') | Out-Null
            }
        }
        "archiving" {
            $summary = "归档链路进行中，等待 doc-updater / repo-committer"
            $color = "Cyan"
            $priority = 110
        }
        "completed" {
            $summary = "已完成"
            $color = "Green"
            $priority = 900
        }
        default {
            $summary = "未知状态，建议人工检查"
            $color = "Yellow"
            $priority = 300
            $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action status') | Out-Null
        }
    }

    return [pscustomobject]@{
        task_id = $TaskId
        state = $state
        summary = $summary
        color = $color
        priority = $priority
        commands = @($commands.ToArray())
        assigned_worker = $assignedWorker
        worker_alive = $workerAlive
        activity_age = $activityAgeText
        stale = $isStaleRun
    }
}

function Invoke-Status {
    Write-Host ''
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host '  Team Lead Status' -ForegroundColor Cyan
    Write-Host '==========================================' -ForegroundColor Cyan
    Sync-TaskAttemptHistoryFromLocks | Out-Null

    # Environment
    Write-Host ''
    Write-Host '--- Environment ---' -ForegroundColor Cyan
    $tlPaneId = $env:TEAM_LEAD_PANE_ID
    if (-not $tlPaneId) {
        try {
            $panes = wezterm cli list --format json 2>$null | ConvertFrom-Json
            $tlPane = $panes | Where-Object { $_.title -like '*claude*' } | Select-Object -First 1
            if ($tlPane) { $tlPaneId = $tlPane.pane_id.ToString() }
        } catch {}
    }
    if ($tlPaneId) {
        Write-Host ('  Team Lead Pane: ' + $tlPaneId) -ForegroundColor Green
    } else {
        Write-Host '  Team Lead Pane: not detected' -ForegroundColor Red
    }

    $flagExists = Test-Path $bootstrapFlag
    if ($flagExists) {
        Write-Host '  Bootstrap: done' -ForegroundColor Green
    } else {
        Write-Host '  Bootstrap: not done' -ForegroundColor Red
    }

    # Workers
    Write-Host ''
    Write-Host '--- Workers ---' -ForegroundColor Cyan
    try { Reconcile-WorkerRegistryFromPanes | Out-Null } catch {}
    $regScript = Join-Path $scriptDir "worker-registry.ps1"
    if (Test-Path $regScript) {
        try { & $regScript -Action list } catch { Write-Host '  (registry list error, run health-check)' -ForegroundColor Yellow }
    }

    # MCP Route Inbox
    Write-Host '--- Route Inbox ---' -ForegroundColor Cyan
    $inboxPath = Join-Path $rootDir "mcp\route-server\data\route-inbox.json"
    $pendingRoutes = @()
    if (Test-Path $inboxPath) {
        $inbox = Get-Content $inboxPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $pending = $inbox.routes | Where-Object { -not $_.processed }
        if ($pending) { $pendingRoutes = @($pending) }
        if ($pending) {
            foreach ($r in $pending) {
                $color = if ($r.status -eq 'success') { 'Green' } elseif ($r.status -eq 'fail') { 'Red' } else { 'Yellow' }
                Write-Host ('  ' + $r.task.PadRight(18) + ' from=' + $r.from + ' status=' + $r.status) -ForegroundColor $color
            }
        } else {
            Write-Host '  (no pending routes)' -ForegroundColor Gray
        }
    } else {
        Write-Host '  (inbox not created yet)' -ForegroundColor Gray
    }

    # Approval requests
    Write-Host '--- Approval Requests ---' -ForegroundColor Cyan
    $cleanupResult = Cleanup-ExpiredApprovalRequests -Persist
    $approvals = $cleanupResult.data
    if ($cleanupResult.changed) {
        Write-Host ('  [auto-cleanup] expired=' + $cleanupResult.expired + ' pruned=' + $cleanupResult.pruned) -ForegroundColor DarkGray
    }
    $pendingApprovals = @(
        $approvals.requests |
        Where-Object { $_.status -eq 'pending' } |
        Sort-Object created_at
    )
    $pendingApprovalsByTask = @{}
    foreach ($req in $pendingApprovals) {
        $reqTask = if ($req.task) { [string]$req.task } elseif ($req.task_id) { [string]$req.task_id } else { "" }
        if (-not $reqTask) { continue }
        if (-not $pendingApprovalsByTask.ContainsKey($reqTask)) {
            $pendingApprovalsByTask[$reqTask] = New-Object System.Collections.Generic.List[object]
        }
        $pendingApprovalsByTask[$reqTask].Add($req) | Out-Null
    }
    if ($pendingApprovals.Count -gt 0) {
        Write-Host '  [CRITICAL] Pending approvals detected. Handle approve/deny before any wait/sleep.' -ForegroundColor Red
        foreach ($req in $pendingApprovals) {
            $reqColor = if ($req.risk -eq 'low') { 'Yellow' } else { 'Red' }
            $reqTask = if ($req.task) { [string]$req.task } elseif ($req.task_id) { [string]$req.task_id } else { "" }
            $reqWorker = if ($req.worker) { [string]$req.worker } elseif ($req.worker_name) { [string]$req.worker_name } else { "" }
            Write-Host ('  ' + $req.id + ' task=' + $reqTask + ' worker=' + $reqWorker + ' risk=' + $req.risk) -ForegroundColor $reqColor
        }
        if ($cleanupResult.stale_pending -gt 0) {
            Write-Host ('  [warn] stale pending approvals: ' + $cleanupResult.stale_pending + ' (waiting router auto-deny or manual approve/deny)') -ForegroundColor Yellow
        }
        Write-Host '  Recovery shortcut:' -ForegroundColor Yellow
        Write-Host '    powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction baseline-clean' -ForegroundColor White
    } else {
        Write-Host '  (no pending approval requests)' -ForegroundColor Gray
    }

    # Task locks
    Write-Host ''
    Write-Host '--- Task Locks ---' -ForegroundColor Cyan
    $locks = Read-TaskLocks
    Run-WorkerRegistryHealthCheck
    $workerMapForStatus = $null
    try { $workerMapForStatus = Get-WorkerMap } catch {}
    $orphanLocks = New-Object System.Collections.Generic.List[string]
    $invalidLocks = New-Object System.Collections.Generic.List[string]
    $taskRecommendations = New-Object System.Collections.Generic.List[object]
    $staleThresholdMinutes = Get-StaleRunThresholdMinutes
    $gate = Get-ArchiveGateContext -locks $locks
    $hasLocks = $false
    if ($locks.locks.PSObject.Properties.Count -gt 0) {
        $locks.locks.PSObject.Properties | ForEach-Object {
            $hasLocks = $true
            $tid = $_.Name
            $l = $_.Value
            $stateColor = switch ($l.state) {
                "completed"   { "Green" }
                "qa_passed"   { "Green" }
                "in_progress" { "Yellow" }
                "waiting_qa"  { "Yellow" }
                "qa"          { "Cyan" }
                "archiving"   { "Cyan" }
                "assigned"    { "White" }
                "blocked"     { "Red" }
                "fail"        { "Red" }
                default       { "Gray" }
            }
            $tidPad = $tid.PadRight(18)
            $lState = $l.state
            $line = '  ' + $tidPad + ' state=' + $lState
            if ($tid -notmatch '^(BACKEND|SHOP-FE|ADMIN-FE)-\d+$') {
                $line += ' [INVALID-TASKID]'
                $stateColor = "Red"
                $invalidLocks.Add($tid) | Out-Null
            }
            if ([string]$lState -in @("in_progress", "qa")) {
                $displayWorker = Get-AssignedWorkerFromLock -TaskId $tid -lock $l -State ([string]$lState) -WorkerMap $workerMapForStatus
                if ($displayWorker) {
                    if (Test-WorkerPaneAlive -WorkerName $displayWorker) {
                        $line += ' worker=' + $displayWorker
                    } else {
                        $line += ' worker=' + $displayWorker + ' [OFFLINE-DRIFT]'
                        $stateColor = "Red"
                        $orphanLocks.Add($tid + '|' + $displayWorker) | Out-Null
                    }
                }
            }
            $activityUtc = Get-TaskLatestActivityUtc -lock $l
            if ($activityUtc) {
                $line += ' last=' + (Get-TaskActivityAgeText -ActivityUtc $activityUtc)
            }
            $recApprovals = @()
            if ($pendingApprovalsByTask.ContainsKey($tid)) {
                $recApprovals = @($pendingApprovalsByTask[$tid].ToArray())
            }
            $recommendation = Get-TaskRecommendation -TaskId $tid -Lock $l -PendingApprovals $recApprovals -WorkerMap $workerMapForStatus -GateContext $gate
            if ($recommendation) {
                if ($recommendation.stale -and $stateColor -notin @("Red")) {
                    $line += ' [STALE-RUN>' + $staleThresholdMinutes + 'm]'
                    $stateColor = "Yellow"
                }
                if ($recommendation.summary) {
                    $line += ' next=' + $recommendation.summary
                }
                if ([string]$recommendation.state -ne "completed") {
                    $taskRecommendations.Add($recommendation) | Out-Null
                }
            }
            Write-Host $line -ForegroundColor $stateColor
        }
    }
    if (-not $hasLocks) {
        Write-Host '  (no task locks)' -ForegroundColor Gray
    }
    if ($orphanLocks.Count -gt 0) {
        Write-Host '  [WARN] Detected execution drift tasks (worker pane offline).' -ForegroundColor Yellow
    }
    if ($invalidLocks.Count -gt 0) {
        Write-Host '  [WARN] Detected invalid TaskId lock entries (non-canonical).' -ForegroundColor Yellow
    }

    # Attempt history
    Write-Host ''
    Write-Host '--- Recent Attempts ---' -ForegroundColor Cyan
    $attemptHistory = Read-TaskAttemptHistory
    $recentAttempts = @(
        @(Get-TaskAttemptList $attemptHistory) |
        Sort-Object started_at -Descending |
        Select-Object -First 8
    )
    if ($recentAttempts.Count -eq 0) {
        Write-Host '  (no attempt history)' -ForegroundColor Gray
    } else {
        foreach ($attempt in $recentAttempts) {
            $result = if ($attempt.result) { [string]$attempt.result } else { "-" }
            $color = switch ($result) {
                "success" { "Green" }
                "running" { "Yellow" }
                "blocked" { "Red" }
                "requeued" { "Yellow" }
                default { "Gray" }
            }
            $line = '  ' + ([string]$attempt.task_id).PadRight(18) + ' phase=' + [string]$attempt.phase + ' result=' + $result + ' worker=' + [string]$attempt.worker
            if ($attempt.requeue_reason) {
                $line += ' reason=' + [string]$attempt.requeue_reason
            }
            Write-Host $line -ForegroundColor $color
        }
    }

    # API doc sync status
    Write-Host ''
    Write-Host '--- API Doc Sync ---' -ForegroundColor Cyan
    $docSync = Read-DocSyncState
    $backendRows = @($docSync.backend.GetEnumerator() | Sort-Object Name)
    if ($backendRows.Count -eq 0) {
        Write-Host '  (no backend doc sync records)' -ForegroundColor Gray
    } else {
        foreach ($row in $backendRows) {
            $backendTask = $row.Key
            $entry = $row.Value
            $syncStatus = if ($entry.doc_sync_status) { [string]$entry.doc_sync_status } else { "unknown" }
            $color = switch ($syncStatus) {
                "synced" { "Green" }
                "pending" { "Yellow" }
                "blocked" { "Red" }
                "fail" { "Red" }
                default { "Gray" }
            }
            $syncedAt = if ($entry.doc_synced_at) { [string]$entry.doc_synced_at } else { "-" }
            Write-Host ('  ' + $backendTask.PadRight(18) + ' status=' + $syncStatus + ' synced_at=' + $syncedAt) -ForegroundColor $color
        }
    }

    # Archive jobs
    Write-Host ''
    Write-Host '--- Archive Jobs ---' -ForegroundColor Cyan
    $archiveJobs = Read-ArchiveJobs
    $jobRows = @()
    if ($archiveJobs.jobs) {
        $jobMap = Convert-ToArchiveJobMap $archiveJobs.jobs
        $jobRows = @($jobMap.Values)
    }
    $activeJobs = @($jobRows | Where-Object { $_.status -in @("pending", "running", "blocked") } | Sort-Object started_at)
    if ($activeJobs.Count -eq 0) {
        Write-Host '  (no active archive jobs)' -ForegroundColor Gray
    } else {
        foreach ($job in $activeJobs) {
            $st = [string]$job.status
            $color = switch ($st) {
                "pending" { "Yellow" }
                "running" { "Cyan" }
                "blocked" { "Red" }
                default { "Gray" }
            }
            $line = '  ' + ([string]$job.task_id).PadRight(18) + ' status=' + $st + ' doc=' + [string]$job.doc_status + ' commit=' + [string]$job.commit_status
            Write-Host $line -ForegroundColor $color
        }
    }

    # Suggested actions
    Write-Host ''
    Write-Host '--- Suggested Actions ---' -ForegroundColor Cyan
    if (-not $flagExists) {
        Write-Host '  powershell -File scripts/teamlead-control.ps1 -Action bootstrap' -ForegroundColor Yellow
    } else {
        $activeTaskIds = @($gate.active_task_ids)
        $lockOnlyActive = @($gate.lock_only_active)

        if ($lockOnlyActive.Count -gt 0) {
            Write-Host ('  [WARN] Lock-only active tasks (missing in active dir): ' + ($lockOnlyActive -join ', ')) -ForegroundColor Yellow
            Write-Host '         These tasks still block archive until resolved.' -ForegroundColor DarkYellow
        }

        if ($activeTaskIds.Count -eq 0) {
            Write-Host '  No active tasks' -ForegroundColor Green
        }

        if ($taskRecommendations.Count -gt 0) {
            foreach ($rec in @($taskRecommendations | Sort-Object priority, task_id)) {
                Write-Host ('  ' + $rec.task_id + ' -> ' + $rec.summary) -ForegroundColor $rec.color
                foreach ($cmd in @($rec.commands)) {
                    Write-Host ('    ' + $cmd) -ForegroundColor White
                }
            }
        }

        if ($orphanLocks.Count -gt 0) {
            Write-Host '  Drift recovery:' -ForegroundColor Yellow
            Write-Host '    powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction reap-stale' -ForegroundColor White
            foreach ($item in $orphanLocks) {
                $parts = $item -split '\|'
                if ($parts.Count -ge 2) {
                    $tid = $parts[0]
                    $w = $parts[1]
                    Write-Host ('    powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction reset-task -TaskId ' + $tid + ' -TargetState assigned') -ForegroundColor White
                    Write-Host ('    powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-worker -WorkerName ' + $w) -ForegroundColor White
                }
            }
        }
        if ($invalidLocks.Count -gt 0) {
            Write-Host '  Lock normalization:' -ForegroundColor Yellow
            Write-Host '    powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction normalize-locks' -ForegroundColor White
        }
        if ($pendingRoutes.Count -gt 0 -or $pendingApprovals.Count -gt 0 -or $invalidLocks.Count -gt 0) {
            Write-Host '  Optional cleanup (manual only):' -ForegroundColor Yellow
            Write-Host '    powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction baseline-clean' -ForegroundColor White
        }
    }
    Write-Host ''
}

# ============================================================
# Recover helper: baseline-clean
# ============================================================
function Get-ActiveTaskIdSet {
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    $activeRoot = Join-Path $rootDir "01-tasks\active"
    if (-not (Test-Path $activeRoot)) { return $set }

    $files = @(Get-ChildItem -Path "$activeRoot\*\*.md" -File -ErrorAction SilentlyContinue)
    foreach ($f in $files) {
        $fn = [string]$f.Name
        if ($fn -match '^(BACKEND|SHOP-FE|ADMIN-FE)-\d+') {
            [void]$set.Add([string]$matches[0].ToUpper())
        }
    }
    return $set
}

function Get-TaskStateText($locks, [string]$TaskId) {
    if ($locks -and $locks.locks -and $locks.locks.PSObject.Properties.Name -contains $TaskId) {
        $raw = $locks.locks.$TaskId.state
        if ($raw) { return ([string]$raw).ToLower() }
    }
    return "unlocked"
}

function Get-ArchiveGateContext($locks) {
    $idMap = @{}
    foreach ($tid in @(Get-ActiveTaskIdSet)) {
        if ($tid) { $idMap[$tid.ToUpper()] = $true }
    }

    $lockOnlyActive = New-Object System.Collections.Generic.List[string]
    if ($locks -and $locks.locks) {
        foreach ($p in $locks.locks.PSObject.Properties) {
            $tid = [string]$p.Name
            if (-not $tid) { continue }
            $state = Get-TaskStateText -locks $locks -TaskId $tid
            if ($state -ne "completed" -and -not $idMap.ContainsKey($tid.ToUpper())) {
                $idMap[$tid.ToUpper()] = $true
                $lockOnlyActive.Add($tid.ToUpper() + ":" + $state) | Out-Null
            }
        }
    }

    $activeTaskIds = @($idMap.Keys | Sort-Object)
    $dispatchTodoTasks = @()
    $runningTasks = @()
    $archiveReadyTasks = @()
    $otherActiveTasks = @()

    foreach ($tid in $activeTaskIds) {
        $state = Get-TaskStateText -locks $locks -TaskId $tid
        switch ($state) {
            "assigned"    { $dispatchTodoTasks += $tid; continue }
            "blocked"     { $dispatchTodoTasks += $tid; continue }
            "in_progress" { $runningTasks += $tid; continue }
            "qa"          { $runningTasks += $tid; continue }
            "waiting_qa"  { $runningTasks += $tid; continue }
            "qa_passed"   { $archiveReadyTasks += $tid; continue }
            "archiving"   { $archiveReadyTasks += $tid; continue }
            "completed"   { $archiveReadyTasks += $tid; continue }
            default       { $otherActiveTasks += ($tid + ":" + $state); continue }
        }
    }

    return [pscustomobject]@{
        active_task_ids    = $activeTaskIds
        lock_only_active   = @($lockOnlyActive.ToArray())
        dispatch_todo      = $dispatchTodoTasks
        running            = $runningTasks
        archive_ready      = $archiveReadyTasks
        other_active       = $otherActiveTasks
    }
}

function Invoke-BaselineClean {
    Write-Host '[INFO] Running baseline-clean (dirty-state cleanup)...' -ForegroundColor Yellow

    $summary = [ordered]@{
        approvals_resolved = 0
        approvals_force_resolved = 0
        routes_marked_processed = 0
        lock_keys_removed = 0
        blocked_to_assigned = 0
        router_entries_removed = 0
    }

    # 1) Worker registry reconcile/health-check
    try { Reconcile-WorkerRegistryFromPanes | Out-Null } catch {}
    $regScript = Join-Path $scriptDir "worker-registry.ps1"
    if (Test-Path $regScript) {
        try { & $regScript -Action health-check *> $null } catch {}
    }
    $routerCleanup = Cleanup-StaleApprovalRouters
    $summary.router_entries_removed = $routerCleanup.removed

    # 2) Resolve all pending approval requests (deny)
    $approvals = Read-ApprovalRequests
    if (-not $approvals.requests) { $approvals.requests = @() }
    $pendingApprovals = @($approvals.requests | Where-Object { $_.status -eq 'pending' } | Sort-Object created_at)
    $approvalNow = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    foreach ($req in $pendingApprovals) {
        $sent = $false
        $targetPane = if ($req.worker_pane_id) { [string]$req.worker_pane_id } else { "" }
        $promptType = if ($req.prompt_type) { [string]$req.prompt_type } else { "command_approval" }
        if ($targetPane) {
            try { $sent = Send-ApprovalDecisionToPane -paneId $targetPane -decision 'deny' -promptType $promptType } catch { $sent = $false }
        }
        if (-not $sent) {
            $reqWorkerName = if ($req.worker) { [string]$req.worker } elseif ($req.worker_name) { [string]$req.worker_name } else { "" }
            $resolvedPane = Resolve-WorkerPaneByName -workerName $reqWorkerName
            if ($resolvedPane) {
                try {
                    $sent = Send-ApprovalDecisionToPane -paneId $resolvedPane -decision 'deny' -promptType $promptType
                    if ($sent) { $req.worker_pane_id = $resolvedPane }
                } catch {
                    $sent = $false
                }
            }
        }

        $req.status = 'resolved'
        $req.decision = 'deny'
        $req.resolved_at = $approvalNow
        if ($sent) {
            $req.resolved_by = 'teamlead-control/recover-baseline-clean'
            Set-NoteField -obj $req -value 'Baseline cleanup auto-deny (decision sent to worker pane).'
            $summary.approvals_resolved++
        } else {
            $req.resolved_by = 'teamlead-control/recover-baseline-clean-offline'
            Set-NoteField -obj $req -value 'Baseline cleanup force-resolved: worker pane unavailable.'
            $summary.approvals_force_resolved++
        }
    }
    if ($pendingApprovals.Count -gt 0) {
        Write-ApprovalRequests $approvals
    }

    # 3) Mark all pending route inbox records as processed
    $inboxPath = Join-Path $rootDir "mcp\route-server\data\route-inbox.json"
    if (Test-Path $inboxPath) {
        try {
            $inbox = Get-Content $inboxPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not $inbox.routes) { $inbox | Add-Member -NotePropertyName routes -NotePropertyValue @() -Force }
            $changedInbox = $false
            $processedAt = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
            foreach ($r in @($inbox.routes)) {
                $isProcessed = $false
                if ($null -ne $r.processed) { $isProcessed = [bool]$r.processed }
                if (-not $isProcessed) {
                    $r.processed = $true
                    $r.processed_at = $processedAt
                    $summary.routes_marked_processed++
                    $changedInbox = $true
                }
            }
            if ($changedInbox) {
                $inbox.updated_at = $processedAt
                $jsonInbox = ($inbox | ConvertTo-Json -Depth 12)
                Write-Utf8NoBomFile -path $inboxPath -content $jsonInbox
            }
        } catch {
            Write-Host ('[WARN] Failed to clean route inbox: ' + $_.Exception.Message) -ForegroundColor Yellow
        }
    }

    # 4) Normalize lock keys + recover stale approval-blocked active tasks
    $activeTaskIds = Get-ActiveTaskIdSet
    $pendingTaskIds = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($req in @($approvals.requests | Where-Object { $_.status -eq 'pending' })) {
        $reqTask = if ($req.task) { [string]$req.task } elseif ($req.task_id) { [string]$req.task_id } else { "" }
        if ($reqTask) { [void]$pendingTaskIds.Add($reqTask.ToUpper()) }
    }

    Update-TaskLocksData {
        param($locks)
        $validLocks = @{}
        if ($locks.locks) {
            foreach ($p in $locks.locks.PSObject.Properties) {
                $tid = [string]$p.Name
                if ($tid -match '^(BACKEND|SHOP-FE|ADMIN-FE)-\d+$') {
                    $validLocks[$tid] = $p.Value
                } else {
                    $summary.lock_keys_removed++
                }
            }
        }
        $locks.locks = $validLocks

        foreach ($tid in @($locks.locks.Keys)) {
            $lock = $locks.locks[$tid]
            if (-not $lock) { continue }
            $state = if ($lock.state) { [string]$lock.state } else { "" }
            $note = if ($lock.note) { [string]$lock.note } else { "" }
            if (
                $state -eq 'blocked' -and
                $note -like 'Approval required:*' -and
                $activeTaskIds.Contains($tid) -and
                -not $pendingTaskIds.Contains($tid)
            ) {
                $lock.state = 'assigned'
                $lock.updated_at = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
                $lock.updated_by = 'teamlead-control/recover-baseline-clean'
                Set-NoteField -obj $lock -value 'Recovered from stale approval block by baseline-clean'
                Set-ObjectField -obj $lock -name "run_id" -value ""
                if ($lock.PSObject.Properties.Name -contains 'routeUpdate') {
                    $lock.PSObject.Properties.Remove('routeUpdate')
                }
                $locks.locks[$tid] = $lock
                $summary.blocked_to_assigned++
            }
        }
        return $null
    } | Out-Null

    Write-Host '[OK] baseline-clean complete' -ForegroundColor Green
    Write-Host ('  approvals_resolved: ' + $summary.approvals_resolved) -ForegroundColor Gray
    Write-Host ('  approvals_force_resolved: ' + $summary.approvals_force_resolved) -ForegroundColor Gray
    Write-Host ('  routes_marked_processed: ' + $summary.routes_marked_processed) -ForegroundColor Gray
    Write-Host ('  lock_keys_removed: ' + $summary.lock_keys_removed) -ForegroundColor Gray
    Write-Host ('  blocked_to_assigned: ' + $summary.blocked_to_assigned) -ForegroundColor Gray
    Write-Host ('  router_entries_removed: ' + $summary.router_entries_removed) -ForegroundColor Gray
}

function Invoke-PreDispatchBaselineClean {
    $auto = [System.Environment]::GetEnvironmentVariable("TEAMLEAD_AUTO_BASELINE_CLEAN")
    if ($auto -and $auto.Trim() -eq "0") {
        Write-Host '[INFO] Pre-dispatch baseline-clean disabled by TEAMLEAD_AUTO_BASELINE_CLEAN=0' -ForegroundColor DarkGray
        return
    }
    Write-Host '[INFO] Pre-dispatch baseline-clean enabled, running...' -ForegroundColor Cyan
    Invoke-BaselineClean
}

# ============================================================
# Action: recover
# ============================================================
function Invoke-Recover {
    if (-not $RecoverAction) {
        Write-Host '[FAIL] recover requires -RecoverAction (reap-stale / restart-worker / reset-task / normalize-locks / baseline-clean / full-clean)' -ForegroundColor Red
        exit 1
    }

    $tlPaneId = $null
    if ($RecoverAction -eq "restart-worker") {
        $tlPaneId = Resolve-TeamLeadPaneId
    }

    switch ($RecoverAction) {
        "reap-stale" {
            Write-Host '[INFO] Cleaning stale worker registrations...' -ForegroundColor Yellow
            $regScript = Join-Path $scriptDir "worker-registry.ps1"
            & $regScript -Action health-check
            try { Reconcile-WorkerRegistryFromPanes | Out-Null } catch {}

            if (Test-Path $monitorPidFile) {
                $savedPid = (Get-Content $monitorPidFile -Raw).Trim()
                try {
                    $proc = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
                    if (-not $proc) {
                        Remove-Item $monitorPidFile -Force
                        Write-Host '[OK] Cleaned stale monitor PID file' -ForegroundColor Green
                    }
                } catch {
                    Remove-Item $monitorPidFile -Force
                }
            }

            try {
                $clean = Cleanup-StaleApprovalRouters -Verbose
                if ($clean.removed -gt 0) {
                    Write-Host ('[OK] cleaned stale approval-router entries: removed=' + $clean.removed + ', killed=' + $clean.killed) -ForegroundColor Green
                }
            } catch {}
            Write-Host '[OK] reap-stale done' -ForegroundColor Green
        }

        "restart-worker" {
            if (-not $WorkerName) {
                Write-Host '[FAIL] restart-worker requires -WorkerName' -ForegroundColor Red
                exit 1
            }
            $workerMap = Get-WorkerMap
            $wConfig = $null
            $workerMap.PSObject.Properties | ForEach-Object {
                $cfg = $_.Value
                $devWorkers = @(Get-WorkerListForPhase -cfg $cfg -phase "dev")
                $qaWorkers = @(Get-WorkerListForPhase -cfg $cfg -phase "qa")
                if ($devWorkers -contains $WorkerName -or $qaWorkers -contains $WorkerName) {
                    $wConfig = $cfg
                }
            }
            if (-not $wConfig) {
                Write-Host ('[FAIL] Worker ' + $WorkerName + ' not in worker-map.json') -ForegroundColor Red
                exit 1
            }

            $regScript = Join-Path $scriptDir "worker-registry.ps1"
            & $regScript -Action unregister -WorkerName $WorkerName 2>$null

            $isQa = ($WorkerName.ToLower() -match '(^|-)qa(?:-\d+)?$')
            $restartEngine = if ($isQa -and $wConfig.qa_engine) { $wConfig.qa_engine } elseif (-not $isQa -and $wConfig.dev_engine) { $wConfig.dev_engine } else { $wConfig.engine }

            $startScript = Join-Path $scriptDir "start-worker.ps1"
            & $startScript -WorkDir $wConfig.workdir -WorkerName $WorkerName -Engine $restartEngine -TeamLeadPaneId $tlPaneId
            Write-Host ('[OK] Worker ' + $WorkerName + ' restarted') -ForegroundColor Green
        }

        "reset-task" {
            if (-not $TaskId) {
                Write-Host '[FAIL] reset-task requires -TaskId' -ForegroundColor Red
                exit 1
            }
            Assert-CanonicalTaskId $TaskId
            if (-not $TargetState) {
                $TargetState = "assigned"
            }
            $locks = Read-TaskLocks
            if ($locks.locks.PSObject.Properties.Name -notcontains $TaskId) {
                Write-Host ('[FAIL] Task ' + $TaskId + ' not in TASK-LOCKS.json') -ForegroundColor Red
                exit 1
            }
            Update-TaskLocksData {
                param($latest)
                if ($latest.locks.PSObject.Properties.Name -notcontains $TaskId) {
                    throw ("Task missing during reset-task commit: " + $TaskId)
                }
                $latestLock = $latest.locks.$TaskId
                $latestLock.state = $TargetState
                $latestLock.updated_at = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
                $latestLock.updated_by = "teamlead-control/recover"
                Set-NoteField -obj $latestLock -value "Manual reset to $TargetState"
                if ($TargetState -notin @("in_progress", "qa")) {
                    Set-ObjectField -obj $latestLock -name "run_id" -value ""
                }
                return $null
            } | Out-Null
            Write-Host ('[OK] Task ' + $TaskId + ' reset to ' + $TargetState) -ForegroundColor Green
        }

        "normalize-locks" {
            $removed = Update-TaskLocksData {
                param($latest)
                $validLocks = @{}
                $removedLocal = New-Object System.Collections.Generic.List[string]
                if ($latest.locks) {
                    foreach ($p in $latest.locks.PSObject.Properties) {
                        $k = [string]$p.Name
                        if ($k -match '^(BACKEND|SHOP-FE|ADMIN-FE)-\d+$') {
                            $validLocks[$k] = $p.Value
                        } else {
                            $removedLocal.Add($k) | Out-Null
                        }
                    }
                }
                $latest.locks = $validLocks
                return @($removedLocal.ToArray())
            }
            if ($removed.Count -gt 0) {
                Write-Host '[OK] Removed non-canonical task lock keys:' -ForegroundColor Green
                foreach ($k in $removed) {
                    Write-Host ('  - ' + $k) -ForegroundColor Yellow
                }
            } else {
                Write-Host '[OK] No non-canonical task lock keys found.' -ForegroundColor Green
            }
        }

        "baseline-clean" {
            Invoke-BaselineClean
        }

        "full-clean" {
            Write-Host '[INFO] Running full-clean (baseline-clean + reap-stale + status)...' -ForegroundColor Cyan
            Invoke-BaselineClean

            Write-Host '[INFO] full-clean step 2/3: reap-stale...' -ForegroundColor Yellow
            $regScript = Join-Path $scriptDir "worker-registry.ps1"
            & $regScript -Action health-check
            try { Reconcile-WorkerRegistryFromPanes | Out-Null } catch {}

            if (Test-Path $monitorPidFile) {
                $savedPid = (Get-Content $monitorPidFile -Raw).Trim()
                try {
                    $proc = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
                    if (-not $proc) {
                        Remove-Item $monitorPidFile -Force
                        Write-Host '[OK] Cleaned stale monitor PID file' -ForegroundColor Green
                    }
                } catch {
                    Remove-Item $monitorPidFile -Force
                }
            }

            try {
                $clean = Cleanup-StaleApprovalRouters -Verbose
                if ($clean.removed -gt 0) {
                    Write-Host ('[OK] cleaned stale approval-router entries: removed=' + $clean.removed + ', killed=' + $clean.killed) -ForegroundColor Green
                }
            } catch {}

            Write-Host '[INFO] full-clean step 3/3: status...' -ForegroundColor Yellow
            Invoke-Status
            Write-Host '[OK] full-clean done' -ForegroundColor Green
        }
    }
}

# ============================================================
# Action: approve-request / deny-request
# ============================================================
function Invoke-ApprovalDecision($decision) {
    if (-not $RequestId) {
        Write-Host ('[FAIL] ' + $Action + ' requires -RequestId') -ForegroundColor Red
        exit 1
    }

    $cleanupResult = Cleanup-ExpiredApprovalRequests -Persist
    $approvals = $cleanupResult.data
    $req = $approvals.requests | Where-Object { $_.id -eq $RequestId } | Select-Object -First 1
    if (-not $req) {
        Write-Host ('[FAIL] Approval request not found: ' + $RequestId) -ForegroundColor Red
        exit 1
    }
    if ($req.status -ne 'pending') {
        Write-Host ('[FAIL] Approval request is not pending: ' + $RequestId + ' (status=' + $req.status + ')') -ForegroundColor Red
        exit 1
    }

    $targetPane = [string]$req.worker_pane_id
    $promptType = if ($req.prompt_type) { [string]$req.prompt_type } else { "command_approval" }
    $sent = Send-ApprovalDecisionToPane -paneId $targetPane -decision $decision -promptType $promptType
    if (-not $sent) {
        $reqWorkerName = if ($req.worker) { [string]$req.worker } elseif ($req.worker_name) { [string]$req.worker_name } else { "" }
        $resolvedPane = Resolve-WorkerPaneByName -workerName $reqWorkerName
        if ($resolvedPane -and $resolvedPane -ne $targetPane) {
            Write-Host ('[WARN] Pane drift detected. Retry approval decision via registry pane ' + $resolvedPane) -ForegroundColor Yellow
            $sent = Send-ApprovalDecisionToPane -paneId $resolvedPane -decision $decision -promptType $promptType
            if ($sent) {
                $req.worker_pane_id = $resolvedPane
            }
        }
    }

    if (-not $sent) {
        Write-Host ('[FAIL] Failed to send approval decision to pane ' + $targetPane + '. Request remains pending: ' + $RequestId) -ForegroundColor Red
        exit 1
    }

    $req.status = 'resolved'
    $req.decision = $decision
    $req.resolved_at = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    $req.resolved_by = 'teamlead-control/' + $Action
    Write-ApprovalRequests $approvals

    Write-Host ('[OK] Approval request ' + $RequestId + ' -> ' + $decision) -ForegroundColor Green
    Write-Host ('     Decision sent to pane ' + $req.worker_pane_id) -ForegroundColor Gray
}

# ============================================================
# Action: add-lock
# ============================================================
function Invoke-AddLock {
    if (-not $TaskId) {
        Write-Host '[FAIL] add-lock requires -TaskId' -ForegroundColor Red
        exit 1
    }
    Assert-CanonicalTaskId $TaskId

    $prefix = Resolve-TaskPrefix $TaskId
    if (-not $prefix) {
        Write-Host ('[FAIL] Unknown task prefix: ' + $TaskId) -ForegroundColor Red
        exit 1
    }

    $workerMap = Get-WorkerMap
    $wConfig = $workerMap.$prefix
    $domain = $wConfig.domain

    # Verify task file exists (P0-4)
    $taskDir = Join-Path $rootDir "01-tasks\active\$domain"
    $taskFiles = Get-ChildItem -Path "$taskDir\$TaskId*.md" -ErrorAction SilentlyContinue
    if ($taskFiles.Count -eq 0) {
        Write-Host ('[FAIL] Task file not found: ' + $TaskId + ' (dir: 01-tasks/active/' + $domain + '/)') -ForegroundColor Red
        exit 1
    }
    if ($taskFiles.Count -gt 1) {
        Write-Host ('[FAIL] Multiple task files match ' + $TaskId + ', resolve manually:') -ForegroundColor Red
        $taskFiles | ForEach-Object { Write-Host ('  - ' + $_.Name) -ForegroundColor Yellow }
        exit 1
    }

    $locks = Read-TaskLocks

    # Check if already exists
    if ($locks.locks.PSObject.Properties.Name -contains $TaskId) {
        $st = $locks.locks.$TaskId.state
        Write-Host ('[WARN] Task ' + $TaskId + ' already has lock (state=' + $st + ')') -ForegroundColor Yellow
        return
    }

    # Create lock entry
    $newLock = @{
        runner = ""
        owner = "team-lead"
        state = "assigned"
        updated_at = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
        updated_by = "teamlead-control/add-lock"
        run_id = ""
        note = ""
    }

    $created = Update-TaskLocksData {
        param($latest)
        if ($latest.locks.PSObject.Properties.Name -contains $TaskId) {
            return $false
        }
        $locksHash = @{}
        $latest.locks.PSObject.Properties | ForEach-Object { $locksHash[$_.Name] = $_.Value }
        $locksHash[$TaskId] = $newLock
        $latest.locks = $locksHash
        return $true
    }
    if (-not $created) {
        Write-Host ('[WARN] Task ' + $TaskId + ' already has lock after refresh') -ForegroundColor Yellow
        return
    }

    Write-Host ('[OK] Lock created: ' + $TaskId + ' -> assigned') -ForegroundColor Green
}

# ============================================================
# Action: archive
# ============================================================
function Invoke-Archive {
    if (-not $TaskId) {
        Write-Host '[FAIL] archive requires -TaskId' -ForegroundColor Red
        exit 1
    }
    Assert-CanonicalTaskId $TaskId

    $tlPaneId = Resolve-TeamLeadPaneId
    $locks = Read-TaskLocks
    $prefix = Resolve-TaskPrefix $TaskId
    if (-not $prefix) {
        Write-Host ('[FAIL] Unknown task prefix: ' + $TaskId) -ForegroundColor Red
        exit 1
    }

    $workerMap = Get-WorkerMap
    $wConfig = $workerMap.$prefix
    if (-not $wConfig) {
        Write-Host ('[FAIL] No config for prefix ' + $prefix + ' in worker-map.json') -ForegroundColor Red
        exit 1
    }
    $domain = $wConfig.domain
    Sync-TaskAttemptHistoryFromLocks -TaskId $TaskId | Out-Null

    $lock = $null
    if ($locks.locks.PSObject.Properties.Name -contains $TaskId) {
        $lock = $locks.locks.$TaskId
    }
    if (-not $lock) {
        Write-Host ('[FAIL] Task ' + $TaskId + ' not in TASK-LOCKS.json. Cannot archive.') -ForegroundColor Red
        exit 1
    }
    if ($lock.state -notin @("completed", "qa_passed", "blocked", "archiving")) {
        Write-Host ('[FAIL] Task ' + $TaskId + " state='" + $lock.state + "' cannot archive.") -ForegroundColor Red
        Write-Host '       Required state: completed / qa_passed / blocked / archiving' -ForegroundColor Yellow
        exit 1
    }

    # 全局归档门禁：仅当所有活跃任务都处于可归档态时才允许 archive
    $gate = Get-ArchiveGateContext -locks $locks
    $blocking = @()
    $blocking += @($gate.dispatch_todo | Where-Object { $_ -ne $TaskId })
    $blocking += @($gate.running | Where-Object { $_ -ne $TaskId })
    $blocking += @($gate.other_active | Where-Object { -not $_.StartsWith($TaskId + ":") })
    if ($blocking.Count -gt 0) {
        Write-Host ('[FAIL] Archive blocked: non-archive-ready active tasks still exist: ' + ($blocking -join ', ')) -ForegroundColor Red
        Write-Host '       Rule: only when all active tasks are qa_passed/archiving/completed can archive proceed.' -ForegroundColor Yellow
        exit 1
    }

    $activeDir = Join-Path $rootDir ("01-tasks\active\" + $domain)
    $completedDir = Join-Path $rootDir ("01-tasks\completed\" + $domain)
    if (-not (Test-Path $completedDir)) {
        New-Item -ItemType Directory -Path $completedDir -Force | Out-Null
    }

    $activeMatches = @(Get-ChildItem -Path "$activeDir\$TaskId*.md" -File -ErrorAction SilentlyContinue)
    $completedMatches = @(Get-ChildItem -Path "$completedDir\$TaskId*.md" -File -ErrorAction SilentlyContinue)

    if ($activeMatches.Count -gt 1) {
        Write-Host ('[FAIL] Multiple active task files matched ' + $TaskId) -ForegroundColor Red
        $activeMatches | ForEach-Object { Write-Host ('  - ' + $_.Name) -ForegroundColor Yellow }
        exit 1
    }
    if ($completedMatches.Count -gt 1) {
        Write-Host ('[FAIL] Multiple completed task files matched ' + $TaskId) -ForegroundColor Red
        $completedMatches | ForEach-Object { Write-Host ('  - ' + $_.Name) -ForegroundColor Yellow }
        exit 1
    }

    $archivedFile = $null
    $movedToCompletedNow = $false
    if ($activeMatches.Count -eq 1) {
        $source = $activeMatches[0].FullName
        $dest = Join-Path $completedDir $activeMatches[0].Name
        Move-Item -Path $source -Destination $dest -Force
        $archivedFile = $dest
        $movedToCompletedNow = $true
        Write-Host ('[OK] Task file archived: ' + $TaskId + ' -> completed/' + $domain) -ForegroundColor Green
    } elseif ($completedMatches.Count -eq 1) {
        $archivedFile = $completedMatches[0].FullName
        Write-Host ('[WARN] Task file already in completed: ' + $completedMatches[0].Name) -ForegroundColor Yellow
    } else {
        Write-Host ('[FAIL] Task file not found in active/completed for ' + $TaskId) -ForegroundColor Red
        exit 1
    }

    $docTriggerScript = Join-Path $scriptDir "trigger-doc-updater.ps1"
    $commitTriggerScript = Join-Path $scriptDir "trigger-repo-committer.ps1"

    if (-not (Test-Path $docTriggerScript)) {
        Write-Host '[FAIL] trigger-doc-updater.ps1 not found. Archive cannot guarantee docs consistency.' -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path $commitTriggerScript)) {
        Write-Host '[FAIL] trigger-repo-committer.ps1 not found. Archive cannot guarantee commit/push.' -ForegroundColor Red
        exit 1
    }

    $jobId = "ARCHIVE-" + $TaskId
    $docTaskId = ""
    $commitTaskId = ""
    $upsertArchiveJob = {
        param(
            [string]$status,
            [string]$docId,
            [string]$commitId,
            [string]$docStatus,
            [string]$commitStatus,
            [string]$note,
            [string]$blockedReason
        )
        try {
            $jobsLocal = Read-ArchiveJobs
            $jobsHashLocal = Convert-ToArchiveJobMap $jobsLocal.jobs
            $entry = if ($jobsHashLocal.ContainsKey($jobId)) { $jobsHashLocal[$jobId] } else { @{} }
            $entry.job_id = $jobId
            $entry.task_id = $TaskId
            $entry.domain = $domain
            $entry.archived_file = $archivedFile
            $entry.moved_to_completed = $movedToCompletedNow
            $entry.status = $status
            $entry.doc_task_id = if ($docId) { $docId } elseif ($entry.doc_task_id) { $entry.doc_task_id } else { "" }
            $entry.doc_status = if ($docStatus) { $docStatus } elseif ($entry.doc_status) { $entry.doc_status } else { "pending" }
            $entry.commit_task_id = if ($commitId) { $commitId } elseif ($entry.commit_task_id) { $entry.commit_task_id } else { "" }
            $entry.commit_status = if ($commitStatus) { $commitStatus } elseif ($entry.commit_status) { $entry.commit_status } else { "pending" }
            $entry.push_required = (-not $NoPush.IsPresent)
            if (-not $entry.started_at) { $entry.started_at = Get-Date -Format "o" }
            $entry.updated_at = Get-Date -Format "o"
            $entry.updated_by = "teamlead-control/archive"
            if ($note) { $entry.note = $note }
            if ($blockedReason) { $entry.blocked_reason = $blockedReason }
            $jobsHashLocal[$jobId] = $entry
            $jobsLocal.jobs = $jobsHashLocal
            Write-ArchiveJobs $jobsLocal
        } catch {}
    }
    $markArchiveBlocked = {
        param([string]$lockNote, [string]$jobReason)
        Update-TaskLocksData {
            param($latest)
            if ($latest.locks.PSObject.Properties.Name -contains $TaskId) {
                $latestLock = $latest.locks.$TaskId
                $latestLock.state = "blocked"
                $latestLock.updated_at = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
                $latestLock.updated_by = "teamlead-control/archive"
                Set-NoteField -obj $latestLock -value $lockNote
                Set-ObjectField -obj $latestLock -name "run_id" -value ""
            }
            return $null
        } | Out-Null
        & $upsertArchiveJob -status "blocked" -docId $docTaskId -commitId $commitTaskId -docStatus "blocked" -commitStatus "blocked" -note $lockNote -blockedReason $jobReason
    }

    # 先落一条 archive job，避免中途异常导致锁在 archiving 但无 job 可追踪
    & $upsertArchiveJob -status "starting" -docId "" -commitId "" -docStatus "pending" -commitStatus "pending" -note "Archive initializing" -blockedReason ""

    # 先进入 archiving 中间态，等待 doc-updater + repo-committer 回传收口
    Update-TaskLocksData {
        param($latest)
        if ($latest.locks.PSObject.Properties.Name -notcontains $TaskId) {
            throw ("Task missing during archive commit: " + $TaskId)
        }
        $latestLock = $latest.locks.$TaskId
        if ([string]$latestLock.state -notin @("completed", "qa_passed", "blocked", "archiving")) {
            throw ("Task state drifted before archive commit: " + $TaskId + " state=" + [string]$latestLock.state)
        }
        $latestLock.state = "archiving"
        $latestLock.updated_at = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
        $latestLock.updated_by = "teamlead-control/archive"
        Set-NoteField -obj $latestLock -value "Archive started: waiting doc-updater + repo-committer"
        Set-ObjectField -obj $latestLock -name "run_id" -value ""
        return $null
    } | Out-Null
    & $upsertArchiveJob -status "running" -docId "" -commitId "" -docStatus "pending" -commitStatus "pending" -note "Archive started: waiting doc-updater + repo-committer" -blockedReason ""

    # Trigger doc-updater（归档一致性）
    try {
        $docRaw = & $docTriggerScript -TaskId $TaskId -TeamLeadPaneId $tlPaneId -Reason archive_move -Force -EmitJson
        $docResp = Convert-CommandOutputToJson -output $docRaw
    } catch {
        Write-Host ('[FAIL] trigger-doc-updater exception: ' + $_.Exception.Message) -ForegroundColor Red
        & $markArchiveBlocked -lockNote "Archive blocked: doc-updater exception" -jobReason ("doc_updater_exception: " + $_.Exception.Message)
        exit 1
    }
    if (-not $docResp) {
        Write-Host '[FAIL] trigger-doc-updater did not return machine-readable result.' -ForegroundColor Red
        & $markArchiveBlocked -lockNote "Archive blocked: doc-updater response invalid" -jobReason "doc_updater_response_invalid"
        exit 1
    }
    if ($docResp.status -notin @("dispatched", "already_dispatched")) {
        Write-Host ('[FAIL] doc-updater dispatch failed: status=' + [string]$docResp.status + ' message=' + [string]$docResp.message) -ForegroundColor Red
        & $markArchiveBlocked -lockNote "Archive blocked: doc-updater dispatch failed" -jobReason ("doc_updater_dispatch_failed: " + [string]$docResp.status)
        exit 1
    }
    $docTaskId = [string]$docResp.docTaskId
    if (-not $docTaskId) {
        Write-Host '[FAIL] doc-updater response missing docTaskId.' -ForegroundColor Red
        & $markArchiveBlocked -lockNote "Archive blocked: doc-updater missing docTaskId" -jobReason "doc_updater_missing_doc_task_id"
        exit 1
    }
    $docPaneId = ""
    if ($docResp.workerPane) {
        $docPaneId = [string]$docResp.workerPane
    } elseif ($docResp.docUpdaterPane) {
        $docPaneId = [string]$docResp.docUpdaterPane
    }
    if ($docPaneId) {
        Ensure-ApprovalRouter -TaskId $docTaskId -WorkerName "doc-updater" -WorkerPaneId $docPaneId -TeamLeadPaneId $tlPaneId
    } else {
        Write-Host '[WARN] doc-updater pane not returned, cannot auto-attach approval-router.' -ForegroundColor Yellow
    }
    & $upsertArchiveJob -status "running" -docId $docTaskId -commitId "" -docStatus "pending" -commitStatus "pending" -note "Doc updater dispatched" -blockedReason ""

    # Trigger repo-committer（默认 push）
    $commitArgs = @("-TaskId", $TaskId, "-TeamLeadPaneId", $tlPaneId, "-Force", "-EmitJson")
    if (-not $NoPush.IsPresent) {
        $commitArgs += "-Push"
    }
    if ($CommitMessage) {
        $commitArgs += @("-CommitMessage", $CommitMessage)
    }
    try {
        $commitRaw = & $commitTriggerScript @commitArgs
        $commitResp = Convert-CommandOutputToJson -output $commitRaw
    } catch {
        Write-Host ('[FAIL] trigger-repo-committer exception: ' + $_.Exception.Message) -ForegroundColor Red
        & $markArchiveBlocked -lockNote "Archive blocked: repo-committer exception" -jobReason ("repo_committer_exception: " + $_.Exception.Message)
        exit 1
    }
    if (-not $commitResp) {
        Write-Host '[FAIL] trigger-repo-committer did not return machine-readable result.' -ForegroundColor Red
        & $markArchiveBlocked -lockNote "Archive blocked: repo-committer response invalid" -jobReason "repo_committer_response_invalid"
        exit 1
    }
    if ($commitResp.status -notin @("dispatched", "already_dispatched")) {
        Write-Host ('[FAIL] repo-committer dispatch failed: status=' + [string]$commitResp.status + ' message=' + [string]$commitResp.message) -ForegroundColor Red
        & $markArchiveBlocked -lockNote "Archive blocked: repo-committer dispatch failed" -jobReason ("repo_committer_dispatch_failed: " + [string]$commitResp.status)
        exit 1
    }
    $commitTaskId = [string]$commitResp.commitTaskId
    if (-not $commitTaskId) {
        Write-Host '[FAIL] repo-committer response missing commitTaskId.' -ForegroundColor Red
        & $markArchiveBlocked -lockNote "Archive blocked: repo-committer missing commitTaskId" -jobReason "repo_committer_missing_commit_task_id"
        exit 1
    }
    $commitPaneId = if ($commitResp.paneId) { [string]$commitResp.paneId } else { "" }
    $commitWorker = if ($commitResp.worker) { [string]$commitResp.worker } else { "repo-committer" }
    if ($commitPaneId) {
        Ensure-ApprovalRouter -TaskId $commitTaskId -WorkerName $commitWorker -WorkerPaneId $commitPaneId -TeamLeadPaneId $tlPaneId
    } else {
        Write-Host '[WARN] repo-committer pane not returned, cannot auto-attach approval-router.' -ForegroundColor Yellow
    }

    # 记录 archive job，交给 route-monitor 根据回调推进到 completed/blocked
    & $upsertArchiveJob -status "running" -docId $docTaskId -commitId $commitTaskId -docStatus "pending" -commitStatus "pending" -note "Archive running: waiting doc-updater + repo-committer success" -blockedReason ""

    Write-Host ('[OK] Archive flow started: ' + $TaskId) -ForegroundColor Green
    if ($archivedFile) {
        Write-Host ('     Task file: ' + $archivedFile) -ForegroundColor Gray
    }
    Write-Host ('     Doc task: ' + $docTaskId) -ForegroundColor Gray
    Write-Host ('     Commit task: ' + $commitTaskId) -ForegroundColor Gray
    Write-Host '     Final completion will be set by route-monitor after both tasks return success.' -ForegroundColor Cyan
}

# ============================================================
# Main Entry Point
# ============================================================
switch ($Action) {
    "bootstrap"   { Invoke-Bootstrap }
    "dispatch"    {
        $dispatchMutex = Enter-DispatchMutex
        try { Invoke-Dispatch } finally { if ($dispatchMutex) { try { $dispatchMutex.ReleaseMutex() | Out-Null } catch {}; try { $dispatchMutex.Dispose() } catch {} } }
    }
    "dispatch-qa" {
        $dispatchMutex = Enter-DispatchMutex
        try { Invoke-DispatchQA } finally { if ($dispatchMutex) { try { $dispatchMutex.ReleaseMutex() | Out-Null } catch {}; try { $dispatchMutex.Dispose() } catch {} } }
    }
    "status"      { Invoke-Status }
    "requeue"     { Invoke-Requeue }
    "recover"     { Invoke-Recover }
    "add-lock"    { Invoke-AddLock }
    "archive"     { Invoke-Archive }
    "approve-request" { Invoke-ApprovalDecision -decision 'approve' }
    "deny-request"    { Invoke-ApprovalDecision -decision 'deny' }
}
