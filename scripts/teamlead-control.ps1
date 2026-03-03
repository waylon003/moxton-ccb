#!/usr/bin/env pwsh
# teamlead-control.ps1 - Team Lead Unified Controller
# Single entry point, hard gates, minimal freedom
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action bootstrap
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action dispatch -TaskId BACKEND-009
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action dispatch-qa -TaskId BACKEND-009
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action status
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action recover -RecoverAction reap-stale
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action recover -RecoverAction baseline-clean
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action archive -TaskId SHOP-FE-004
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action approve-request -RequestId APR-20260228120000-0001
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action deny-request -RequestId APR-20260228120000-0001

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("bootstrap", "dispatch", "dispatch-qa", "status", "recover", "add-lock", "archive", "approve-request", "deny-request")]
    [string]$Action,

    [Parameter(Mandatory=$false)]
    [string]$TaskId,

    [Parameter(Mandatory=$false)]
    [ValidateSet("reap-stale", "restart-worker", "reset-task", "normalize-locks", "baseline-clean")]
    [string]$RecoverAction,

    [Parameter(Mandatory=$false)]
    [string]$WorkerName,

    [Parameter(Mandatory=$false)]
    [string]$TargetState,

    [Parameter(Mandatory=$false)]
    [string]$RequestId,

    [Parameter(Mandatory=$false)]
    [switch]$NoPush,

    [Parameter(Mandatory=$false)]
    [string]$CommitMessage,

    [Parameter(Mandatory=$false)]
    [switch]$DryRun
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
        return @{ version = "1.0"; updated_at = (Get-Date -Format "o"); locks = @{} }
    }
    $raw = Get-Content $taskLocksPath -Raw -Encoding UTF8
    return $raw | ConvertFrom-Json
}

function Write-TaskLocks($data) {
    $data.updated_at = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    $json = ($data | ConvertTo-Json -Depth 10)
    Write-Utf8NoBomFile -path $taskLocksPath -content $json
}

function Set-NoteField($obj, [string]$value) {
    if (-not $obj) { return }
    if (-not $obj.PSObject.Properties['note']) {
        $obj | Add-Member -NotePropertyName note -NotePropertyValue $value -Force
    } else {
        $obj.note = $value
    }
}

function Read-ArchiveJobs {
    if (-not (Test-Path $archiveJobsPath)) {
        return @{ version = "1.0"; updated_at = (Get-Date -Format "o"); jobs = @{} }
    }
    try {
        $raw = Get-Content $archiveJobsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $raw.jobs) {
            $raw | Add-Member -NotePropertyName jobs -NotePropertyValue @{} -Force
        }
        return $raw
    } catch {
        return @{ version = "1.0"; updated_at = (Get-Date -Format "o"); jobs = @{} }
    }
}

