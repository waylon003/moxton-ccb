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
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action approve-request -RequestId APR-20260228120000-0001
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action deny-request -RequestId APR-20260228120000-0001

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("bootstrap", "dispatch", "dispatch-qa", "status", "recover", "add-lock", "approve-request", "deny-request")]
    [string]$Action,

    [Parameter(Mandatory=$false)]
    [string]$TaskId,

    [Parameter(Mandatory=$false)]
    [ValidateSet("reap-stale", "restart-worker", "reset-task")]
    [string]$RecoverAction,

    [Parameter(Mandatory=$false)]
    [string]$WorkerName,

    [Parameter(Mandatory=$false)]
    [string]$TargetState,

    [Parameter(Mandatory=$false)]
    [string]$RequestId,

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
$approvalRequestsPath = Join-Path $rootDir "mcp\route-server\data\approval-requests.json"

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

function Send-ApprovalDecisionToPane($paneId, $decision) {
    $key = if ($decision -eq 'approve') { 'y' } else { 'n' }
    wezterm cli send-text --pane-id $paneId --no-paste $key | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host ('[FAIL] Failed to send approval decision to pane ' + $paneId) -ForegroundColor Red
        exit 1
    }
    Start-Sleep -Milliseconds 200
    wezterm cli send-text --pane-id $paneId --no-paste "`r" | Out-Null
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

function Ensure-WorkerRunning($wName, $wConfig, $tlPaneId) {
    $regScript = Join-Path $scriptDir "worker-registry.ps1"
    try {
        $paneId = & $regScript -Action get -WorkerName $wName 2>$null
        if ($paneId -and $LASTEXITCODE -eq 0) {
            Write-Host ('[OK] Worker ' + $wName + ' online (pane ' + $paneId + ')') -ForegroundColor Green
            return $paneId
        }
    } catch {}

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
    Write-Host '  approve-request -- powershell -File scripts/teamlead-control.ps1 -Action approve-request -RequestId <ID>' -ForegroundColor White
    Write-Host '  deny-request    -- powershell -File scripts/teamlead-control.ps1 -Action deny-request -RequestId <ID>' -ForegroundColor White
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

    $tlPaneId = Resolve-TeamLeadPaneId
    $workerMap = Get-WorkerMap
    $locks = Read-TaskLocks

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

    # Dispatch task (BEFORE updating lock)
    $dispatchScript = Join-Path $scriptDir "dispatch-task.ps1"
    & $dispatchScript -WorkerPaneId $paneId -WorkerName $devWorker -TaskId $TaskId -TaskFilePath $taskFile.FullName -Engine $devEngine -TeamLeadPaneId $tlPaneId

    # Update task lock AFTER successful dispatch
    $lockData = $locks.locks.$TaskId
    $lockData.state = "in_progress"
    $lockData.runner = $devEngine
    $lockData.updated_at = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    $lockData.updated_by = "teamlead-control/dispatch"
    Write-TaskLocks $locks

    # Ensure route monitor is alive for auto lock/doc-updater processing
    Ensure-RouteMonitor $tlPaneId

    Write-Host ''
    Write-Host ('[OK] Task ' + $TaskId + ' dispatched to ' + $devWorker + ' (pane ' + $paneId + ')') -ForegroundColor Green
    Write-Host ''
    Write-Host '[NEXT] Start background watchers:' -ForegroundColor Cyan
    $watcherCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\route-watcher.ps1" -FilterTask ' + $TaskId + ' -Timeout 600'
    Write-Host ('  Bash(run_in_background: true): ' + $watcherCmd) -ForegroundColor White
    $approvalCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\approval-router.ps1" -WorkerPaneId ' + $paneId + ' -WorkerName ' + $devWorker + ' -TaskId ' + $TaskId + ' -TeamLeadPaneId ' + $tlPaneId + ' -Timeout 600'
    Write-Host ('  Bash(run_in_background: true): ' + $approvalCmd) -ForegroundColor White
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

    $tlPaneId = Resolve-TeamLeadPaneId
    $workerMap = Get-WorkerMap
    $locks = Read-TaskLocks

    $prefix = Resolve-TaskPrefix $TaskId
    if (-not $prefix) {
        Write-Host ('[FAIL] Unknown task prefix: ' + $TaskId) -ForegroundColor Red
        exit 1
    }

    $wConfig = $workerMap.$prefix
    $qaWorker = $wConfig.qa
    $domain = $wConfig.domain

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
    $paneId = Ensure-WorkerRunning $qaWorker $qaConfig $tlPaneId

    # Dispatch FIRST, then update lock
    $dispatchScript = Join-Path $scriptDir "dispatch-task.ps1"
    & $dispatchScript -WorkerPaneId $paneId -WorkerName $qaWorker -TaskId $TaskId -TaskFilePath $taskFile.FullName -Engine $qaEngine -TeamLeadPaneId $tlPaneId

    # Update task lock AFTER successful dispatch
    $lockData = $locks.locks.$TaskId
    $lockData.state = "qa"
    $lockData.runner = $qaEngine
    $lockData.updated_at = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    $lockData.updated_by = "teamlead-control/dispatch-qa"
    Write-TaskLocks $locks

    # Ensure route monitor is alive for auto lock/doc-updater processing
    Ensure-RouteMonitor $tlPaneId

    Write-Host ''
    Write-Host ('[OK] QA task ' + $TaskId + ' dispatched to ' + $qaWorker + ' (pane ' + $paneId + ')') -ForegroundColor Green
    Write-Host ''
    Write-Host '[NEXT] Start background watchers:' -ForegroundColor Cyan
    $watcherCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\route-watcher.ps1" -FilterTask ' + $TaskId + ' -Timeout 600'
    Write-Host ('  Bash(run_in_background: true): ' + $watcherCmd) -ForegroundColor White
    $approvalCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\approval-router.ps1" -WorkerPaneId ' + $paneId + ' -WorkerName ' + $qaWorker + ' -TaskId ' + $TaskId + ' -TeamLeadPaneId ' + $tlPaneId + ' -Timeout 600'
    Write-Host ('  Bash(run_in_background: true): ' + $approvalCmd) -ForegroundColor White
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
    }{}
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
    $regScript = Join-Path $scriptDir "worker-registry.ps1"
    if (Test-Path $regScript) {
        try { & $regScript -Action list } catch { Write-Host '  (registry list error, run health-check)' -ForegroundColor Yellow }
    }

    # MCP Route Inbox
    Write-Host '--- Route Inbox ---' -ForegroundColor Cyan
    $inboxPath = Join-Path $rootDir "mcp\route-server\data\route-inbox.json"
    if (Test-Path $inboxPath) {
        $inbox = Get-Content $inboxPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $pending = $inbox.routes | Where-Object { -not $_.processed }
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
    $approvals = Read-ApprovalRequests
    $pendingApprovals = @($approvals.requests | Where-Object { $_.status -eq 'pending' })
    if ($pendingApprovals.Count -gt 0) {
        foreach ($req in $pendingApprovals) {
            $reqColor = if ($req.risk -eq 'low') { 'Yellow' } else { 'Red' }
            Write-Host ('  ' + $req.id + ' task=' + $req.task + ' worker=' + $req.worker + ' risk=' + $req.risk) -ForegroundColor $reqColor
        }
    } else {
        Write-Host '  (no pending approval requests)' -ForegroundColor Gray
    }

    # Task locks
    Write-Host ''
    Write-Host '--- Task Locks ---' -ForegroundColor Cyan
    $locks = Read-TaskLocks
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
                "assigned"    { "White" }
                "blocked"     { "Red" }
                "fail"        { "Red" }
                default       { "Gray" }
            }
            $tidPad = $tid.PadRight(18)
            $lState = $l.state
            Write-Host ('  ' + $tidPad + ' state=' + $lState) -ForegroundColor $stateColor
        }
    }
    if (-not $hasLocks) {
        Write-Host '  (no task locks)' -ForegroundColor Gray
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
    }
    Write-Host ''
}