function Write-ArchiveJobs($data) {
    $data.updated_at = Get-Date -Format "o"
    $json = ($data | ConvertTo-Json -Depth 12)
    Write-Utf8NoBomFile -path $archiveJobsPath -content $json
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
        if ($cfg.dev) {
            $known[[string]$cfg.dev] = @{
                work_dir = [string]$cfg.workdir
                engine = if ($cfg.dev_engine) { [string]$cfg.dev_engine } else { [string]$cfg.engine }
            }
        }
        if ($cfg.qa) {
            $known[[string]$cfg.qa] = @{
                work_dir = [string]$cfg.workdir
                engine = if ($cfg.qa_engine) { [string]$cfg.qa_engine } else { [string]$cfg.engine }
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
            foreach ($t in $titles) {
                if ($t -like ("*" + $workerName + "*")) {
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
        $pid = if ($pane.pane_id) { [string]$pane.pane_id } else { "" }
        if ($pid) { [void]$set.Add($pid) }
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
        $pid = 0
        $pidStr = if ($entry.pid) { [string]$entry.pid } else { "" }
        $proc = $null
        $alive = $false
        if ([int]::TryParse($pidStr, [ref]$pid) -and $pid -gt 0) {
            $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
            $alive = ($null -ne $proc)
        }

        $paneId = if ($entry.worker_pane_id) { [string]$entry.worker_pane_id } else { "" }
        $paneAlive = ($paneId -and $livePanes.Contains($paneId))
        $entryWorkerUpper = if ($entry.worker) { ([string]$entry.worker).ToUpper() } else { "" }
        $sameWorkerDifferentTask = ($keepWorkerUpper -and $entryWorkerUpper -eq $keepWorkerUpper -and $name -ne $keepKey)

        $drop = (-not $alive) -or (-not $paneAlive) -or $sameWorkerDifferentTask
        if ($drop) {
            if ($alive -and $pid -gt 0) {
                Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
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
        Write-Host ('[FAIL] Task ' + $tid + " state='" + $st + "' not allowed.") -ForegroundColor Red
        Write-Host ('       Allowed: ' + $allowed) -ForegroundColor Yellow
        Write-Host ('       Reset: powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction reset-task -TaskId ' + $tid + ' -TargetState assigned') -ForegroundColor DarkGray
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

function Get-ExpectedWorkerForTaskState([string]$TaskId, [string]$State, $WorkerMap) {
    if (-not $TaskId -or -not $State -or -not $WorkerMap) { return $null }
    $prefix = Resolve-TaskPrefix $TaskId
    if (-not $prefix) { return $null }
    $cfg = $WorkerMap.$prefix
    if (-not $cfg) { return $null }
    switch ($State) {
        "in_progress" { return $cfg.dev }
        "qa" { return $cfg.qa }
        default { return $null }
    }
}

function Assert-NoExecutionDrift([string]$TaskId, $locks, $WorkerMap) {
    if (-not $TaskId -or -not $locks -or -not $WorkerMap) { return }
    if ($locks.locks.PSObject.Properties.Name -notcontains $TaskId) { return }
    $lock = $locks.locks.$TaskId
    if (-not $lock) { return }

    $state = if ($lock.state) { [string]$lock.state } else { "" }
    if ($state -notin @("in_progress", "qa")) { return }

    $expectedWorker = Get-ExpectedWorkerForTaskState -TaskId $TaskId -State $state -WorkerMap $WorkerMap
    if (-not $expectedWorker) { return }
    if (Test-WorkerPaneAlive -WorkerName $expectedWorker) { return }

    Write-Host ('[FAIL] Execution drift detected: task ' + $TaskId + ' state=' + $state + ' but worker offline (' + $expectedWorker + ')') -ForegroundColor Red
    Write-Host '       This usually happens when worker pane was closed manually.' -ForegroundColor Yellow
    Write-Host '       Recover with:' -ForegroundColor Yellow
    Write-Host ('         powershell -NoProfile -ExecutionPolicy Bypass -File "' + $scriptDir + '\teamlead-control.ps1" -Action recover -RecoverAction reap-stale') -ForegroundColor White
    Write-Host ('         powershell -NoProfile -ExecutionPolicy Bypass -File "' + $scriptDir + '\teamlead-control.ps1" -Action recover -RecoverAction reset-task -TaskId ' + $TaskId + ' -TargetState assigned') -ForegroundColor White
    Write-Host ('         powershell -NoProfile -ExecutionPolicy Bypass -File "' + $scriptDir + '\teamlead-control.ps1" -Action recover -RecoverAction restart-worker -WorkerName ' + $expectedWorker) -ForegroundColor White
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
    Write-Host '  dispatch    -- powershell -File scripts/teamlead-control.ps1 -Action dispatch -TaskId <ID>' -ForegroundColor White
    Write-Host '  dispatch-qa -- powershell -File scripts/teamlead-control.ps1 -Action dispatch-qa -TaskId <ID>' -ForegroundColor White
    Write-Host '  status      -- powershell -File scripts/teamlead-control.ps1 -Action status' -ForegroundColor White
    Write-Host '  recover     -- powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction <action>' -ForegroundColor White
    Write-Host '  archive     -- powershell -File scripts/teamlead-control.ps1 -Action archive -TaskId <ID> [-NoPush] [-CommitMessage "..."]' -ForegroundColor White
    Write-Host '  approve-request -- powershell -File scripts/teamlead-control.ps1 -Action approve-request -RequestId <ID>' -ForegroundColor White
    Write-Host '  deny-request    -- powershell -File scripts/teamlead-control.ps1 -Action deny-request -RequestId <ID>' -ForegroundColor White
    Write-Host ''
    Write-Host 'Approval Priority Rule:' -ForegroundColor Cyan
    Write-Host '  If pending approval requests exist, do NOT run sleep/wait. Approve or deny first.' -ForegroundColor Yellow
    Write-Host '  dispatch/dispatch-qa will auto-run baseline-clean (set TEAMLEAD_AUTO_BASELINE_CLEAN=0 to disable).' -ForegroundColor DarkGray
    Write-Host '  dispatch-qa defaults to fresh QA context (set TEAMLEAD_QA_REUSE_CONTEXT=1 to reuse QA session).' -ForegroundColor DarkGray
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
    Invoke-PreDispatchBaselineClean

    $workerMap = Get-WorkerMap
    $locks = Read-TaskLocks
    Assert-NoInvalidTaskLockEntries $locks
    Run-WorkerRegistryHealthCheck

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

    $devWorker = $wConfig.dev
    $domain = $wConfig.domain
    Assert-NoExecutionDrift -TaskId $TaskId -locks $locks -WorkerMap $workerMap

    # Assert state (only assigned/blocked -> in_progress)
    Assert-TaskState $TaskId @("assigned", "blocked") $locks

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
    $devEngine = if ($wConfig.dev_engine) { $wConfig.dev_engine } else { $wConfig.engine }
    $devConfig = @{ workdir = $wConfig.workdir; engine = $devEngine }
    $paneId = Ensure-WorkerRunning $devWorker $devConfig $tlPaneId

    # 先确保监控已启动，避免 dispatch 阶段出现审批提示但无人接管
    Ensure-RouteMonitor $tlPaneId
    Ensure-ApprovalRouter -TaskId $TaskId -WorkerName $devWorker -WorkerPaneId $paneId -TeamLeadPaneId $tlPaneId

    # Dispatch task (BEFORE updating lock)
    $dispatchScript = Join-Path $scriptDir "dispatch-task.ps1"
    & $dispatchScript -WorkerPaneId $paneId -WorkerName $devWorker -TaskId $TaskId -TaskFilePath $taskFile.FullName -Engine $devEngine -TeamLeadPaneId $tlPaneId
    $dispatchExit = $LASTEXITCODE
    if ($dispatchExit -ne 0) {
        Write-Host ('[FAIL] Dispatch failed for ' + $TaskId + ' (worker=' + $devWorker + ', pane=' + $paneId + ', exit=' + $dispatchExit + ')') -ForegroundColor Red
        Write-Host '       Task lock not updated. Please check worker pane output and rerun dispatch.' -ForegroundColor Yellow
        exit 1
    }

    # Update task lock AFTER successful dispatch
    $lockData = $locks.locks.$TaskId
    $lockData.state = "in_progress"
    $lockData.runner = $devEngine
    $lockData.updated_at = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    $lockData.updated_by = "teamlead-control/dispatch"
    Write-TaskLocks $locks

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
    Invoke-PreDispatchBaselineClean

    $workerMap = Get-WorkerMap
    $locks = Read-TaskLocks
    Assert-NoInvalidTaskLockEntries $locks
    Run-WorkerRegistryHealthCheck

    $prefix = Resolve-TaskPrefix $TaskId
    if (-not $prefix) {
        Write-Host ('[FAIL] Unknown task prefix: ' + $TaskId) -ForegroundColor Red
        exit 1
    }

    $wConfig = $workerMap.$prefix
    $qaWorker = $wConfig.qa
    $domain = $wConfig.domain
    Assert-NoExecutionDrift -TaskId $TaskId -locks $locks -WorkerMap $workerMap

    # Assert state (only waiting_qa -> qa)
    Assert-TaskState $TaskId @("waiting_qa") $locks

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

    $qaEngine = if ($wConfig.qa_engine) { $wConfig.qa_engine } else { $wConfig.engine }
    $qaConfig = @{ workdir = $wConfig.workdir; engine = $qaEngine }
    $reuseQaContext = [System.Environment]::GetEnvironmentVariable("TEAMLEAD_QA_REUSE_CONTEXT")
    $forceFreshQaContext = (-not $reuseQaContext -or $reuseQaContext.Trim() -ne "1")
    if ($forceFreshQaContext) {
        Write-Host '[INFO] QA dispatch uses fresh worker context (set TEAMLEAD_QA_REUSE_CONTEXT=1 to reuse existing QA session).' -ForegroundColor Cyan
    }
    $paneId = Ensure-WorkerRunning $qaWorker $qaConfig $tlPaneId -ForceRestart:$forceFreshQaContext

    # 先确保监控已启动，避免 dispatch 阶段出现审批提示但无人接管
    Ensure-RouteMonitor $tlPaneId
    Ensure-ApprovalRouter -TaskId $TaskId -WorkerName $qaWorker -WorkerPaneId $paneId -TeamLeadPaneId $tlPaneId

    # Dispatch FIRST, then update lock
    $dispatchScript = Join-Path $scriptDir "dispatch-task.ps1"
    & $dispatchScript -WorkerPaneId $paneId -WorkerName $qaWorker -TaskId $TaskId -TaskFilePath $taskFile.FullName -Engine $qaEngine -TeamLeadPaneId $tlPaneId
    $dispatchExit = $LASTEXITCODE
    if ($dispatchExit -ne 0) {
        Write-Host ('[FAIL] Dispatch QA failed for ' + $TaskId + ' (worker=' + $qaWorker + ', pane=' + $paneId + ', exit=' + $dispatchExit + ')') -ForegroundColor Red
        Write-Host '       Task lock not updated. Please check worker pane output and rerun dispatch-qa.' -ForegroundColor Yellow
        exit 1
    }

    # Update task lock AFTER successful dispatch
    $lockData = $locks.locks.$TaskId
    $lockData.state = "qa"
    $lockData.runner = $qaEngine
    $lockData.updated_at = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    $lockData.updated_by = "teamlead-control/dispatch-qa"
    Write-TaskLocks $locks

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
    $watcherCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\route-watcher.ps1" -FilterTask ' + $TaskId + ' -Timeout 0'
    Write-Host ('  Optional Bash(run_in_background: true): ' + $watcherCmd) -ForegroundColor DarkGray
    $approvalCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\approval-router.ps1" -WorkerPaneId ' + $paneId + ' -WorkerName ' + $qaWorker + ' -TaskId ' + $TaskId + ' -TeamLeadPaneId ' + $tlPaneId + ' -Timeout 0 -Continuous'
    Write-Host ('  (debug manual start): ' + $approvalCmd) -ForegroundColor DarkGray
    Write-Host ''
}

# ============================================================
# Action: status
# ============================================================
function Invoke-Status {
    Write-Host ''
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host '  Team Lead Status' -ForegroundColor Cyan
    Write-Host '==========================================' -ForegroundColor Cyan

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
            $expectedWorker = Get-ExpectedWorkerForTaskState -TaskId $tid -State ([string]$lState) -WorkerMap $workerMapForStatus
            if ($expectedWorker) {
                if (Test-WorkerPaneAlive -WorkerName $expectedWorker) {
                    $line += ' worker=' + $expectedWorker
                } else {
                    $line += ' worker=' + $expectedWorker + ' [OFFLINE-DRIFT]'
                    $stateColor = "Red"
                    $orphanLocks.Add($tid + '|' + $expectedWorker) | Out-Null
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
        $jobRows = @($archiveJobs.jobs.PSObject.Properties | ForEach-Object { $_.Value })
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
        $pendingTasks = @()
        if ($locks.locks.PSObject.Properties.Count -gt 0) {
            $locks.locks.PSObject.Properties | ForEach-Object {
                if ($_.Value.state -in @("assigned", "blocked")) {
                    $pendingTasks += $_.Name
                }
                if ($_.Value.state -eq "qa_passed") {
                    $qpName = $_.Name
                    Write-Host ('  [qa_passed] ' + $qpName + ' -- confirm completion or re-dispatch') -ForegroundColor Green
                }
            }
        }
        if ($pendingTasks.Count -gt 0) {
            $pendingStr = $pendingTasks -join ', '
            Write-Host ('  Pending tasks: ' + $pendingStr) -ForegroundColor Yellow
            foreach ($t in $pendingTasks) {
                Write-Host ('    powershell -File scripts/teamlead-control.ps1 -Action dispatch -TaskId ' + $t) -ForegroundColor White
            }
        } else {
            Write-Host '  No pending tasks' -ForegroundColor Green
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
            Write-Host '  Baseline cleanup:' -ForegroundColor Yellow
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
    $locks = Read-TaskLocks
    $locksChanged = $false
    $validLocks = @{}
    if ($locks.locks) {
        foreach ($p in $locks.locks.PSObject.Properties) {
            $tid = [string]$p.Name
            if ($tid -match '^(BACKEND|SHOP-FE|ADMIN-FE)-\d+$') {
                $validLocks[$tid] = $p.Value
            } else {
                $summary.lock_keys_removed++
                $locksChanged = $true
            }
        }
    }
    $locks.locks = $validLocks

    $activeTaskIds = Get-ActiveTaskIdSet
    $pendingTaskIds = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($req in @($approvals.requests | Where-Object { $_.status -eq 'pending' })) {
        $reqTask = if ($req.task) { [string]$req.task } elseif ($req.task_id) { [string]$req.task_id } else { "" }
        if ($reqTask) { [void]$pendingTaskIds.Add($reqTask.ToUpper()) }
    }

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
            if ($lock.PSObject.Properties.Name -contains 'routeUpdate') {
                $lock.PSObject.Properties.Remove('routeUpdate')
            }
            $locks.locks[$tid] = $lock
            $summary.blocked_to_assigned++
            $locksChanged = $true
        }
    }

    if ($locksChanged) {
        Write-TaskLocks $locks
    }

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
        Write-Host '[FAIL] recover requires -RecoverAction (reap-stale / restart-worker / reset-task / normalize-locks / baseline-clean)' -ForegroundColor Red
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
                if ($cfg.dev -eq $WorkerName -or $cfg.qa -eq $WorkerName) {
                    $wConfig = $cfg
                }
            }
            if (-not $wConfig) {
                Write-Host ('[FAIL] Worker ' + $WorkerName + ' not in worker-map.json') -ForegroundColor Red
                exit 1
            }

            $regScript = Join-Path $scriptDir "worker-registry.ps1"
            & $regScript -Action unregister -WorkerName $WorkerName 2>$null

            $isQa = $WorkerName -like '*-qa'
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
            $locks.locks.$TaskId.state = $TargetState
            $locks.locks.$TaskId.updated_at = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
            $locks.locks.$TaskId.updated_by = "teamlead-control/recover"
            Set-NoteField -obj $locks.locks.$TaskId -value "Manual reset to $TargetState"
            Write-TaskLocks $locks
            Write-Host ('[OK] Task ' + $TaskId + ' reset to ' + $TargetState) -ForegroundColor Green
        }

        "normalize-locks" {
            $locks = Read-TaskLocks
            $validLocks = @{}
            $removed = New-Object System.Collections.Generic.List[string]
            if ($locks.locks) {
                foreach ($p in $locks.locks.PSObject.Properties) {
                    $k = [string]$p.Name
                    if ($k -match '^(BACKEND|SHOP-FE|ADMIN-FE)-\d+$') {
                        $validLocks[$k] = $p.Value
                    } else {
                        $removed.Add($k) | Out-Null
                    }
                }
            }
            $locks.locks = $validLocks
            Write-TaskLocks $locks
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
        note = ""
    }

    # Add to locks (convert PSCustomObject to hashtable for mutation)
    $locksHash = @{}
    $locks.locks.PSObject.Properties | ForEach-Object { $locksHash[$_.Name] = $_.Value }
    $locksHash[$TaskId] = $newLock
    $locks.locks = $locksHash
    Write-TaskLocks $locks

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
            $jobsHashLocal = @{}
            if ($jobsLocal.jobs) {
                foreach ($p in $jobsLocal.jobs.PSObject.Properties) { $jobsHashLocal[$p.Name] = $p.Value }
            }
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
        $locksLocal = Read-TaskLocks
        if ($locksLocal.locks.PSObject.Properties.Name -contains $TaskId) {
            $locksLocal.locks.$TaskId.state = "blocked"
            $locksLocal.locks.$TaskId.updated_at = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
            $locksLocal.locks.$TaskId.updated_by = "teamlead-control/archive"
            Set-NoteField -obj $locksLocal.locks.$TaskId -value $lockNote
            Write-TaskLocks $locksLocal
        }
        & $upsertArchiveJob -status "blocked" -docId $docTaskId -commitId $commitTaskId -docStatus "blocked" -commitStatus "blocked" -note $lockNote -blockedReason $jobReason
    }

    # 先落一条 archive job，避免中途异常导致锁在 archiving 但无 job 可追踪
    & $upsertArchiveJob -status "starting" -docId "" -commitId "" -docStatus "pending" -commitStatus "pending" -note "Archive initializing" -blockedReason ""

    # 先进入 archiving 中间态，等待 doc-updater + repo-committer 回传收口
    $locks.locks.$TaskId.state = "archiving"
    $locks.locks.$TaskId.updated_at = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    $locks.locks.$TaskId.updated_by = "teamlead-control/archive"
    Set-NoteField -obj $locks.locks.$TaskId -value "Archive started: waiting doc-updater + repo-committer"
    Write-TaskLocks $locks
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
    "dispatch"    { Invoke-Dispatch }
    "dispatch-qa" { Invoke-DispatchQA }
    "status"      { Invoke-Status }
    "recover"     { Invoke-Recover }
    "add-lock"    { Invoke-AddLock }
    "archive"     { Invoke-Archive }
    "approve-request" { Invoke-ApprovalDecision -decision 'approve' }
    "deny-request"    { Invoke-ApprovalDecision -decision 'deny' }
}