# ============================================================
# Action: recover
# ============================================================
function Invoke-Recover {
    if (-not $RecoverAction) {
        Write-Host '[FAIL] recover requires -RecoverAction (reap-stale / restart-worker / reset-task)' -ForegroundColor Red
        exit 1
    }

    $tlPaneId = Resolve-TeamLeadPaneId

    switch ($RecoverAction) {
        "reap-stale" {
            Write-Host '[INFO] Cleaning stale worker registrations...' -ForegroundColor Yellow
            $regScript = Join-Path $scriptDir "worker-registry.ps1"
            & $regScript -Action health-check

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
            $locks.locks.$TaskId.note = "Manual reset to $TargetState"
            Write-TaskLocks $locks
            Write-Host ('[OK] Task ' + $TaskId + ' reset to ' + $TargetState) -ForegroundColor Green
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

    $approvals = Read-ApprovalRequests
    $req = $approvals.requests | Where-Object { $_.id -eq $RequestId } | Select-Object -First 1
    if (-not $req) {
        Write-Host ('[FAIL] Approval request not found: ' + $RequestId) -ForegroundColor Red
        exit 1
    }
    if ($req.status -ne 'pending') {
        Write-Host ('[FAIL] Approval request is not pending: ' + $RequestId + ' (status=' + $req.status + ')') -ForegroundColor Red
        exit 1
    }

    Send-ApprovalDecisionToPane -paneId $req.worker_pane_id -decision $decision

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
# Main Entry Point
# ============================================================
switch ($Action) {
    "bootstrap"   { Invoke-Bootstrap }
    "dispatch"    { Invoke-Dispatch }
    "dispatch-qa" { Invoke-DispatchQA }
    "status"      { Invoke-Status }
    "recover"     { Invoke-Recover }
    "add-lock"    { Invoke-AddLock }
    "approve-request" { Invoke-ApprovalDecision -decision 'approve' }
    "deny-request"    { Invoke-ApprovalDecision -decision 'deny' }
}
