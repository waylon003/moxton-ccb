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
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-task -TaskId BACKEND-009
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action archive -TaskId SHOP-FE-004
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action show-approval -RequestId APR-20260228120000-0001
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action approve-request -RequestId APR-20260228120000-0001
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action deny-request -RequestId APR-20260228120000-0001
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action approve-local -WorkerName shop-fe-qa [-PromptType auto|command_approval|edit_confirm|menu_approval]
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action approve-local-session -WorkerName shop-fe-qa [-PromptType auto|menu_approval]
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/teamlead-control.ps1 -Action deny-local -WorkerName shop-fe-qa [-PromptType auto|command_approval|edit_confirm|menu_approval]

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("bootstrap", "dispatch", "dispatch-qa", "status", "notify-ready", "requeue", "recover", "add-lock", "archive", "show-approval", "approve-request", "deny-request", "approve-local", "approve-local-session", "deny-local")]
    [string]$Action,

    [Parameter(Mandatory=$false)]
    [string]$TaskId,

    [Parameter(Mandatory=$false)]
    [ValidateSet("reap-stale", "restart-task", "restart-worker", "reset-task", "normalize-locks", "baseline-clean", "full-clean")]
    [string]$RecoverAction,

    [Parameter(Mandatory=$false)]
    [string]$WorkerName,

    [Parameter(Mandatory=$false)]
    [string]$TargetState,

    [Parameter(Mandatory=$false)]
    [string]$RequestId,

    [Parameter(Mandatory=$false)]
    [ValidateSet("auto", "command_approval", "edit_confirm", "menu_approval")]
    [string]$PromptType = "auto",


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

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        chcp 65001 | Out-Null
    }
} catch {}
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
$taskLocksPath = Join-Path $rootDir "01-tasks\TASK-LOCKS.json"
$workerMapPath = Join-Path $rootDir "config\worker-map.json"
$registryPath = Join-Path $rootDir "config\worker-panels.json"
$bootstrapFlag = Join-Path $env:TEMP "moxton-bootstrap-done.flag"
$monitorPidFile = Join-Path $env:TEMP "moxton-route-monitor.pid"
$monitorPaneFile = Join-Path $env:TEMP "moxton-route-monitor-pane.id"
$notifierPidFile = Join-Path $env:TEMP "moxton-route-notifier.pid"
$notifierPaneFile = Join-Path $env:TEMP "moxton-route-notifier-pane.id"
$richMonitorPidFile = Join-Path $env:TEMP "moxton-rich-monitor.pid"
$richMonitorPaneFile = Join-Path $env:TEMP "moxton-rich-monitor-pane.id"
$paneApprovalWatcherStatePath = Join-Path $rootDir "config\pane-approval-watchers.json"
$localApprovalEventsPath = Join-Path $rootDir "config\local-approval-events.jsonl"
$localApprovalStatePath = Join-Path $rootDir "config\local-approval-state.json"
$approvalRequestsPath = Join-Path $rootDir "mcp\route-server\data\approval-requests.json"
$docSyncStatePath = Join-Path $rootDir "config\api-doc-sync-state.json"
$archiveJobsPath = Join-Path $rootDir "config\archive-jobs.json"
$taskAttemptHistoryPath = Join-Path $rootDir "config\task-attempt-history.json"
$notifySentinelReadyPath = Join-Path $rootDir "config\notify-sentinel.ready.json"
$routeMonitorStatePath = Join-Path $rootDir "config\route-monitor-state.json"
$routeNotifierStatePath = Join-Path $rootDir "config\route-notifier-state.json"
$richMonitorStatePath = Join-Path $rootDir "config\rich-monitor-state.json"
$teamLeadDeliveryLogPath = Join-Path $rootDir "config\teamlead-delivery.jsonl"
$teamLeadDeliveryFailureLogPath = Join-Path $rootDir "config\teamlead-delivery-failures.jsonl"
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


function Append-Utf8Line([string]$path, [string]$line) {
    if ([string]::IsNullOrWhiteSpace($path) -or [string]::IsNullOrWhiteSpace($line)) { return }
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $writer = New-Object System.IO.StreamWriter($path, $true, $utf8NoBom)
    try {
        $writer.WriteLine($line)
    } finally {
        $writer.Dispose()
    }
}

function Convert-ToObjectMap($source) {
    $map = @{}
    if ($null -eq $source) { return $map }
    if ($source -is [System.Collections.IDictionary]) {
        foreach ($key in $source.Keys) {
            $name = [string]$key
            if ($name) { $map[$name] = $source[$key] }
        }
        return $map
    }
    foreach ($prop in $source.PSObject.Properties) {
        $name = [string]$prop.Name
        if ($name) { $map[$name] = $prop.Value }
    }
    return $map
}

function Read-LocalApprovalState {
    if (-not (Test-Path $localApprovalStatePath)) {
        return @{ updated_at = (Get-Date -Format "o"); workers = @{} }
    }
    try {
        $raw = Get-Content $localApprovalStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $raw.workers) {
            $raw | Add-Member -NotePropertyName workers -NotePropertyValue @{} -Force
        } elseif (-not ($raw.workers -is [System.Collections.IDictionary])) {
            $raw.workers = Convert-ToObjectMap $raw.workers
        }
        return $raw
    } catch {
        return @{ updated_at = (Get-Date -Format "o"); workers = @{} }
    }
}

function Write-LocalApprovalState($state) {
    if (-not $state) {
        $state = @{ updated_at = (Get-Date -Format "o"); workers = @{} }
    }
    if (-not $state.workers) { $state.workers = @{} }
    if (-not ($state.workers -is [System.Collections.IDictionary])) {
        $state.workers = Convert-ToObjectMap $state.workers
    }
    $state.updated_at = Get-Date -Format "o"
    Write-Utf8NoBomFile -path $localApprovalStatePath -content ($state | ConvertTo-Json -Depth 10)
}

function Update-LocalApprovalStateEntry([string]$WorkerName, [scriptblock]$Mutator) {
    if (-not $WorkerName) { return $null }
    $state = Read-LocalApprovalState
    $workers = Convert-ToObjectMap $state.workers
    $current = $null
    if ($workers.ContainsKey($WorkerName)) {
        $current = $workers[$WorkerName]
    }
    $next = & $Mutator $current
    if ($null -eq $next) {
        if ($workers.ContainsKey($WorkerName)) {
            $workers.Remove($WorkerName) | Out-Null
        }
    } else {
        $workers[$WorkerName] = $next
    }
    $state.workers = $workers
    Write-LocalApprovalState $state
    return $next
}

function Append-LocalApprovalEvent($record) {
    if (-not $record) { return }
    Append-Utf8Line -path $localApprovalEventsPath -line ($record | ConvertTo-Json -Compress -Depth 10)
}

function Mark-LocalApprovalResolved([string]$WorkerName, [string]$Decision, [string]$PromptType, [string]$ResolvedBy) {
    if (-not $WorkerName) { return }
    $resolvedAt = Get-Date -Format "o"
    $entry = Update-LocalApprovalStateEntry -WorkerName $WorkerName -Mutator {
        param($current)
        if (-not $current) { return $null }
        $current.status = "resolved"
        $current.decision = if ($Decision) { $Decision } else { "" }
        if ($PromptType) { $current.prompt_type = $PromptType }
        $current.resolved_at = $resolvedAt
        $current.resolved_by = if ($ResolvedBy) { $ResolvedBy } else { "teamlead-control" }
        $current.updated_at = $resolvedAt
        return $current
    }
    if ($entry) {
        Append-LocalApprovalEvent @{
            at = $resolvedAt
            kind = "local_approval_resolution"
            worker = $WorkerName
            task = if ($entry.task) { [string]$entry.task } else { "" }
            pane_id = if ($entry.pane_id) { [string]$entry.pane_id } else { "" }
            run_id = if ($entry.run_id) { [string]$entry.run_id } else { "" }
            prompt_type = if ($entry.prompt_type) { [string]$entry.prompt_type } else { "" }
            decision = if ($Decision) { $Decision } else { "" }
            resolved_by = if ($ResolvedBy) { $ResolvedBy } else { "teamlead-control" }
            fingerprint = if ($entry.fingerprint) { [string]$entry.fingerprint } else { "" }
            preview = if ($entry.preview) { [string]$entry.preview } else { "" }
            event_id = if ($entry.event_id) { [string]$entry.event_id } else { "" }
        }
    }
}

function Clear-LocalApprovalState([string]$WorkerName) {
    if (-not $WorkerName) { return }
    Update-LocalApprovalStateEntry -WorkerName $WorkerName -Mutator { param($current) return $null } | Out-Null
}

function Read-NotifySentinelReady {
    if (-not (Test-Path $notifySentinelReadyPath)) { return $null }
    try {
        return (Get-Content $notifySentinelReadyPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Write-NotifySentinelReady {
    param(
        [string]$Source,
        [string]$Note,
        [string]$Wezterm,
        [int]$Workers = 0
    )
    $payload = [ordered]@{
        at = (Get-Date -Format "o")
        source = if ($Source) { $Source } else { "manual" }
        note = if ($Note) { $Note } else { "" }
        wezterm = if ($Wezterm) { $Wezterm } else { "" }
        workers = $Workers
        user = if ($env:USERNAME) { $env:USERNAME } else { "" }
        pid = [int]$PID
    }
    Write-Utf8NoBomFile -path $notifySentinelReadyPath -content ($payload | ConvertTo-Json -Depth 6)
    return [pscustomobject]$payload
}

function Read-JsonLinesFile {
    param(
        [string]$Path,
        [int]$Tail = 0
    )
    if (-not (Test-Path $Path)) { return @() }
    try {
        $lines = if ($Tail -gt 0) {
            @(Get-Content $Path -Encoding UTF8 -Tail $Tail)
        } else {
            @(Get-Content $Path -Encoding UTF8)
        }
    } catch {
        return @()
    }

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $items.Add(($line | ConvertFrom-Json)) | Out-Null
        } catch {}
    }
    return @($items.ToArray())
}

function Get-TeamLeadDeliverySnapshot {
    $monitor = Read-RouteMonitorState
    $notifier = Read-RouteNotifierState
    $rich = Read-RichMonitorState

    $records = @(Read-JsonLinesFile -Path $teamLeadDeliveryLogPath -Tail 200)
    $failureRecords = @(Read-JsonLinesFile -Path $teamLeadDeliveryFailureLogPath -Tail 80 | Sort-Object at -Descending)
    $latestByEvent = @{}
    foreach ($record in @($records | Sort-Object at)) {
        $eventId = if ($record.event_id) { [string]$record.event_id } else { 'event-' + [guid]::NewGuid().ToString('N') }
        $latestByEvent[$eventId] = $record
    }

    $unresolved = @($latestByEvent.Values | Where-Object { -not [bool]$_.sent } | Sort-Object at -Descending)
    $successCount = @($records | Where-Object { [bool]$_.sent }).Count
    $failureCount = @($records | Where-Object { -not [bool]$_.sent }).Count

    return [pscustomobject]@{
        monitor = $monitor
        notifier = $notifier
        rich = $rich
        success_count = $successCount
        failure_count = $failureCount
        unresolved = $unresolved
        recent_failures = $failureRecords
    }
}
function Assert-NotifySentinelReady {
    return
}

function Invoke-NotifyReady {
    Write-Host '[INFO] notify-ready 已弃用。当前由 route-monitor 写事件、route-notifier 独立通知 Team Lead，无需 notify-sentinel ready 标记。' -ForegroundColor Yellow
}
function Resolve-TeamLeadPaneId {
    $currentPane = Normalize-PaneId ([string]$env:WEZTERM_PANE)
    if (-not $currentPane) {
        $currentPane = Normalize-PaneId ([string]$env:WEZTERM_PANE_ID)
    }
    if ($currentPane) {
        $env:TEAM_LEAD_PANE_ID = $currentPane
        return $env:TEAM_LEAD_PANE_ID
    }

    $normalizedEnvTeamLead = Normalize-PaneId ([string]$env:TEAM_LEAD_PANE_ID)
    if ($normalizedEnvTeamLead) {
        $env:TEAM_LEAD_PANE_ID = $normalizedEnvTeamLead
        return $env:TEAM_LEAD_PANE_ID
    }

    Write-Host '[FAIL] Cannot reliably detect Team Lead Pane ID.' -ForegroundColor Red
    Write-Host '       请在真正的 Team Lead WezTerm pane 内执行，或先显式设置 $env:TEAM_LEAD_PANE_ID。' -ForegroundColor Yellow
    Write-Host '       示例：$env:TEAM_LEAD_PANE_ID = $env:WEZTERM_PANE' -ForegroundColor DarkGray
    return $null
}

function Assert-TeamLeadPaneId([string]$PaneId, [string]$ActionName = 'action') {
    if ($PaneId) { return }
    Write-Host ('[FAIL] Missing Team Lead Pane ID for ' + $ActionName + '.') -ForegroundColor Red
    Write-Host '       请切到真正的 Team Lead WezTerm pane 后重试，或先执行：' -ForegroundColor Yellow
    Write-Host '       $env:TEAM_LEAD_PANE_ID = $env:WEZTERM_PANE' -ForegroundColor White
    exit 1
}

function Normalize-PaneId([string]$value) {
    if (-not $value) { return $null }
    $trimmed = $value.Trim()
    if ($trimmed -match '(\d+)') {
        return $Matches[1]
    }
    return $null
}

function Read-ProcessStateFile([string]$Path) {
    if (-not $Path -or -not (Test-Path $Path)) { return $null }
    try {
        return (Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Read-RouteMonitorState {
    return (Read-ProcessStateFile -Path $routeMonitorStatePath)
}

function Read-RouteNotifierState {
    return (Read-ProcessStateFile -Path $routeNotifierStatePath)
}

function Read-RichMonitorState {
    return (Read-ProcessStateFile -Path $richMonitorStatePath)
}

function Test-RichMonitorEnabled {
    $raw = [string]$env:CCB_DISABLE_RICH_MONITOR
    if (-not $raw) { return $true }
    switch ($raw.Trim().ToLowerInvariant()) {
        '1' { return $false }
        'true' { return $false }
        'yes' { return $false }
        'on' { return $false }
        default { return $true }
    }
}

function Get-RichMonitorPaneId {
    return (Get-TrackedPaneId -PaneFile $richMonitorPaneFile -StatePath $richMonitorStatePath -StateField 'monitor_pane_id')
}

function Get-TrackedPaneId([string]$PaneFile, [string]$StatePath, [string]$StateField) {
    if ($PaneFile -and (Test-Path $PaneFile)) {
        try {
            $paneId = Normalize-PaneId ((Get-Content $PaneFile -Raw -Encoding UTF8).Trim())
            if ($paneId) { return $paneId }
        } catch {}
    }
    $state = Read-ProcessStateFile -Path $StatePath
    if ($state -and $StateField -and $state.PSObject.Properties.Name -contains $StateField) {
        $value = $state.$StateField
        if ($value) { return (Normalize-PaneId ([string]$value)) }
    }
    return $null
}

function Get-RouteMonitorPaneId {
    return (Get-TrackedPaneId -PaneFile $monitorPaneFile -StatePath $routeMonitorStatePath -StateField 'monitor_pane_id')
}

function Get-RouteNotifierPaneId {
    return (Get-TrackedPaneId -PaneFile $notifierPaneFile -StatePath $routeNotifierStatePath -StateField 'notifier_pane_id')
}

function Get-LockRouteBodyPreview($Lock) {
    if (-not $Lock) { return '' }
    if ($Lock.routeUpdate -and $Lock.routeUpdate.bodyPreview) {
        return [string]$Lock.routeUpdate.bodyPreview
    }
    foreach ($candidate in @($Lock.note, $Lock.message, $Lock.reason)) {
        if ($candidate) { return [string]$candidate }
    }
    return ''
}

function Get-BlockedDecision([string]$body) {
    if (-not $body) { return 'unknown' }
    $text = $body.ToLowerInvariant()
    if ($text -match '3033|health' -or $text -match 'connection refused|econnrefused|port .* closed|service unavailable|server not started|unreachable') {
        return 'service_down'
    }
    if ($text -match 'pre-existing|dirty state|working tree|uncommitted|git status|modified files|already modified|baseline') {
        return 'dirty_state'
    }
    if ($text -match 'credential|credentials|token|login|password|no credentials|sec_e_no_credentials|auth') {
        return 'missing_credentials'
    }
    return 'unknown'
}

function Get-BackendServiceRestoreTaskId {
    $candidate = Join-Path $rootDir '01-tasks\active\backend\BACKEND-016-start-backend-dev-server.md'
    if (Test-Path $candidate) { return 'BACKEND-016' }
    return $null
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

function Get-LockDispatchMode($lock) {
    if (-not $lock) { return 'pane' }
    if ($lock.PSObject.Properties.Name -contains 'dispatch_mode' -and $lock.dispatch_mode) {
        $mode = ([string]$lock.dispatch_mode).Trim().ToLowerInvariant()
        if ($mode) { return $mode }
    }
    return 'pane'
}

function Test-ProcessAliveById([int]$ProcessId) {
    if ($ProcessId -le 0) { return $false }
    try {
        $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        return ($null -ne $proc)
    } catch {
        return $false
    }
}

function Read-HeadlessRunSnapshot([string]$TaskId, $Lock) {
    if (-not $Lock) { return $null }
    $dispatchMode = Get-LockDispatchMode -lock $Lock
    if ($dispatchMode -ne 'headless') { return $null }

    $runDir = ''
    if ($Lock.PSObject.Properties.Name -contains 'headless_run_dir' -and $Lock.headless_run_dir) {
        $runDir = [string]$Lock.headless_run_dir
    }
    if (-not $runDir -and $TaskId -and $Lock.PSObject.Properties.Name -contains 'run_id' -and $Lock.run_id) {
        $safeTask = ($TaskId -replace '[^A-Za-z0-9\-]', '-')
        $runDir = Join-Path (Join-Path $rootDir 'runtime\runs') $safeTask
        $runDir = Join-Path $runDir ([string]$Lock.run_id)
    }

    $statePath = if ($runDir) { Join-Path $runDir 'state.json' } else { '' }
    $state = if ($statePath) { Read-ProcessStateFile -Path $statePath } else { $null }
    $runtimeUpdatedUtc = $null
    if ($state) {
        $updatedCandidate = if ($state.updated_at) { [string]$state.updated_at } elseif ($state.started_at) { [string]$state.started_at } else { '' }
        if ($updatedCandidate) {
            $runtimeUpdatedUtc = ConvertTo-UtcDateSafe $updatedCandidate
        }
    }

    $processId = 0
    if ($Lock.PSObject.Properties.Name -contains 'headless_pid' -and $Lock.headless_pid) {
        try { $processId = [int]$Lock.headless_pid } catch { $processId = 0 }
    }
    $processAlive = Test-ProcessAliveById -ProcessId $processId

    return [pscustomobject]@{
        dispatch_mode = 'headless'
        run_dir = $runDir
        state_path = $statePath
        process_id = $processId
        process_alive = $processAlive
        runtime_status = if ($state -and $state.status) { [string]$state.status } else { '' }
        runtime_phase = if ($state -and $state.phase) { [string]$state.phase } else { '' }
        runtime_note = if ($state -and $state.note) { [string]$state.note } else { '' }
        runtime_updated_utc = $runtimeUpdatedUtc
        runtime_updated_age = if ($runtimeUpdatedUtc) { Get-TaskActivityAgeText -ActivityUtc $runtimeUpdatedUtc } else { '-' }
        exit_code = if ($state -and $state.PSObject.Properties.Name -contains 'exit_code' -and $state.exit_code -ne $null) { [int]$state.exit_code } else { -1 }
    }
}

function Clear-TaskRuntimeFields($lock, [switch]$ClearAssignedWorker, [switch]$ClearDispatchMode) {
    if (-not $lock) { return }
    Set-ObjectField -obj $lock -name 'run_id' -value ''
    Set-ObjectField -obj $lock -name 'headless_run_dir' -value ''
    Set-ObjectField -obj $lock -name 'headless_pid' -value 0
    Set-ObjectField -obj $lock -name 'pane_id' -value ''
    if ($ClearAssignedWorker) {
        Set-ObjectField -obj $lock -name 'assigned_worker' -value ''
    }
    if ($ClearDispatchMode) {
        Set-ObjectField -obj $lock -name 'dispatch_mode' -value ''
    }
}

function Resolve-RecoveryTargetState([string]$State, [string]$Phase) {
    $stateNorm = if ($State) { ([string]$State).Trim().ToLowerInvariant() } else { '' }
    $phaseNorm = if ($Phase) { ([string]$Phase).Trim().ToLowerInvariant() } else { '' }

    switch ($stateNorm) {
        'qa' { return 'waiting_qa' }
        'waiting_qa' { return 'waiting_qa' }
        'qa_passed' { return 'waiting_qa' }
        'in_progress' { return 'assigned' }
        'assigned' { return 'assigned' }
        'blocked' { return 'assigned' }
    }

    if ($phaseNorm -eq 'qa') {
        return 'waiting_qa'
    }
    return 'assigned'
}

function Get-TaskRuntimeResidue([string]$TaskId, $Lock) {
    if (-not $Lock) { return $null }

    $runId = if ($Lock.PSObject.Properties.Name -contains 'run_id' -and $Lock.run_id) { [string]$Lock.run_id } else { '' }
    $assignedWorker = if ($Lock.PSObject.Properties.Name -contains 'assigned_worker' -and $Lock.assigned_worker) { [string]$Lock.assigned_worker } else { '' }
    $paneId = if ($Lock.PSObject.Properties.Name -contains 'pane_id' -and $Lock.pane_id) { [string]$Lock.pane_id } else { '' }
    $dispatchModeRaw = if ($Lock.PSObject.Properties.Name -contains 'dispatch_mode' -and $Lock.dispatch_mode) { [string]$Lock.dispatch_mode } else { '' }
    $headlessRunDir = if ($Lock.PSObject.Properties.Name -contains 'headless_run_dir' -and $Lock.headless_run_dir) { [string]$Lock.headless_run_dir } else { '' }
    $headlessPid = 0
    if ($Lock.PSObject.Properties.Name -contains 'headless_pid' -and $Lock.headless_pid) {
        try { $headlessPid = [int]$Lock.headless_pid } catch { $headlessPid = 0 }
    }
    $dispatchMode = if ($dispatchModeRaw) { $dispatchModeRaw.Trim().ToLowerInvariant() } elseif ($headlessRunDir -or $headlessPid -gt 0) { 'headless' } else { '' }
    $headlessPidAlive = if ($headlessPid -gt 0) { Test-ProcessAliveById -ProcessId $headlessPid } else { $false }

    $fields = New-Object System.Collections.Generic.List[string]
    if ($runId) { $fields.Add('run_id=' + $runId) | Out-Null }
    if ($assignedWorker) { $fields.Add('assigned_worker=' + $assignedWorker) | Out-Null }
    if ($dispatchModeRaw) { $fields.Add('dispatch_mode=' + $dispatchModeRaw) | Out-Null }
    if ($headlessRunDir) { $fields.Add('headless_run_dir=' + $headlessRunDir) | Out-Null }
    if ($headlessPid -gt 0) { $fields.Add('headless_pid=' + [string]$headlessPid + '(' + $(if ($headlessPidAlive) { 'alive' } else { 'gone' }) + ')') | Out-Null }
    if ($paneId) { $fields.Add('pane_id=' + $paneId) | Out-Null }

    [pscustomobject]@{
        has_residue = ($fields.Count -gt 0)
        dispatch_mode = $dispatchMode
        run_id = $runId
        assigned_worker = $assignedWorker
        pane_id = $paneId
        headless_run_dir = $headlessRunDir
        headless_pid = $headlessPid
        headless_pid_alive = $headlessPidAlive
        summary = ($fields -join '; ')
    }
}

function Assert-DispatchRuntimeClean([string]$TaskId, [string]$TargetState, $Lock) {
    $residue = Get-TaskRuntimeResidue -TaskId $TaskId -Lock $Lock
    if (-not $residue -or -not $residue.has_residue) { return }

    Write-Host ('[FAIL] Task ' + $TaskId + ' state=' + $TargetState + ' still carries stale runtime metadata.') -ForegroundColor Red
    Write-Host ('       Residue: ' + $residue.summary) -ForegroundColor Yellow
    Write-Host ('       First: powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-task -TaskId ' + $TaskId) -ForegroundColor White
    if ($TargetState -eq 'waiting_qa') {
        Write-Host ('       Then:  powershell -File scripts/teamlead-control.ps1 -Action dispatch-qa -TaskId ' + $TaskId) -ForegroundColor DarkGray
    } else {
        Write-Host ('       Then:  powershell -File scripts/teamlead-control.ps1 -Action dispatch -TaskId ' + $TaskId) -ForegroundColor DarkGray
    }
    exit 1
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
    $lines = @($raw -split "(
|`n)")
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


function Get-BackgroundWatcherStaleSeconds {
    return (Get-EnvIntOrDefault -name 'CCB_BACKGROUND_WATCHER_STALE_SECONDS' -defaultValue 15)
}

function Get-ProcessStateAgeSeconds($State) {
    if (-not $State) { return $null }
    $lastLoopUtc = ConvertTo-UtcDateSafe $State.last_loop_at
    if (-not $lastLoopUtc) { return $null }
    try {
        return [int][Math]::Floor(((Get-Date).ToUniversalTime() - $lastLoopUtc).TotalSeconds)
    } catch {
        return $null
    }
}

function Test-ProcessStateFresh($State, [int]$MaxAgeSeconds = 0) {
    if (-not $State) { return $false }
    if ($MaxAgeSeconds -le 0) {
        $MaxAgeSeconds = Get-BackgroundWatcherStaleSeconds
    }
    $ageSeconds = Get-ProcessStateAgeSeconds $State
    if ($null -eq $ageSeconds) { return $false }
    return ($ageSeconds -le $MaxAgeSeconds)
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
        # 这里仅统计 stale pending，真正超时拒绝由 pane watcher / Team Lead 负责处理。
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

function Send-ApprovalDecisionToPane($paneId, $decision, $promptType, $approvalMode = "default") {
    $ptype = if ($promptType) { [string]$promptType } else { "command_approval" }
    $mode = if ($approvalMode) { [string]$approvalMode } else { "default" }
    if ($ptype -eq "edit_confirm") {
        if ($decision -eq 'approve') {
            wezterm cli send-text --pane-id $paneId --no-paste "`r" | Out-Null
            return ($LASTEXITCODE -eq 0)
        }
        wezterm cli send-text --pane-id $paneId --no-paste "`e" | Out-Null
        return ($LASTEXITCODE -eq 0)
    }

    if ($ptype -eq "menu_approval") {
        if ($decision -eq 'approve') {
            $key = if ($mode -eq 'session') { '2' } else { '1' }
        } else {
            $key = '3'
        }
        wezterm cli send-text --pane-id $paneId --no-paste $key | Out-Null
        if ($LASTEXITCODE -ne 0) {
            return $false
        }
        Start-Sleep -Milliseconds 200
        wezterm cli send-text --pane-id $paneId --no-paste "`r" | Out-Null
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

function Get-WorkerPaneTail([string]$paneId, [int]$maxLines = 120) {
    if (-not $paneId) { return "" }
    try {
        $text = wezterm cli get-text --pane-id $paneId 2>$null
        if (-not $text) { return "" }
        $parts = @($text -split "`n")
        if ($parts.Count -gt $maxLines) {
            $parts = $parts[-$maxLines..-1]
        }
        return (($parts -join "`n") -replace "`r", "")
    } catch {
        return ""
    }
}

function Resolve-LocalPromptType([string]$paneId, [string]$explicitPromptType = "auto") {
    if ($explicitPromptType -and $explicitPromptType -ne "auto") { return $explicitPromptType }
    $tail = Get-WorkerPaneTail -paneId $paneId
    if (-not $tail) { return "command_approval" }
    if ($tail -match 'Approve Once|Approve this session|Question 1/1|Run the tool and continue|Select an option|enter to submit answer') {
        return "menu_approval"
    }
    if ($tail -match 'Press enter to confirm or esc to cancel|press enter to confirm and save|enter to confirm|esc to cancel|tab to add notes') {
        return "edit_confirm"
    }
    return "command_approval"
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

function Get-WeztermPaneInfo([string]$PaneId, $Panes = $null) {
    $normalized = Normalize-PaneId $PaneId
    if (-not $normalized) { return $null }
    if (-not $Panes) {
        $Panes = Get-WeztermPanes
    }
    if (-not $Panes) { return $null }
    foreach ($pane in @($Panes)) {
        $candidate = Normalize-PaneId ([string]$pane.pane_id)
        if ($candidate -eq $normalized) {
            return $pane
        }
    }
    return $null
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

function Resolve-DispatchMode($cfg, [string]$phase) {
    if (-not $cfg) { return 'pane' }
    $phaseKey = if ($phase) { ($phase.ToLowerInvariant() + '_dispatch_mode') } else { '' }
    $raw = $null
    if ($phaseKey -and $cfg.PSObject.Properties.Name -contains $phaseKey) {
        $raw = $cfg.$phaseKey
    }
    if (-not $raw -and $cfg.PSObject.Properties.Name -contains 'dispatch_mode') {
        $raw = $cfg.dispatch_mode
    }
    $mode = if ($raw) { [string]$raw } else { 'pane' }
    $mode = $mode.Trim().ToLowerInvariant()
    if ($mode -notin @('pane', 'headless')) {
        throw ('Unsupported dispatch mode: ' + $mode + ' phase=' + $phase)
    }
    return $mode
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

function Read-PaneApprovalWatcherStore {
    if (-not (Test-Path $paneApprovalWatcherStatePath)) {
        return @{ updated_at = (Get-Date -Format "o"); watchers = @{} }
    }
    try {
        $raw = Get-Content $paneApprovalWatcherStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $raw.watchers) {
            $raw | Add-Member -NotePropertyName watchers -NotePropertyValue @{} -Force
        } elseif (-not ($raw.watchers -is [System.Collections.IDictionary])) {
            $raw.watchers = Convert-ToObjectMap $raw.watchers
        }
        return $raw
    } catch {
        return @{ updated_at = (Get-Date -Format "o"); watchers = @{} }
    }
}

function Convert-ToWatcherEntryMap($watchersObj) {
    $map = @{}
    foreach ($entry in (Convert-ToObjectMap $watchersObj).GetEnumerator()) {
        $name = [string]$entry.Key
        if ($name -and $name -match '\|') {
            $map[$name] = $entry.Value
        }
    }
    return $map
}

function Write-PaneApprovalWatcherStore($data) {
    if (-not $data) {
        $data = @{ updated_at = (Get-Date -Format "o"); watchers = @{} }
    }
    if (-not $data.watchers) { $data.watchers = @{} }
    if (-not ($data.watchers -is [System.Collections.IDictionary])) {
        $data.watchers = Convert-ToObjectMap $data.watchers
    }
    $data.updated_at = Get-Date -Format "o"
    Write-Utf8NoBomFile -path $paneApprovalWatcherStatePath -content ($data | ConvertTo-Json -Depth 10)
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

function Stop-PaneApprovalWatcher([string]$TaskId, [string]$WorkerName, [switch]$Quiet) {
    if (-not $TaskId -or -not $WorkerName) { return $false }
    $store = Read-PaneApprovalWatcherStore
    $watchers = Convert-ToWatcherEntryMap $store.watchers
    $key = ($TaskId + '|' + $WorkerName).ToUpper()
    if (-not $watchers.ContainsKey($key)) { return $false }
    $entry = $watchers[$key]
    $watcherPid = 0
    $pidStr = if ($entry.pid) { [string]$entry.pid } else { '' }
    if ([int]::TryParse($pidStr, [ref]$watcherPid) -and $watcherPid -gt 0) {
        Stop-Process -Id $watcherPid -Force -ErrorAction SilentlyContinue
    }
    $watchers.Remove($key) | Out-Null
    $store.watchers = $watchers
    Write-PaneApprovalWatcherStore $store
    Clear-LocalApprovalState -WorkerName $WorkerName
    if (-not $Quiet) {
        Write-Host ('[OK] pane-approval-watcher stopped: ' + $TaskId + ' / ' + $WorkerName) -ForegroundColor Green
    }
    return $true
}

function Cleanup-StalePaneApprovalWatchers([string]$KeepTaskId = '', [string]$KeepWorkerName = '', [switch]$Verbose) {
    $store = Read-PaneApprovalWatcherStore
    $watchers = Convert-ToWatcherEntryMap $store.watchers
    if ($watchers.Keys.Count -eq 0) {
        return @{ removed = 0; killed = 0; kept = 0 }
    }

    $locks = Read-TaskLocks
    $livePanes = Get-LivePaneIdSet
    $keepKey = ''
    if ($KeepTaskId -and $KeepWorkerName) {
        $keepKey = ($KeepTaskId + '|' + $KeepWorkerName).ToUpper()
    }
    $keepWorkerUpper = if ($KeepWorkerName) { $KeepWorkerName.ToUpperInvariant() } else { '' }

    $nextWatchers = @{}
    $removed = 0
    $killed = 0
    $kept = 0

    foreach ($name in $watchers.Keys) {
        $entry = $watchers[$name]
        $watcherPid = 0
        $pidStr = if ($entry.pid) { [string]$entry.pid } else { '' }
        $proc = $null
        $alive = $false
        if ([int]::TryParse($pidStr, [ref]$watcherPid) -and $watcherPid -gt 0) {
            $proc = Get-Process -Id $watcherPid -ErrorAction SilentlyContinue
            $alive = ($null -ne $proc)
        }

        $paneId = if ($entry.worker_pane_id) { [string]$entry.worker_pane_id } else { '' }
        $paneAlive = $false
        if ($paneId -and $livePanes) {
            try { $paneAlive = [bool]$livePanes.Contains($paneId) } catch { $paneAlive = $false }
        }

        $entryWorker = if ($entry.worker) { [string]$entry.worker } else { '' }
        $entryTask = if ($entry.task) { [string]$entry.task } else { '' }
        $entryRunId = if ($entry.run_id) { [string]$entry.run_id } else { '' }
        $skipTaskLockGuard = $false
        try {
            if ($entry.skip_task_lock_guard -ne $null) { $skipTaskLockGuard = [bool]$entry.skip_task_lock_guard }
        } catch {}

        $sameWorkerDifferentTask = ($keepWorkerUpper -and $entryWorker.ToUpperInvariant() -eq $keepWorkerUpper -and $name -ne $keepKey)
        $taskActive = $true
        if (-not $skipTaskLockGuard) {
            $taskActive = $false
            if ($locks.locks.PSObject.Properties.Name -contains $entryTask) {
                $lock = $locks.locks.$entryTask
                $lockState = if ($lock.state) { [string]$lock.state } else { '' }
                $lockWorker = if ($lock.assigned_worker) { [string]$lock.assigned_worker } else { '' }
                $lockRunId = if ($lock.run_id) { [string]$lock.run_id } else { '' }
                if ($lockState -in @('in_progress', 'qa', 'archiving') -and $lockWorker -eq $entryWorker) {
                    if (-not $entryRunId -or -not $lockRunId -or $lockRunId -eq $entryRunId) {
                        $taskActive = $true
                    }
                }
            }
        }

        $drop = (-not $alive) -or (-not $paneAlive) -or $sameWorkerDifferentTask -or (-not $taskActive)
        if ($drop) {
            if ($alive -and $watcherPid -gt 0) {
                Stop-Process -Id $watcherPid -Force -ErrorAction SilentlyContinue
                $killed++
            }
            $removed++
            if ($entryWorker) { Clear-LocalApprovalState -WorkerName $entryWorker }
            if ($Verbose) {
                Write-Host ('[INFO] Removed stale pane-approval-watcher: ' + $name + ' pid=' + $pidStr + ' pane=' + $paneId) -ForegroundColor DarkGray
            }
            continue
        }

        $nextWatchers[$name] = $entry
        $kept++
    }

    if ($removed -gt 0) {
        $store.watchers = $nextWatchers
        Write-PaneApprovalWatcherStore $store
    }

    return @{ removed = $removed; killed = $killed; kept = $kept }
}

function Ensure-PaneApprovalWatcher([string]$TaskId, [string]$WorkerName, [string]$WorkerPaneId, [string]$TeamLeadPaneId, [string]$RunId = '', [switch]$SkipTaskLockGuard) {
    $watcherScript = Join-Path $scriptDir 'pane-approval-watcher.ps1'
    if (-not (Test-Path $watcherScript)) {
        Write-Host '[WARN] pane-approval-watcher.ps1 not found, skip auto start' -ForegroundColor Yellow
        return
    }

    $key = ($TaskId + '|' + $WorkerName).ToUpper()
    $store = Read-PaneApprovalWatcherStore
    $watchers = Convert-ToWatcherEntryMap $store.watchers

    $needStart = $true
    if ($watchers.ContainsKey($key)) {
        $existing = $watchers[$key]
        $existingPid = 0
        $pidStr = if ($existing.pid) { [string]$existing.pid } else { '' }
        if ([int]::TryParse($pidStr, [ref]$existingPid) -and $existingPid -gt 0) {
            $proc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
            if ($proc) {
                $samePane = ([string]$existing.worker_pane_id -eq [string]$WorkerPaneId)
                $sameTl = ([string]$existing.team_lead_pane_id -eq [string]$TeamLeadPaneId)
                $sameRun = ([string]$existing.run_id -eq [string]$RunId)
                if ($samePane -and $sameTl -and $sameRun) {
                    $needStart = $false
                    Write-Host ('[OK] pane-approval-watcher running (PID ' + $existingPid + ', task=' + $TaskId + ', worker=' + $WorkerName + ')') -ForegroundColor Green
                } else {
                    Stop-Process -Id $existingPid -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    if (-not $needStart) { return }

    $cmdParts = New-Object System.Collections.Generic.List[string]
    foreach ($envName in @('WEZTERM_PANE','WEZTERM_PANE_ID','WEZTERM_UNIX_SOCKET','WEZTERM_EXECUTABLE','WEZTERM_CONFIG_FILE')) {
        $envValue = [System.Environment]::GetEnvironmentVariable($envName)
        if (-not [string]::IsNullOrWhiteSpace($envValue)) {
            $escapedEnvValue = $envValue.Replace("'", "''")
            $cmdParts.Add("`$env:" + $envName + "='" + $escapedEnvValue + "'") | Out-Null
        }
    }
    $escapedWatcherScript = $watcherScript.Replace("'", "''")
    $escapedWorkerPaneId = ([string]$WorkerPaneId).Replace("'", "''")
    $escapedWorkerName = ([string]$WorkerName).Replace("'", "''")
    $escapedTaskId = ([string]$TaskId).Replace("'", "''")
    $escapedTlPaneId = ([string]$TeamLeadPaneId).Replace("'", "''")
    $watcherCommand = "& '" + $escapedWatcherScript + "' -WorkerPaneId '" + $escapedWorkerPaneId + "' -WorkerName '" + $escapedWorkerName + "' -TaskId '" + $escapedTaskId + "' -TeamLeadPaneId '" + $escapedTlPaneId + "'"
    if ($RunId) {
        $watcherCommand += " -RunId '" + ([string]$RunId).Replace("'", "''") + "'"
    }
    if ($SkipTaskLockGuard) {
        $watcherCommand += ' -SkipTaskLockGuard'
    }
    $cmdParts.Add($watcherCommand) | Out-Null
    $proc = Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command',($cmdParts -join '; ')) -WindowStyle Hidden -PassThru
    $watchers[$key] = @{
        pid = $proc.Id
        task = $TaskId
        worker = $WorkerName
        worker_pane_id = $WorkerPaneId
        team_lead_pane_id = $TeamLeadPaneId
        run_id = if ($RunId) { $RunId } else { '' }
        skip_task_lock_guard = [bool]$SkipTaskLockGuard
        started_at = Get-Date -Format 'o'
        status = 'active'
    }
    $store.watchers = $watchers
    Write-PaneApprovalWatcherStore $store
    Write-Host ('[OK] pane-approval-watcher started (PID ' + $proc.Id + ', task=' + $TaskId + ', worker=' + $WorkerName + ')') -ForegroundColor Green
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
    $monitorScript = Join-Path $scriptDir "route-monitor.ps1"
    $monitorRunning = $false
    $needsRestart = $false
    $savedPid = ""
    $savedPaneId = Get-RouteMonitorPaneId
    $proc = $null
    $monitorState = Read-RouteMonitorState
    $panes = $null

    if (Test-Path $monitorPidFile) {
        $savedPid = (Get-Content $monitorPidFile -Raw).Trim()
    } elseif ($monitorState -and $monitorState.pid) {
        $savedPid = [string]$monitorState.pid
    }
    if ($savedPid) {
        try {
            $proc = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
            $monitorRunning = ($null -ne $proc)
        } catch {}
    }
    if (-not $monitorRunning) {
        Remove-Item $monitorPidFile -Force -ErrorAction SilentlyContinue
    } elseif (Test-Path $monitorScript) {
        try {
            $scriptWriteTime = (Get-Item $monitorScript).LastWriteTime
            if ($scriptWriteTime -gt $proc.StartTime) {
                $needsRestart = $true
                Write-Host ('[WARN] route-monitor binary drift detected: script=' + $scriptWriteTime.ToString("yyyy-MM-dd HH:mm:ss") + ' > process=' + $proc.StartTime.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor Yellow
            }
        } catch {}
    }

    if ($monitorState) {
        if ($monitorState.note -and ([string]$monitorState.note).StartsWith('wezterm_cli_unavailable')) {
            $needsRestart = $true
            Write-Host '[WARN] route-monitor lost WezTerm GUI socket, will restart inside WezTerm pane.' -ForegroundColor Yellow
        }
        if ($tlPaneId -and $monitorState.teamlead_pane_id -and ([string]$monitorState.teamlead_pane_id -ne [string]$tlPaneId)) {
            $needsRestart = $true
            Write-Host ('[WARN] route-monitor pane target drift detected: state=' + [string]$monitorState.teamlead_pane_id + ' expected=' + [string]$tlPaneId) -ForegroundColor Yellow
        }
        if ($monitorRunning -and (-not (Test-ProcessStateFresh $monitorState))) {
            $ageSeconds = Get-ProcessStateAgeSeconds $monitorState
            $needsRestart = $true
            Write-Host ('[WARN] route-monitor heartbeat stale: last_loop=' + [string]$monitorState.last_loop_at + ' age=' + [string]$ageSeconds + 's') -ForegroundColor Yellow
        }
    } elseif ($monitorRunning) {
        $needsRestart = $true
        Write-Host '[WARN] route-monitor process exists but state file is missing/unreadable; will restart.' -ForegroundColor Yellow
    }

    if ($monitorRunning -and $savedPaneId) {
        if (-not $panes) { $panes = Get-WeztermPanes }
        $monitorPaneInfo = Get-WeztermPaneInfo $savedPaneId $panes
        if (-not $monitorPaneInfo) {
            $needsRestart = $true
            Write-Host ('[WARN] route-monitor pane ' + $savedPaneId + ' missing; will restart.') -ForegroundColor Yellow
        }
    }

    if ($monitorRunning -and $needsRestart) {
        try {
            Stop-Process -Id $savedPid -Force -ErrorAction Stop
            Start-Sleep -Milliseconds 300
        } catch {
            Write-Host ('[WARN] Failed to stop stale route-monitor PID ' + $savedPid + ': ' + $_.Exception.Message) -ForegroundColor Yellow
        }
        $monitorRunning = $false
        Remove-Item $monitorPidFile -Force -ErrorAction SilentlyContinue
    }
    if ($savedPaneId -and (-not $monitorRunning -or $needsRestart)) {
        try {
            wezterm cli kill-pane --pane-id $savedPaneId 2>$null | Out-Null
            Write-Host ('[INFO] Closed stale route-monitor pane ' + $savedPaneId) -ForegroundColor DarkGray
        } catch {
            Write-Host ('[WARN] Failed to close stale route-monitor pane ' + $savedPaneId + ': ' + $_.Exception.Message) -ForegroundColor Yellow
        }
        Remove-Item $monitorPaneFile -Force -ErrorAction SilentlyContinue
    }

    if (-not $monitorRunning) {
        Write-Host '[INFO] Starting route-monitor...' -ForegroundColor Yellow
        if (Test-Path $monitorScript) {
            $panes = Get-WeztermPanes
            if (-not $panes -or @($panes).Count -eq 0) {
                Write-Host '[FAIL] Cannot start route-monitor: wezterm cli is unavailable in current session.' -ForegroundColor Red
                Write-Host '       请在正在运行的 WezTerm Team Lead 窗口中执行 bootstrap / dispatch。' -ForegroundColor Yellow
                exit 1
            }

            $spawnArgs = @(
                'cli', 'spawn',
                '--cwd', $rootDir,
                'powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', $monitorScript,
                '-Continuous',
                '-TeamLeadPaneId', $tlPaneId
            )
            $spawnOutput = & wezterm @spawnArgs 2>&1
            $newPaneId = Normalize-PaneId ([string]$spawnOutput)
            if ($LASTEXITCODE -ne 0 -or -not $newPaneId) {
                Write-Host ('[FAIL] route-monitor spawn failed: ' + [string]$spawnOutput) -ForegroundColor Red
                exit 1
            }

            Set-Content $monitorPaneFile $newPaneId -Force -Encoding UTF8
            $launchDeadline = (Get-Date).AddSeconds(8)
            $launchedPid = $null
            do {
                Start-Sleep -Milliseconds 300
                $latestState = Read-RouteMonitorState
                if ($latestState -and $latestState.pid) {
                    $statePane = $null
                    if ($latestState.monitor_pane_id) {
                        $statePane = Normalize-PaneId ([string]$latestState.monitor_pane_id)
                    }
                    if ((-not $statePane) -or $statePane -eq $newPaneId) {
                        $launchedPid = [string]$latestState.pid
                    }
                }
            } while ((-not $launchedPid) -and (Get-Date) -lt $launchDeadline)

            if ($launchedPid) {
                Set-Content $monitorPidFile $launchedPid -Force -Encoding UTF8
                Write-Host ('[OK] route-monitor started (pane ' + $newPaneId + ', PID ' + $launchedPid + ')') -ForegroundColor Green
            } else {
                Remove-Item $monitorPidFile -Force -ErrorAction SilentlyContinue
                Write-Host ('[WARN] route-monitor pane started (pane ' + $newPaneId + '), but PID sync timed out. Check status.') -ForegroundColor Yellow
            }
        } else {
            Write-Host '[WARN] route-monitor.ps1 not found, skipping' -ForegroundColor Yellow
        }
    } else {
        if ($savedPaneId) {
            Write-Host ('[OK] route-monitor running (PID ' + $savedPid + ', pane ' + $savedPaneId + ')') -ForegroundColor Green
        } else {
            Write-Host ('[OK] route-monitor running (PID ' + $savedPid + ')') -ForegroundColor Green
        }
    }
}

function Ensure-RouteNotifier($tlPaneId) {
    $notifierScript = Join-Path $scriptDir "route-notifier.ps1"
    $notifierRunning = $false
    $needsRestart = $false
    $savedPid = ""
    $savedPaneId = Get-RouteNotifierPaneId
    $proc = $null
    $notifierState = Read-RouteNotifierState
    $panes = $null

    if (Test-Path $notifierPidFile) {
        $savedPid = (Get-Content $notifierPidFile -Raw).Trim()
    } elseif ($notifierState -and $notifierState.pid) {
        $savedPid = [string]$notifierState.pid
    }
    if ($savedPid) {
        try {
            $proc = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
            $notifierRunning = ($null -ne $proc)
        } catch {}
    }
    if (-not $notifierRunning) {
        Remove-Item $notifierPidFile -Force -ErrorAction SilentlyContinue
    } elseif (Test-Path $notifierScript) {
        try {
            $scriptWriteTime = (Get-Item $notifierScript).LastWriteTime
            if ($scriptWriteTime -gt $proc.StartTime) {
                $needsRestart = $true
                Write-Host ('[WARN] route-notifier binary drift detected: script=' + $scriptWriteTime.ToString("yyyy-MM-dd HH:mm:ss") + ' > process=' + $proc.StartTime.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor Yellow
            }
        } catch {}
    }

    if ($notifierState) {
        if ($notifierState.note -and ([string]$notifierState.note).StartsWith('wezterm_cli_unavailable')) {
            $needsRestart = $true
            Write-Host '[WARN] route-notifier lost WezTerm GUI socket, will restart inside WezTerm pane.' -ForegroundColor Yellow
        }
        if ($tlPaneId -and $notifierState.teamlead_pane_id -and ([string]$notifierState.teamlead_pane_id -ne [string]$tlPaneId)) {
            $needsRestart = $true
            Write-Host ('[WARN] route-notifier pane target drift detected: state=' + [string]$notifierState.teamlead_pane_id + ' expected=' + [string]$tlPaneId) -ForegroundColor Yellow
        }
        if ($notifierRunning -and (-not (Test-ProcessStateFresh $notifierState))) {
            $ageSeconds = Get-ProcessStateAgeSeconds $notifierState
            $needsRestart = $true
            Write-Host ('[WARN] route-notifier heartbeat stale: last_loop=' + [string]$notifierState.last_loop_at + ' age=' + [string]$ageSeconds + 's') -ForegroundColor Yellow
        }
    } elseif ($notifierRunning) {
        $needsRestart = $true
        Write-Host '[WARN] route-notifier process exists but state file is missing/unreadable; will restart.' -ForegroundColor Yellow
    }

    if ($notifierRunning -and $savedPaneId) {
        if (-not $panes) { $panes = Get-WeztermPanes }
        $notifierPaneInfo = Get-WeztermPaneInfo $savedPaneId $panes
        if (-not $notifierPaneInfo) {
            $needsRestart = $true
            Write-Host ('[WARN] route-notifier pane ' + $savedPaneId + ' missing; will restart.') -ForegroundColor Yellow
        }
    }

    if ($notifierRunning -and $needsRestart) {
        try {
            Stop-Process -Id $savedPid -Force -ErrorAction Stop
            Start-Sleep -Milliseconds 300
        } catch {
            Write-Host ('[WARN] Failed to stop stale route-notifier PID ' + $savedPid + ': ' + $_.Exception.Message) -ForegroundColor Yellow
        }
        $notifierRunning = $false
        Remove-Item $notifierPidFile -Force -ErrorAction SilentlyContinue
    }
    if ($savedPaneId -and (-not $notifierRunning -or $needsRestart)) {
        try {
            wezterm cli kill-pane --pane-id $savedPaneId 2>$null | Out-Null
            Write-Host ('[INFO] Closed stale route-notifier pane ' + $savedPaneId) -ForegroundColor DarkGray
        } catch {
            Write-Host ('[WARN] Failed to close stale route-notifier pane ' + $savedPaneId + ': ' + $_.Exception.Message) -ForegroundColor Yellow
        }
        Remove-Item $notifierPaneFile -Force -ErrorAction SilentlyContinue
    }

    if (-not $notifierRunning) {
        Write-Host '[INFO] Starting route-notifier...' -ForegroundColor Yellow
        if (Test-Path $notifierScript) {
            $panes = Get-WeztermPanes
            if (-not $panes -or @($panes).Count -eq 0) {
                Write-Host '[FAIL] Cannot start route-notifier: wezterm cli is unavailable in current session.' -ForegroundColor Red
                Write-Host '       请在正在运行的 WezTerm Team Lead 窗口中执行 bootstrap / dispatch。' -ForegroundColor Yellow
                exit 1
            }

            $spawnArgs = @(
                'cli', 'spawn',
                '--cwd', $rootDir,
                'powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', $notifierScript,
                '-Continuous',
                '-TeamLeadPaneId', $tlPaneId
            )
            $spawnOutput = & wezterm @spawnArgs 2>&1
            $newPaneId = Normalize-PaneId ([string]$spawnOutput)
            if ($LASTEXITCODE -ne 0 -or -not $newPaneId) {
                Write-Host ('[FAIL] route-notifier spawn failed: ' + [string]$spawnOutput) -ForegroundColor Red
                exit 1
            }

            Set-Content $notifierPaneFile $newPaneId -Force -Encoding UTF8
            $launchDeadline = (Get-Date).AddSeconds(8)
            $launchedPid = $null
            do {
                Start-Sleep -Milliseconds 300
                $latestState = Read-RouteNotifierState
                if ($latestState -and $latestState.pid) {
                    $statePane = $null
                    if ($latestState.notifier_pane_id) {
                        $statePane = Normalize-PaneId ([string]$latestState.notifier_pane_id)
                    }
                    if ((-not $statePane) -or $statePane -eq $newPaneId) {
                        $launchedPid = [string]$latestState.pid
                    }
                }
            } while ((-not $launchedPid) -and (Get-Date) -lt $launchDeadline)

            if ($launchedPid) {
                Set-Content $notifierPidFile $launchedPid -Force -Encoding UTF8
                Write-Host ('[OK] route-notifier started (pane ' + $newPaneId + ', PID ' + $launchedPid + ')') -ForegroundColor Green
            } else {
                Remove-Item $notifierPidFile -Force -ErrorAction SilentlyContinue
                Write-Host ('[WARN] route-notifier pane started (pane ' + $newPaneId + '), but PID sync timed out. Check status.') -ForegroundColor Yellow
            }
        } else {
            Write-Host '[WARN] route-notifier.ps1 not found, skipping' -ForegroundColor Yellow
        }
    } else {
        if ($savedPaneId) {
            Write-Host ('[OK] route-notifier running (PID ' + $savedPid + ', pane ' + $savedPaneId + ')') -ForegroundColor Green
        } else {
            Write-Host ('[OK] route-notifier running (PID ' + $savedPid + ')') -ForegroundColor Green
        }
    }
}

function Ensure-RichMonitor($tlPaneId) {
    if (-not (Test-RichMonitorEnabled)) {
        Write-Host '[INFO] 已通过 CCB_DISABLE_RICH_MONITOR=1 禁用 Rich 看板' -ForegroundColor DarkGray
        return
    }

    $richScript = Join-Path $scriptDir 'start-rich-monitor.ps1'
    if (-not (Test-Path $richScript)) {
        Write-Host '[WARN] 未找到 start-rich-monitor.ps1，跳过 Rich 看板启动' -ForegroundColor Yellow
        return
    }

    $richRunning = $false
    $needsRestart = $false
    $savedPid = ''
    $savedPaneId = Get-RichMonitorPaneId
    $proc = $null
    $richState = Read-RichMonitorState
    $panes = Get-WeztermPanes
    $tlPaneInfo = Get-WeztermPaneInfo $tlPaneId $panes
    $richPaneInfo = $null
    $targetPercent = 38

    if ($env:CCB_RICH_MONITOR_PERCENT) {
        try {
            $parsedPercent = [int]$env:CCB_RICH_MONITOR_PERCENT
            if ($parsedPercent -ge 20 -and $parsedPercent -le 70) {
                $targetPercent = $parsedPercent
            }
        } catch {}
    }

    if (Test-Path $richMonitorPidFile) {
        $savedPid = (Get-Content $richMonitorPidFile -Raw).Trim()
    } elseif ($richState -and $richState.pid) {
        $savedPid = [string]$richState.pid
    }
    if ($savedPid) {
        try {
            $proc = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
            $richRunning = ($null -ne $proc)
        } catch {}
    }
    if (-not $richRunning) {
        Remove-Item $richMonitorPidFile -Force -ErrorAction SilentlyContinue
    } elseif (Test-Path $richScript) {
        try {
            $scriptWriteTime = (Get-Item $richScript).LastWriteTime
            if ($scriptWriteTime -gt $proc.StartTime) {
                $needsRestart = $true
                Write-Host ('[WARN] Rich 看板脚本时间戳晚于现有进程，准备重启：script=' + $scriptWriteTime.ToString('yyyy-MM-dd HH:mm:ss') + ' > process=' + $proc.StartTime.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Yellow
            }
        } catch {}
    }

    if ($richState) {
        if ($richState.note -and ([string]$richState.note).Trim().Length -gt 0) {
            $noteText = [string]$richState.note
            if ($noteText -match 'error|traceback|fail') {
                $needsRestart = $true
                Write-Host ('[WARN] Rich 看板状态文件报告异常备注：' + $noteText) -ForegroundColor Yellow
            }
        }
        if ($richState.status -and ([string]$richState.status -eq 'error')) {
            $needsRestart = $true
            Write-Host '[WARN] Rich 看板状态为 error，准备重启。' -ForegroundColor Yellow
        }
        if ($richRunning -and (-not (Test-ProcessStateFresh $richState 20))) {
            $ageSeconds = Get-ProcessStateAgeSeconds $richState
            $needsRestart = $true
            Write-Host ('[WARN] Rich 看板心跳过期：last_loop=' + [string]$richState.last_loop_at + ' age=' + [string]$ageSeconds + 's') -ForegroundColor Yellow
        }
    } elseif ($richRunning) {
        $needsRestart = $true
        Write-Host '[WARN] Rich 看板进程存在但状态文件缺失/不可读；准备重启。' -ForegroundColor Yellow
    }

    if ($richRunning -and $savedPaneId) {
        $richPaneInfo = Get-WeztermPaneInfo $savedPaneId $panes
        if (-not $richPaneInfo) {
            $needsRestart = $true
            Write-Host '[WARN] Rich 看板进程仍存活，但窗格已丢失；准备重启。' -ForegroundColor Yellow
        } elseif ($tlPaneInfo) {
            $sameWindow = ([string]$richPaneInfo.window_id -eq [string]$tlPaneInfo.window_id)
            $sameTab = ([string]$richPaneInfo.tab_id -eq [string]$tlPaneInfo.tab_id)
            if ((-not $sameWindow) -or (-not $sameTab)) {
                $needsRestart = $true
                Write-Host '[WARN] Rich 看板未附着在 Team Lead 当前标签页；将重新挂到右侧分栏。' -ForegroundColor Yellow
            }
        }
    }

    if ($richRunning -and $needsRestart) {
        try {
            Stop-Process -Id $savedPid -Force -ErrorAction Stop
            Start-Sleep -Milliseconds 300
        } catch {
            Write-Host ('[WARN] 停止过期 Rich 看板进程失败，PID=' + $savedPid + '：' + $_.Exception.Message) -ForegroundColor Yellow
        }
        $richRunning = $false
        Remove-Item $richMonitorPidFile -Force -ErrorAction SilentlyContinue
    }
    if ($savedPaneId -and (-not $richRunning -or $needsRestart)) {
        try {
            wezterm cli kill-pane --pane-id $savedPaneId 2>$null | Out-Null
            Write-Host ('[INFO] 已关闭过期 Rich 看板窗格 ' + $savedPaneId) -ForegroundColor DarkGray
        } catch {
            Write-Host ('[WARN] 关闭过期 Rich 看板窗格失败，pane=' + $savedPaneId + '：' + $_.Exception.Message) -ForegroundColor Yellow
        }
        Remove-Item $richMonitorPaneFile -Force -ErrorAction SilentlyContinue
    }

    if (-not $richRunning) {
        Write-Host '[INFO] 正在启动 Rich 看板...' -ForegroundColor Yellow
        if (-not $panes -or @($panes).Count -eq 0) {
            Write-Host '[WARN] 无法启动 Rich 看板：当前会话不可用 wezterm cli。' -ForegroundColor Yellow
            Write-Host '       Rich 看板属于只读观察层；即使未启动，派遣链路也会继续。' -ForegroundColor DarkGray
            return
        }

        $launchMode = 'standalone'
        if ($tlPaneInfo) {
            $spawnArgs = @(
                'cli', 'split-pane',
                '--pane-id', $tlPaneId,
                '--horizontal',
                '--percent', [string]$targetPercent,
                '--cwd', $rootDir,
                'powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', $richScript,
                '-RunChild',
                '-LayoutMode', 'merged-right',
                '-PairedTeamLeadPaneId', $tlPaneId,
                '-SplitPercent', [string]$targetPercent
            )
            $launchMode = 'merged-right'
        } else {
            $spawnArgs = @(
                'cli', 'spawn',
                '--cwd', $rootDir,
                'powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', $richScript,
                '-RunChild',
                '-LayoutMode', 'standalone',
                '-SplitPercent', [string]$targetPercent
            )
        }

        $spawnOutput = & wezterm @spawnArgs 2>&1
        $newPaneId = Normalize-PaneId ([string]$spawnOutput)
        if ($LASTEXITCODE -ne 0 -or -not $newPaneId) {
            Write-Host ('[WARN] Rich 看板拉起失败：' + [string]$spawnOutput) -ForegroundColor Yellow
            return
        }

        Set-Content $richMonitorPaneFile $newPaneId -Force -Encoding UTF8
        $launchDeadline = (Get-Date).AddSeconds(8)
        $launchedPid = $null
        do {
            Start-Sleep -Milliseconds 300
            $latestState = Read-RichMonitorState
            if ($latestState -and $latestState.pid) {
                $statePane = $null
                if ($latestState.monitor_pane_id) {
                    $statePane = Normalize-PaneId ([string]$latestState.monitor_pane_id)
                }
                if ((-not $statePane) -or $statePane -eq $newPaneId) {
                    $launchedPid = [string]$latestState.pid
                }
            }
        } while ((-not $launchedPid) -and (Get-Date) -lt $launchDeadline)

        if ($launchedPid) {
            Set-Content $richMonitorPidFile $launchedPid -Force -Encoding UTF8
            if ($launchMode -eq 'merged-right') {
                Write-Host ('[OK] Rich 看板已启动（同窗右侧 pane=' + $newPaneId + '，PID=' + $launchedPid + '）') -ForegroundColor Green
            } else {
                Write-Host ('[OK] Rich 看板已启动（pane=' + $newPaneId + '，PID=' + $launchedPid + '）') -ForegroundColor Green
            }
        } else {
            Remove-Item $richMonitorPidFile -Force -ErrorAction SilentlyContinue
            if ($launchMode -eq 'merged-right') {
                Write-Host ('[WARN] Rich 看板右侧窗格已启动（pane=' + $newPaneId + '），但 PID 同步超时，请执行 status 检查。') -ForegroundColor Yellow
            } else {
                Write-Host ('[WARN] Rich 看板窗格已启动（pane=' + $newPaneId + '），但 PID 同步超时，请执行 status 检查。') -ForegroundColor Yellow
            }
        }
    } else {
        if ($savedPaneId) {
            if ($tlPaneInfo -and $richPaneInfo -and ([string]$richPaneInfo.window_id -eq [string]$tlPaneInfo.window_id) -and ([string]$richPaneInfo.tab_id -eq [string]$tlPaneInfo.tab_id)) {
                Write-Host ('[OK] Rich 看板运行中（同窗右侧 pane=' + $savedPaneId + '，PID=' + $savedPid + '）') -ForegroundColor Green
            } else {
                Write-Host ('[OK] Rich 看板运行中（PID=' + $savedPid + '，pane=' + $savedPaneId + '）') -ForegroundColor Green
            }
        } else {
            Write-Host ('[OK] Rich 看板运行中（PID=' + $savedPid + '）') -ForegroundColor Green
        }
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
    Assert-TeamLeadPaneId $tlPaneId 'bootstrap'
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
    Ensure-RouteNotifier $tlPaneId
    Ensure-RichMonitor $tlPaneId

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

    Write-Host ""
    Write-Host '--- Route Notifications ---' -ForegroundColor Cyan
    Write-Host '  route-monitor 只负责收口 MCP route、写锁与写事件；route-notifier 独立负责 WezTerm 唤醒 Team Lead。' -ForegroundColor Yellow
    Write-Host '  rich-monitor 为独立只读观察层，默认随 bootstrap / dispatch 自动拉起。' -ForegroundColor Yellow
    Write-Host '  默认开启；如需关闭可设置：CCB_ROUTE_MONITOR_NOTIFY=0 或 CCB_DISABLE_RICH_MONITOR=1' -ForegroundColor DarkGray
    Write-Host '  仅对关键 route 变化提醒；普通 in_progress 心跳不会持续刷屏。' -ForegroundColor DarkGray

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
    Write-Host '                 restart-task example: ... -Action recover -RecoverAction restart-task -TaskId BACKEND-010' -ForegroundColor DarkGray
    Write-Host '  archive     -- powershell -File scripts/teamlead-control.ps1 -Action archive -TaskId <ID> [-NoPush] [-CommitMessage "..."]' -ForegroundColor White
    Write-Host '  show-approval  -- powershell -File scripts/teamlead-control.ps1 -Action show-approval -RequestId <ID>' -ForegroundColor White
    Write-Host '  approve-request -- powershell -File scripts/teamlead-control.ps1 -Action approve-request -RequestId <ID>' -ForegroundColor White
    Write-Host '  deny-request    -- powershell -File scripts/teamlead-control.ps1 -Action deny-request -RequestId <ID>' -ForegroundColor White
    Write-Host '  approve-local  -- powershell -File scripts/teamlead-control.ps1 -Action approve-local -WorkerName <WORKER> [-PromptType auto|command_approval|edit_confirm|menu_approval]' -ForegroundColor White
    Write-Host '  approve-local-session -- powershell -File scripts/teamlead-control.ps1 -Action approve-local-session -WorkerName <WORKER> [-PromptType auto|menu_approval]' -ForegroundColor White
    Write-Host '  deny-local     -- powershell -File scripts/teamlead-control.ps1 -Action deny-local -WorkerName <WORKER> [-PromptType auto|command_approval|edit_confirm|menu_approval]' -ForegroundColor White
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
    Assert-TeamLeadPaneId $tlPaneId 'dispatch'
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
    $dispatchLock = Assert-TaskState $TaskId @("assigned", "blocked") $locks
    Assert-DispatchRuntimeClean -TaskId $TaskId -TargetState 'assigned' -Lock $dispatchLock
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
        $devDispatchMode = Resolve-DispatchMode -cfg $wConfig -phase 'dev'
        Write-Host ('  Worker: ' + $devWorker) -ForegroundColor White
        Write-Host ('  File:   ' + $taskFile.Name) -ForegroundColor White
        Write-Host ('  Domain: ' + $domain) -ForegroundColor White
        Write-Host ('  Mode:   ' + $devDispatchMode) -ForegroundColor White
        Write-Host '[DRY-RUN] No changes made.' -ForegroundColor Magenta
        return
    }

    # Ensure worker is running
    $defaultDevEngine = if ($wConfig.dev_engine) { [string]$wConfig.dev_engine } else { [string]$wConfig.engine }
    $devEngine = if ($DispatchEngine) { [string]$DispatchEngine } else { $defaultDevEngine }
    $devDispatchMode = Resolve-DispatchMode -cfg $wConfig -phase 'dev'
    $runId = New-TaskRunId -TaskId $TaskId -Phase "dev"
    if ($DispatchEngine) {
        Write-Host ('[INFO] Engine override: ' + $defaultDevEngine + ' -> ' + $devEngine) -ForegroundColor Cyan
    }

    $paneId = ''
    $headlessRunDir = ''
    $headlessPid = 0

    # 先确保监控已启动，避免 route 回调无人接管
    Ensure-RouteMonitor $tlPaneId
    Ensure-RouteNotifier $tlPaneId
    Ensure-RichMonitor $tlPaneId

    if ($devDispatchMode -eq 'headless') {
        if ($devEngine.ToLowerInvariant() -ne 'codex') {
            Write-Host ('[FAIL] Headless dispatch currently supports codex only. task=' + $TaskId + ' worker=' + $devWorker + ' engine=' + $devEngine) -ForegroundColor Red
            exit 1
        }
        $headlessScript = Join-Path $scriptDir 'start-headless-run.ps1'
        if (-not (Test-Path $headlessScript)) {
            Write-Host ('[FAIL] Headless runner not found: ' + $headlessScript) -ForegroundColor Red
            exit 1
        }
        $dispatchJson = & $headlessScript -TaskId $TaskId -WorkerName $devWorker -WorkDir $wConfig.workdir -Engine $devEngine -TaskFilePath $taskFile.FullName -RunId $runId -EmitJson
        $dispatchExit = $LASTEXITCODE
        if ($dispatchExit -ne 0) {
            Write-Host ('[FAIL] Headless dispatch failed for ' + $TaskId + ' (worker=' + $devWorker + ', exit=' + $dispatchExit + ')') -ForegroundColor Red
            Write-Host '       Task lock not updated. Please inspect runtime/runs and rerun dispatch.' -ForegroundColor Yellow
            exit 1
        }
        try {
            $dispatchResp = $dispatchJson | ConvertFrom-Json
        } catch {
            Write-Host '[FAIL] Headless dispatch did not return machine-readable result.' -ForegroundColor Red
            exit 1
        }
        if (-not $dispatchResp -or [string]$dispatchResp.status -ne 'dispatched') {
            Write-Host ('[FAIL] Headless dispatch failed: status=' + [string]$dispatchResp.status + ' message=' + [string]$dispatchResp.message) -ForegroundColor Red
            exit 1
        }
        $headlessRunDir = if ($dispatchResp.runDir) { [string]$dispatchResp.runDir } else { '' }
        $headlessPid = if ($dispatchResp.pid) { [int]$dispatchResp.pid } else { 0 }
    } else {
        $devConfig = @{ workdir = $wConfig.workdir; engine = $devEngine }
        $registeredDevEngine = Get-RegisteredWorkerEngine -WorkerName $devWorker
        $forceRestartForEngine = $false
        if ($registeredDevEngine -and $registeredDevEngine.ToLowerInvariant() -ne $devEngine.ToLowerInvariant()) {
            Write-Host ('[INFO] Worker ' + $devWorker + ' engine mismatch (' + $registeredDevEngine + ' -> ' + $devEngine + '), forcing restart...') -ForegroundColor Yellow
            $forceRestartForEngine = $true
        }
        $paneId = Ensure-WorkerRunning $devWorker $devConfig $tlPaneId -ForceRestart:$forceRestartForEngine

        # Dispatch task (BEFORE updating lock)
        $dispatchScript = Join-Path $scriptDir "dispatch-task.ps1"
        & $dispatchScript -WorkerPaneId $paneId -WorkerName $devWorker -TaskId $TaskId -TaskFilePath $taskFile.FullName -Engine $devEngine -TeamLeadPaneId $tlPaneId -RunId $runId
        $dispatchExit = $LASTEXITCODE
        if ($dispatchExit -ne 0) {
            Write-Host ('[FAIL] Dispatch failed for ' + $TaskId + ' (worker=' + $devWorker + ', pane=' + $paneId + ', exit=' + $dispatchExit + ')') -ForegroundColor Red
            Write-Host '       Task lock not updated. Please check worker pane output and rerun dispatch.' -ForegroundColor Yellow
            Stop-PaneApprovalWatcher -TaskId $TaskId -WorkerName $devWorker -Quiet | Out-Null
            exit 1
        }
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
        Set-ObjectField -obj $latestLock -name "dispatch_mode" -value $devDispatchMode
        if ($devDispatchMode -eq 'headless') {
            Set-ObjectField -obj $latestLock -name "headless_run_dir" -value $headlessRunDir
            Set-ObjectField -obj $latestLock -name "headless_pid" -value $headlessPid
            Set-ObjectField -obj $latestLock -name "pane_id" -value ""
        } else {
            Set-ObjectField -obj $latestLock -name "headless_run_dir" -value ""
            Set-ObjectField -obj $latestLock -name "headless_pid" -value 0
            Set-ObjectField -obj $latestLock -name "pane_id" -value $paneId
        }
        $latestLock.updated_at = $dispatchUpdatedAt
        $latestLock.updated_by = "teamlead-control/dispatch"
    } | Out-Null
    Add-TaskAttemptRecord -TaskId $TaskId -Phase "dev" -Worker $devWorker -Engine $devEngine -RunId $runId -DispatchAction "dispatch" -StartedAt $dispatchUpdatedAt | Out-Null

    # Ensure route monitor is alive for auto lock/doc-updater processing
    Ensure-RouteMonitor $tlPaneId
    Ensure-RouteNotifier $tlPaneId
    Ensure-RichMonitor $tlPaneId
    if ($devDispatchMode -eq 'pane') {
        Ensure-PaneApprovalWatcher -TaskId $TaskId -WorkerName $devWorker -WorkerPaneId $paneId -TeamLeadPaneId $tlPaneId -RunId $runId
    }

    Write-Host ''
    if ($devDispatchMode -eq 'headless') {
        Write-Host ('[OK] Task ' + $TaskId + ' dispatched to ' + $devWorker + ' (headless pid ' + $headlessPid + ')') -ForegroundColor Green
        if ($headlessRunDir) {
            Write-Host ('  run_dir: ' + $headlessRunDir) -ForegroundColor White
        }
    } else {
        Write-Host ('[OK] Task ' + $TaskId + ' dispatched to ' + $devWorker + ' (pane ' + $paneId + ')') -ForegroundColor Green
    }
    Write-Host ''
    Write-Host '[NEXT] Background watchers:' -ForegroundColor Cyan
    Write-Host '  route-monitor: auto ensured by controller' -ForegroundColor White
    Write-Host '  rich-monitor: auto ensured by controller (read-only dashboard)' -ForegroundColor White
    if ($devDispatchMode -eq 'pane') {
        Write-Host '  pane-approval-watcher: auto ensured by controller' -ForegroundColor White
        $approvalCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\pane-approval-watcher.ps1" -WorkerPaneId ' + $paneId + ' -WorkerName ' + $devWorker + ' -TaskId ' + $TaskId + ' -TeamLeadPaneId ' + $tlPaneId + ' -RunId ' + $runId
        Write-Host ('  (debug manual start): ' + $approvalCmd) -ForegroundColor DarkGray
    } else {
        Write-Host '  pane-approval-watcher: skipped (headless dispatch)' -ForegroundColor DarkGray
    }
    Write-Host '  dispatch/dispatch-qa commands must still be serial from Team Lead side (no parallel command launch).' -ForegroundColor Yellow
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
    Assert-TeamLeadPaneId $tlPaneId 'dispatch-qa'
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
    $dispatchLock = Assert-TaskState $TaskId @("waiting_qa") $locks
    Assert-DispatchRuntimeClean -TaskId $TaskId -TargetState 'waiting_qa' -Lock $dispatchLock
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
        $qaDispatchMode = Resolve-DispatchMode -cfg $wConfig -phase 'qa'
        Write-Host ('  Worker: ' + $qaWorker) -ForegroundColor White
        Write-Host ('  File:   ' + $taskFile.Name) -ForegroundColor White
        Write-Host ('  Mode:   ' + $qaDispatchMode) -ForegroundColor White
        Write-Host '[DRY-RUN] No changes made.' -ForegroundColor Magenta
        return
    }

    $defaultQaEngine = if ($wConfig.qa_engine) { [string]$wConfig.qa_engine } else { [string]$wConfig.engine }
    $qaEngine = if ($DispatchEngine) { [string]$DispatchEngine } else { $defaultQaEngine }
    $qaDispatchMode = Resolve-DispatchMode -cfg $wConfig -phase 'qa'
    $runId = New-TaskRunId -TaskId $TaskId -Phase "qa"
    if ($DispatchEngine) {
        Write-Host ('[INFO] Engine override: ' + $defaultQaEngine + ' -> ' + $qaEngine) -ForegroundColor Cyan
    }

    $paneId = ''
    $headlessRunDir = ''
    $headlessPid = 0

    # 先确保监控已启动，避免 route 回调无人接管
    Ensure-RouteMonitor $tlPaneId
    Ensure-RouteNotifier $tlPaneId
    Ensure-RichMonitor $tlPaneId

    if ($qaDispatchMode -eq 'headless') {
        if ($qaEngine.ToLowerInvariant() -ne 'codex') {
            Write-Host ('[FAIL] Headless dispatch currently supports codex only. task=' + $TaskId + ' worker=' + $qaWorker + ' engine=' + $qaEngine) -ForegroundColor Red
            exit 1
        }
        $headlessScript = Join-Path $scriptDir 'start-headless-run.ps1'
        if (-not (Test-Path $headlessScript)) {
            Write-Host ('[FAIL] Headless runner not found: ' + $headlessScript) -ForegroundColor Red
            exit 1
        }
        $dispatchJson = & $headlessScript -TaskId $TaskId -WorkerName $qaWorker -WorkDir $wConfig.workdir -Engine $qaEngine -TaskFilePath $taskFile.FullName -RunId $runId -EmitJson
        $dispatchExit = $LASTEXITCODE
        if ($dispatchExit -ne 0) {
            Write-Host ('[FAIL] Headless QA dispatch failed for ' + $TaskId + ' (worker=' + $qaWorker + ', exit=' + $dispatchExit + ')') -ForegroundColor Red
            Write-Host '       Task lock not updated. Please inspect runtime/runs and rerun dispatch-qa.' -ForegroundColor Yellow
            exit 1
        }
        try {
            $dispatchResp = $dispatchJson | ConvertFrom-Json
        } catch {
            Write-Host '[FAIL] Headless QA dispatch did not return machine-readable result.' -ForegroundColor Red
            exit 1
        }
        if (-not $dispatchResp -or [string]$dispatchResp.status -ne 'dispatched') {
            Write-Host ('[FAIL] Headless QA dispatch failed: status=' + [string]$dispatchResp.status + ' message=' + [string]$dispatchResp.message) -ForegroundColor Red
            exit 1
        }
        $headlessRunDir = if ($dispatchResp.runDir) { [string]$dispatchResp.runDir } else { '' }
        $headlessPid = if ($dispatchResp.pid) { [int]$dispatchResp.pid } else { 0 }
    } else {
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

        # Dispatch FIRST, then update lock
        $dispatchScript = Join-Path $scriptDir "dispatch-task.ps1"
        & $dispatchScript -WorkerPaneId $paneId -WorkerName $qaWorker -TaskId $TaskId -TaskFilePath $taskFile.FullName -Engine $qaEngine -TeamLeadPaneId $tlPaneId -RunId $runId
        $dispatchExit = $LASTEXITCODE
        if ($dispatchExit -ne 0) {
            Write-Host ('[FAIL] Dispatch QA failed for ' + $TaskId + ' (worker=' + $qaWorker + ', pane=' + $paneId + ', exit=' + $dispatchExit + ')') -ForegroundColor Red
            Write-Host '       Task lock not updated. Please check worker pane output and rerun dispatch-qa.' -ForegroundColor Yellow
            Stop-PaneApprovalWatcher -TaskId $TaskId -WorkerName $qaWorker -Quiet | Out-Null
            exit 1
        }
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
        Set-ObjectField -obj $latestLock -name "dispatch_mode" -value $qaDispatchMode
        if ($qaDispatchMode -eq 'headless') {
            Set-ObjectField -obj $latestLock -name "headless_run_dir" -value $headlessRunDir
            Set-ObjectField -obj $latestLock -name "headless_pid" -value $headlessPid
            Set-ObjectField -obj $latestLock -name "pane_id" -value ""
        } else {
            Set-ObjectField -obj $latestLock -name "headless_run_dir" -value ""
            Set-ObjectField -obj $latestLock -name "headless_pid" -value 0
            Set-ObjectField -obj $latestLock -name "pane_id" -value $paneId
        }
        $latestLock.updated_at = $dispatchUpdatedAt
        $latestLock.updated_by = "teamlead-control/dispatch-qa"
    } | Out-Null
    Add-TaskAttemptRecord -TaskId $TaskId -Phase "qa" -Worker $qaWorker -Engine $qaEngine -RunId $runId -DispatchAction "dispatch-qa" -StartedAt $dispatchUpdatedAt | Out-Null

    # Ensure route monitor is alive for auto lock/doc-updater processing
    Ensure-RouteMonitor $tlPaneId
    Ensure-RouteNotifier $tlPaneId
    Ensure-RichMonitor $tlPaneId
    if ($qaDispatchMode -eq 'pane') {
        Ensure-PaneApprovalWatcher -TaskId $TaskId -WorkerName $qaWorker -WorkerPaneId $paneId -TeamLeadPaneId $tlPaneId -RunId $runId
    }

    Write-Host ''
    if ($qaDispatchMode -eq 'headless') {
        Write-Host ('[OK] QA task ' + $TaskId + ' dispatched to ' + $qaWorker + ' (headless pid ' + $headlessPid + ')') -ForegroundColor Green
        if ($headlessRunDir) {
            Write-Host ('  run_dir: ' + $headlessRunDir) -ForegroundColor White
        }
    } else {
        Write-Host ('[OK] QA task ' + $TaskId + ' dispatched to ' + $qaWorker + ' (pane ' + $paneId + ')') -ForegroundColor Green
    }
    Write-Host ''
    Write-Host '[NEXT] Background watchers:' -ForegroundColor Cyan
    Write-Host '  route-monitor: auto ensured by controller' -ForegroundColor White
    Write-Host '  rich-monitor: auto ensured by controller (read-only dashboard)' -ForegroundColor White
    if ($qaDispatchMode -eq 'pane') {
        Write-Host '  pane-approval-watcher: auto ensured by controller' -ForegroundColor White
        $approvalCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "E:\moxton-ccb\scripts\pane-approval-watcher.ps1" -WorkerPaneId ' + $paneId + ' -WorkerName ' + $qaWorker + ' -TaskId ' + $TaskId + ' -TeamLeadPaneId ' + $tlPaneId + ' -RunId ' + $runId
        Write-Host ('  (debug manual start): ' + $approvalCmd) -ForegroundColor DarkGray
    } else {
        Write-Host '  pane-approval-watcher: skipped (headless dispatch)' -ForegroundColor DarkGray
    }
    Write-Host '  dispatch/dispatch-qa commands must still be serial from Team Lead side (no parallel command launch).' -ForegroundColor Yellow
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
    $prevState = if ($lock.state) { [string]$lock.state } else { '' }
    $assignedWorker = Get-AssignedWorkerFromLock -TaskId $TaskId -lock $lock -State $prevState -WorkerMap $workerMap
    $dispatchMode = Get-LockDispatchMode -lock $lock
    $headlessSnapshot = Read-HeadlessRunSnapshot -TaskId $TaskId -Lock $lock
    $workerAlive = if ($dispatchMode -eq 'headless') {
        if ($headlessSnapshot) { [bool]$headlessSnapshot.process_alive } else { $false }
    } else {
        if ($assignedWorker) { Test-WorkerPaneAlive -WorkerName $assignedWorker } else { $false }
    }
    $phase = Resolve-PhaseFromWorkerName -WorkerName (Get-TaskLatestRouteWorker -lock $lock)
    if (-not $phase) {
        $phase = Resolve-PhaseFromWorkerName -WorkerName $assignedWorker
    }
    if (-not $phase) {
        $phase = if ($TargetState -eq 'waiting_qa') { 'qa' } else { 'dev' }
    }

    $now = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
    Update-TaskLocksData {
        param($latest)
        if ($latest.locks.PSObject.Properties.Name -notcontains $TaskId) {
            throw ('Task missing during requeue commit: ' + $TaskId)
        }
        $latestLock = $latest.locks.$TaskId
        $latestLock.state = $TargetState
        $latestLock.updated_at = $now
        $latestLock.updated_by = 'teamlead-control/requeue'
        Set-NoteField -obj $latestLock -value ('Requeued to ' + $TargetState + ' by team lead: ' + $RequeueReason)
        Clear-TaskRuntimeFields -lock $latestLock -ClearAssignedWorker -ClearDispatchMode
        Set-ObjectField -obj $latestLock -name 'last_requeue' -value @{
            previous_state = $prevState
            target_state = $TargetState
            reason = $RequeueReason
            requested_at = $now
            requested_by = 'teamlead-control/requeue'
        }
        return $null
    }

    Update-LatestTaskAttempt -TaskId $TaskId -Phase $phase -Result 'requeued' -FinalState $TargetState -EndedAt $now -RequeueReason $RequeueReason -UpdatedBy 'teamlead-control/requeue' | Out-Null
    if ($assignedWorker) {
        Stop-PaneApprovalWatcher -TaskId $TaskId -WorkerName $assignedWorker -Quiet | Out-Null
    }

    Write-Host ('[OK] Task ' + $TaskId + ' requeued: ' + $prevState + ' -> ' + $TargetState) -ForegroundColor Green
    Write-Host ('     Reason: ' + $RequeueReason) -ForegroundColor Gray
    Write-Host '     Requeue only updates status/history. It does not notify the old worker and does not auto-dispatch.' -ForegroundColor Cyan
    if ($workerAlive) {
        if ($dispatchMode -eq 'headless') {
            Write-Host ('[WARN] Previous headless run is still alive for task ' + $TaskId) -ForegroundColor Yellow
            Write-Host '       If you need hard stop + clean restart, use recover -RecoverAction restart-task before re-dispatch.' -ForegroundColor Yellow
        } elseif ($assignedWorker) {
            Write-Host ('[WARN] Previous worker is still online: ' + $assignedWorker) -ForegroundColor Yellow
            Write-Host '       Do not paste the reject reason into that pane. Redispatch later with a fresh context.' -ForegroundColor Yellow
        }
        if ($TargetState -eq 'waiting_qa') {
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
        $PendingLocalApproval,
        $WorkerMap,
        $GateContext
    )

    if (-not $Lock) { return $null }

    $state = if ($Lock.state) { ([string]$Lock.state).ToLower() } else { '' }
    $commands = New-Object System.Collections.Generic.List[string]
    $assignedWorker = Get-AssignedWorkerFromLock -TaskId $TaskId -lock $Lock -State $state -WorkerMap $WorkerMap
    $dispatchMode = Get-LockDispatchMode -lock $Lock
    $headlessSnapshot = Read-HeadlessRunSnapshot -TaskId $TaskId -Lock $Lock
    $runtimeResidue = Get-TaskRuntimeResidue -TaskId $TaskId -Lock $Lock
    $workerAlive = if ($dispatchMode -eq 'headless') {
        if ($headlessSnapshot) { [bool]$headlessSnapshot.process_alive } else { $false }
    } else {
        if ($assignedWorker) { Test-WorkerPaneAlive -WorkerName $assignedWorker } else { $false }
    }
    $routeWorker = Get-TaskLatestRouteWorker -lock $Lock
    $phase = Resolve-PhaseFromWorkerName -WorkerName $routeWorker
    if (-not $phase) {
        $phase = Resolve-PhaseFromWorkerName -WorkerName $assignedWorker
    }
    $activityUtc = Get-TaskLatestActivityUtc -lock $Lock
    if ($headlessSnapshot -and $headlessSnapshot.runtime_updated_utc) {
        if (-not $activityUtc -or $headlessSnapshot.runtime_updated_utc -gt $activityUtc) {
            $activityUtc = $headlessSnapshot.runtime_updated_utc
        }
    }
    $activityAgeText = Get-TaskActivityAgeText -ActivityUtc $activityUtc
    $pendingApprovalCount = @($PendingApprovals).Count
    $hasPendingApprovals = ($pendingApprovalCount -gt 0)
    $pendingLocalApproval = $PendingLocalApproval
    $hasPendingLocalApproval = ($null -ne $pendingLocalApproval -and [string]$pendingLocalApproval.status -eq 'pending_teamlead')
    $staleThresholdMinutes = Get-StaleRunThresholdMinutes
    $isStaleRun = $false
    if ($state -in @('in_progress', 'qa') -and $activityUtc -and -not $hasPendingApprovals -and -not $hasPendingLocalApproval) {
        $ageMinutes = ((Get-Date).ToUniversalTime() - $activityUtc).TotalMinutes
        if ($ageMinutes -ge $staleThresholdMinutes) {
            $isStaleRun = $true
        }
    }

    $archiveBlocking = @()
    if ($GateContext) {
        $archiveBlocking += @($GateContext.dispatch_todo | Where-Object { $_ -ne $TaskId })
        $archiveBlocking += @($GateContext.running | Where-Object { $_ -ne $TaskId })
        $archiveBlocking += @($GateContext.other_active | Where-Object { -not $_.StartsWith($TaskId + ':') })
    }

    $blockedBodyPreview = Get-LockRouteBodyPreview -Lock $Lock
    $blockedDecision = Get-BlockedDecision -body $blockedBodyPreview
    $serviceRestoreTaskId = Get-BackendServiceRestoreTaskId

    $summary = ''
    $color = 'Gray'
    $priority = 500

    switch ($state) {
        'assigned' {
            if ($runtimeResidue -and $runtimeResidue.has_residue) {
                $summary = '待派遣前需清理残留运行态'
                $color = 'Red'
                $priority = 15
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-task -TaskId ' + $TaskId) | Out-Null
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action dispatch -TaskId ' + $TaskId) | Out-Null
            } else {
                $summary = '待派遣开发'
                $color = 'Yellow'
                $priority = 60
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action dispatch -TaskId ' + $TaskId) | Out-Null
            }
        }
        'waiting_qa' {
            if ($runtimeResidue -and $runtimeResidue.has_residue) {
                $summary = '待派遣 QA 前需清理残留运行态'
                $color = 'Red'
                $priority = 15
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-task -TaskId ' + $TaskId) | Out-Null
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action dispatch-qa -TaskId ' + $TaskId) | Out-Null
            } else {
                $summary = '待派遣 QA'
                $color = 'Cyan'
                $priority = 70
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action dispatch-qa -TaskId ' + $TaskId) | Out-Null
            }
        }
        'in_progress' {
            if ($hasPendingLocalApproval) {
                $localWorker = if ($pendingLocalApproval.worker) { [string]$pendingLocalApproval.worker } else { $assignedWorker }
                $localPromptType = if ($pendingLocalApproval.prompt_type) { [string]$pendingLocalApproval.prompt_type } else { 'auto' }
                $summary = '开发中，但有本地审批待处理'
                $color = 'Red'
                $priority = 9
                if ($localWorker) {
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action approve-local -WorkerName ' + $localWorker + ' -PromptType ' + $localPromptType) | Out-Null
                    if ($localPromptType -eq 'menu_approval') {
                        $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action approve-local-session -WorkerName ' + $localWorker + ' -PromptType menu_approval') | Out-Null
                    }
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action deny-local -WorkerName ' + $localWorker + ' -PromptType ' + $localPromptType) | Out-Null
                }
            } elseif ($hasPendingApprovals) {
                $summary = '开发中，但有待处理审批'
                $color = 'Red'
                $priority = 10
                foreach ($req in @($PendingApprovals)) {
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action approve-request -RequestId ' + [string]$req.id) | Out-Null
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action deny-request -RequestId ' + [string]$req.id) | Out-Null
                }
            } elseif ($dispatchMode -eq 'headless' -and $headlessSnapshot -and $headlessSnapshot.runtime_status -eq 'success' -and -not $headlessSnapshot.process_alive) {
                $summary = '开发 headless 已退出，等待 route 收口'
                $color = 'Yellow'
                $priority = 18
            } elseif ($dispatchMode -eq 'headless' -and $headlessSnapshot -and $headlessSnapshot.runtime_status -eq 'failed') {
                $summary = '开发 headless 运行失败，建议 restart-task 后重派'
                $color = 'Red'
                $priority = 19
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-task -TaskId ' + $TaskId) | Out-Null
            } elseif (-not $workerAlive) {
                if ($dispatchMode -eq 'headless') {
                    $summary = '开发 headless 执行漂移，建议 restart-task 后重派'
                } else {
                    $summary = '开发执行漂移，worker 已离线'
                    if ($assignedWorker) {
                        $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-worker -WorkerName ' + $assignedWorker) | Out-Null
                    }
                }
                $color = 'Red'
                $priority = 20
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-task -TaskId ' + $TaskId) | Out-Null
            } elseif ($isStaleRun) {
                if ($dispatchMode -eq 'headless') {
                    $summary = '开发 headless 长时间无新 route/输出 [STALE-RUN ' + $activityAgeText + ']'
                } else {
                    $summary = '开发长时间无新 route [STALE-RUN ' + $activityAgeText + ']'
                    if ($assignedWorker) {
                        $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-worker -WorkerName ' + $assignedWorker) | Out-Null
                    }
                }
                $color = 'Yellow'
                $priority = 25
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-task -TaskId ' + $TaskId) | Out-Null
            } else {
                if ($dispatchMode -eq 'headless') {
                    $summary = '开发进行中（headless），等待新 route'
                    $color = 'Cyan'
                } else {
                    $summary = '开发进行中，等待新 route'
                }
            }
        }
        'qa' {
            if ($hasPendingLocalApproval) {
                $localWorker = if ($pendingLocalApproval.worker) { [string]$pendingLocalApproval.worker } else { $assignedWorker }
                $localPromptType = if ($pendingLocalApproval.prompt_type) { [string]$pendingLocalApproval.prompt_type } else { 'auto' }
                $summary = 'QA 中，但有本地审批待处理'
                $color = 'Red'
                $priority = 9
                if ($localWorker) {
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action approve-local -WorkerName ' + $localWorker + ' -PromptType ' + $localPromptType) | Out-Null
                    if ($localPromptType -eq 'menu_approval') {
                        $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action approve-local-session -WorkerName ' + $localWorker + ' -PromptType menu_approval') | Out-Null
                    }
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action deny-local -WorkerName ' + $localWorker + ' -PromptType ' + $localPromptType) | Out-Null
                }
            } elseif ($hasPendingApprovals) {
                $summary = 'QA 中，但有待处理审批'
                $color = 'Red'
                $priority = 10
                foreach ($req in @($PendingApprovals)) {
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action approve-request -RequestId ' + [string]$req.id) | Out-Null
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action deny-request -RequestId ' + [string]$req.id) | Out-Null
                }
            } elseif ($dispatchMode -eq 'headless' -and $headlessSnapshot -and $headlessSnapshot.runtime_status -eq 'success' -and -not $headlessSnapshot.process_alive) {
                $summary = 'QA headless 已退出，等待 route 收口'
                $color = 'Yellow'
                $priority = 18
            } elseif ($dispatchMode -eq 'headless' -and $headlessSnapshot -and $headlessSnapshot.runtime_status -eq 'failed') {
                $summary = 'QA headless 运行失败，建议 restart-task 后重派'
                $color = 'Red'
                $priority = 19
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-task -TaskId ' + $TaskId) | Out-Null
            } elseif (-not $workerAlive) {
                if ($dispatchMode -eq 'headless') {
                    $summary = 'QA headless 执行漂移，建议 restart-task 后重派'
                } else {
                    $summary = 'QA 执行漂移，worker 已离线'
                    if ($assignedWorker) {
                        $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-worker -WorkerName ' + $assignedWorker) | Out-Null
                    }
                }
                $color = 'Red'
                $priority = 20
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-task -TaskId ' + $TaskId) | Out-Null
            } elseif ($isStaleRun) {
                if ($dispatchMode -eq 'headless') {
                    $summary = 'QA headless 长时间无新 route/输出 [STALE-RUN ' + $activityAgeText + ']'
                } else {
                    $summary = 'QA 长时间无新 route [STALE-RUN ' + $activityAgeText + ']'
                    if ($assignedWorker) {
                        $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-worker -WorkerName ' + $assignedWorker) | Out-Null
                    }
                }
                $color = 'Yellow'
                $priority = 25
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-task -TaskId ' + $TaskId) | Out-Null
            } else {
                if ($dispatchMode -eq 'headless') {
                    $summary = 'QA 进行中（headless），等待新 route'
                    $color = 'Cyan'
                } else {
                    $summary = 'QA 进行中，等待新 route'
                }
            }
        }
        'qa_passed' {
            if ($archiveBlocking.Count -gt 0) {
                $summary = 'QA 已通过，等待其它活跃任务收口后再 archive'
                $color = 'Yellow'
                $priority = 80
            } else {
                $summary = 'QA 已通过，可复审后 archive'
                $color = 'Green'
                $priority = 90
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action archive -TaskId ' + $TaskId) | Out-Null
            }
            $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action requeue -TaskId ' + $TaskId + ' -TargetState waiting_qa -RequeueReason "review_reject"') | Out-Null
        }
        'fail' {
            if ($phase -eq 'qa' -and $blockedDecision -eq 'service_down') {
                $summary = 'QA fail（环境阻塞），先恢复后端服务再重派 QA'
                $color = 'Red'
                $priority = 21
                $commands.Add('powershell -Command "curl.exe -sS http://localhost:3033/health"') | Out-Null
                if ($serviceRestoreTaskId) {
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action dispatch -TaskId ' + $serviceRestoreTaskId) | Out-Null
                }
            } elseif ($phase -eq 'qa') {
                $summary = 'QA fail，按驳回处理并回开发'
                $color = 'Red'
                $priority = 29
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action requeue -TaskId ' + $TaskId + ' -TargetState assigned -RequeueReason "qa_fail"') | Out-Null
            } else {
                $summary = '开发 fail，按 blocked 终态处理并优先 restart-task'
                $color = 'Red'
                $priority = 34
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-task -TaskId ' + $TaskId) | Out-Null
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action requeue -TaskId ' + $TaskId + ' -TargetState assigned -RequeueReason "dev_fail"') | Out-Null
            }
        }
        'blocked' {
            if ($hasPendingApprovals) {
                $summary = 'blocked，先处理审批'
                $color = 'Red'
                $priority = 10
                foreach ($req in @($PendingApprovals)) {
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action approve-request -RequestId ' + [string]$req.id) | Out-Null
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action deny-request -RequestId ' + [string]$req.id) | Out-Null
                }
            } elseif ($phase -eq 'qa' -and $blockedDecision -eq 'service_down') {
                $summary = 'QA 因 3033/health 不可达而 blocked，先恢复后端服务再重派 QA'
                $color = 'Red'
                $priority = 22
                $commands.Add('powershell -Command "curl.exe -sS http://localhost:3033/health"') | Out-Null
                if ($serviceRestoreTaskId) {
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action dispatch -TaskId ' + $serviceRestoreTaskId) | Out-Null
                }
            } elseif ($phase -eq 'qa') {
                $summary = 'QA 驳回后待回开发'
                $color = 'Red'
                $priority = 30
                $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action requeue -TaskId ' + $TaskId + ' -TargetState assigned -RequeueReason "qa_reject"') | Out-Null
            } else {
                $summary = '开发 blocked，需任务级恢复后再派遣'
                $color = 'Red'
                $priority = 35
                if ($dispatchMode -eq 'headless') {
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-task -TaskId ' + $TaskId) | Out-Null
                } else {
                    if ($assignedWorker) {
                        $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action recover -RecoverAction restart-worker -WorkerName ' + $assignedWorker) | Out-Null
                    }
                    $commands.Add('powershell -File scripts/teamlead-control.ps1 -Action requeue -TaskId ' + $TaskId + ' -TargetState assigned -RequeueReason "manual_recovery"') | Out-Null
                }
            }
        }
        'archiving' {
            $summary = '归档链路进行中，等待 doc-updater / repo-committer'
            $color = 'Cyan'
            $priority = 110
        }
        'completed' {
            $summary = '已完成'
            $color = 'Green'
            $priority = 900
        }
        default {
            $summary = '未知状态，建议人工检查'
            $color = 'Yellow'
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
        dispatch_mode = $dispatchMode
        headless_snapshot = $headlessSnapshot
        runtime_residue = $runtimeResidue
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
    $tlPaneId = Normalize-PaneId ([string]$env:WEZTERM_PANE)
    if (-not $tlPaneId -and $env:WEZTERM_PANE_ID) { $tlPaneId = Normalize-PaneId ([string]$env:WEZTERM_PANE_ID) }
    if (-not $tlPaneId) { $tlPaneId = Normalize-PaneId ([string]$env:TEAM_LEAD_PANE_ID) }
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

    # Route notifications
    Write-Host ""
    Write-Host '--- Route Notifications ---' -ForegroundColor Cyan
    $routeNotifyEnabled = $true
    $routeFlag = $env:CCB_ROUTE_MONITOR_NOTIFY
    if ($routeFlag) {
        $routeNorm = $routeFlag.Trim().ToLowerInvariant()
        if ($routeNorm -in @("0","false","no","off")) { $routeNotifyEnabled = $false }
    }
    $routeColor = if ($routeNotifyEnabled) { 'Green' } else { 'Yellow' }
    $routeText = if ($routeNotifyEnabled) { 'enabled' } else { 'disabled' }
    Write-Host ('  mode=route-monitor-write + route-notifier-wake notify=' + $routeText + ' scope=mcp-route-only') -ForegroundColor $routeColor

    # Workers
    Write-Host ''
    Write-Host '--- Workers ---' -ForegroundColor Cyan
    try { Reconcile-WorkerRegistryFromPanes | Out-Null } catch {}
    $regScript = Join-Path $scriptDir "worker-registry.ps1"
    if (Test-Path $regScript) {
        try { & $regScript -Action list } catch { Write-Host '  (registry list error, run health-check)' -ForegroundColor Yellow }
    }

    Write-Host ''
    Write-Host '--- Pane Approval Watchers ---' -ForegroundColor Cyan
    $watcherCleanup = Cleanup-StalePaneApprovalWatchers
    $watcherStore = Read-PaneApprovalWatcherStore
    $watcherEntries = @(
        (Convert-ToWatcherEntryMap $watcherStore.watchers).GetEnumerator() |
        Sort-Object Name
    )
    if ($watcherEntries.Count -eq 0) {
        Write-Host '  (no active pane approval watchers)' -ForegroundColor Gray
    } else {
        foreach ($watcherEntry in $watcherEntries) {
            $entry = $watcherEntry.Value
            $statusText = if ($entry.status) { [string]$entry.status } else { 'unknown' }
            $reasonText = if ($entry.reason) { [string]$entry.reason } else { '' }
            $lastSeenText = if ($entry.last_seen) { [string]$entry.last_seen } else { '-' }
            $line = '  ' + ([string]$entry.task).PadRight(18) + ' worker=' + [string]$entry.worker + ' pane=' + [string]$entry.worker_pane_id + ' status=' + $statusText
            if ($entry.run_id) {
                $line += ' run=' + [string]$entry.run_id
            }
            if ($reasonText) {
                $line += ' reason=' + $reasonText
            }
            $line += ' last_seen=' + $lastSeenText
            $color = switch ($statusText) {
                'active' { 'Cyan' }
                'waiting_wezterm' { 'Yellow' }
                'stopped' { 'Red' }
                default { 'Gray' }
            }
            Write-Host $line -ForegroundColor $color
        }
    }
    if ($watcherCleanup.removed -gt 0) {
        Write-Host ('  [auto-cleanup] removed=' + $watcherCleanup.removed + ' killed=' + $watcherCleanup.killed) -ForegroundColor DarkGray
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

        Write-Host '--- Team Lead Deliveries ---' -ForegroundColor Cyan
    $delivery = Get-TeamLeadDeliverySnapshot
    if ($delivery.monitor) {
        $monitorStatus = if ($delivery.monitor.status) { [string]$delivery.monitor.status } else { 'unknown' }
        $monitorColor = switch ($monitorStatus) {
            'running' { 'Green' }
            'starting' { 'Yellow' }
            'error' { 'Red' }
            default { 'Gray' }
        }
        $paneText = if ($delivery.monitor.teamlead_pane_id) { [string]$delivery.monitor.teamlead_pane_id } else { '-' }
        $lastLoopText = '-'
        if ($delivery.monitor.last_loop_at) {
            $lastLoopUtc = ConvertTo-UtcDateSafe $delivery.monitor.last_loop_at
            if ($lastLoopUtc) { $lastLoopText = Get-TaskActivityAgeText -ActivityUtc $lastLoopUtc }
        }
        $monitorPaneText = if ($delivery.monitor.monitor_pane_id) { [string]$delivery.monitor.monitor_pane_id } else { '-' }
        Write-Host ('  route-monitor status=' + $monitorStatus + ' target=' + $paneText + ' monitor_pane=' + $monitorPaneText + ' role=lock-writer last_loop=' + $lastLoopText) -ForegroundColor $monitorColor
        if ($delivery.monitor.note) {
            Write-Host ('  monitor note=' + [string]$delivery.monitor.note) -ForegroundColor DarkGray
        }
    } else {
        Write-Host '  (route-monitor state not found)' -ForegroundColor Yellow
    }
    if ($delivery.notifier) {
        $notifierStatus = if ($delivery.notifier.status) { [string]$delivery.notifier.status } else { 'unknown' }
        $notifierColor = switch ($notifierStatus) {
            'running' { 'Green' }
            'starting' { 'Yellow' }
            'error' { 'Red' }
            default { 'Gray' }
        }
        $notifierTarget = if ($delivery.notifier.teamlead_pane_id) { [string]$delivery.notifier.teamlead_pane_id } else { '-' }
        $notifierPaneText = if ($delivery.notifier.notifier_pane_id) { [string]$delivery.notifier.notifier_pane_id } else { '-' }
        $notifierLastLoop = '-'
        if ($delivery.notifier.last_loop_at) {
            $notifierLastLoopUtc = ConvertTo-UtcDateSafe $delivery.notifier.last_loop_at
            if ($notifierLastLoopUtc) { $notifierLastLoop = Get-TaskActivityAgeText -ActivityUtc $notifierLastLoopUtc }
        }
        Write-Host ('  route-notifier status=' + $notifierStatus + ' target=' + $notifierTarget + ' notifier_pane=' + $notifierPaneText + ' role=teamlead-wake last_loop=' + $notifierLastLoop) -ForegroundColor $notifierColor
        if ($delivery.notifier.note) {
            Write-Host ('  notifier note=' + [string]$delivery.notifier.note) -ForegroundColor DarkGray
        }
    } else {
        Write-Host '  (route-notifier state not found)' -ForegroundColor Yellow
    }
    if (-not (Test-RichMonitorEnabled)) {
        Write-Host '  rich-monitor disabled by CCB_DISABLE_RICH_MONITOR=1' -ForegroundColor DarkGray
    } elseif ($delivery.rich) {
        $richStatus = if ($delivery.rich.status) { [string]$delivery.rich.status } else { 'unknown' }
        $richColor = switch ($richStatus) {
            'running' { 'Green' }
            'starting' { 'Yellow' }
            'error' { 'Red' }
            default { 'Gray' }
        }
        $richPaneText = if ($delivery.rich.monitor_pane_id) { [string]$delivery.rich.monitor_pane_id } else { '-' }
        $richLastLoop = '-'
        if ($delivery.rich.last_loop_at) {
            $richLastLoopUtc = ConvertTo-UtcDateSafe $delivery.rich.last_loop_at
            if ($richLastLoopUtc) { $richLastLoop = Get-TaskActivityAgeText -ActivityUtc $richLastLoopUtc }
        }
        $richTaskCount = 0
        if ($null -ne $delivery.rich.visible_tasks) {
            try {
                if ($delivery.rich.visible_tasks -is [System.Collections.IEnumerable] -and -not ($delivery.rich.visible_tasks -is [string])) {
                    $richTaskCount = @($delivery.rich.visible_tasks).Count
                } else {
                    $richTaskCount = [int]$delivery.rich.visible_tasks
                }
            } catch {
                $richTaskCount = 0
            }
        }
        $richLayout = if ($delivery.rich.layout_mode) { [string]$delivery.rich.layout_mode } else { 'standalone' }
        $richLayoutLabel = switch ($richLayout) {
            'merged-right' { '同窗右栏' }
            'standalone' { '独立窗口' }
            default { $richLayout }
        }
        Write-Host ('  rich-monitor 状态=' + $richStatus + ' pane=' + $richPaneText + ' 布局=' + $richLayoutLabel + ' 最近轮询=' + $richLastLoop + ' 可见任务=' + $richTaskCount) -ForegroundColor $richColor
        if ($delivery.rich.note) {
            Write-Host ('  rich note=' + [string]$delivery.rich.note) -ForegroundColor DarkGray
        }
    } else {
        Write-Host '  （未找到 rich-monitor 状态文件）' -ForegroundColor Yellow
    }
    Write-Host ('  recent delivery attempts: ok=' + $delivery.success_count + ' fail=' + $delivery.failure_count) -ForegroundColor DarkGray
    $unresolvedDeliveries = @($delivery.unresolved | Select-Object -First 5)
    if ($unresolvedDeliveries.Count -eq 0) {
        if ($delivery.failure_count -gt 0) {
            Write-Host '  (recent notify failures recovered by retry)' -ForegroundColor DarkGray
        } else {
            Write-Host '  (no unresolved delivery failures)' -ForegroundColor Gray
        }
    } else {
        foreach ($entry in $unresolvedDeliveries) {
            $task = if ($entry.task) { [string]$entry.task } else { '-' }
            $worker = if ($entry.worker) { [string]$entry.worker } else { '-' }
            $status = if ($entry.status) { [string]$entry.status } else { '-' }
            $action = if ($entry.action) { [string]$entry.action } else { '-' }
            $attempt = if ($entry.attempt) { [string]$entry.attempt } else { '1' }
            $error = if ($entry.error) { [string]$entry.error } else { 'unknown' }
            if ($error.Length -gt 100) { $error = $error.Substring(0, 100) + '...' }
            $age = '-'
            if ($entry.at) {
                $ageUtc = ConvertTo-UtcDateSafe $entry.at
                if ($ageUtc) { $age = Get-TaskActivityAgeText -ActivityUtc $ageUtc }
            }
            Write-Host ('  ' + $task.PadRight(18) + ' worker=' + $worker + ' status=' + $status + ' action=' + $action + ' attempt=' + $attempt + ' last=' + $age + ' err=' + $error) -ForegroundColor Yellow
        }
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

    Write-Host ''
    Write-Host '--- Local Approval State ---' -ForegroundColor Cyan
    $localApprovalState = Read-LocalApprovalState
    $pendingLocalApprovalsByTask = @{}
    $pendingLocalApprovals = @(
        (Convert-ToObjectMap $localApprovalState.workers).GetEnumerator() |
        ForEach-Object { $_.Value } |
        Where-Object { $_ -and [string]$_.status -eq 'pending_teamlead' } |
        Sort-Object opened_at
    )
    foreach ($local in $pendingLocalApprovals) {
        $localTask = if ($local.task) { [string]$local.task } else { '' }
        if (-not $localTask) { continue }
        $pendingLocalApprovalsByTask[$localTask] = $local
    }
    if ($pendingLocalApprovals.Count -eq 0) {
        Write-Host '  (no pending local pane approvals)' -ForegroundColor Gray
    } else {
        foreach ($local in $pendingLocalApprovals) {
            $worker = if ($local.worker) { [string]$local.worker } else { '-' }
            $task = if ($local.task) { [string]$local.task } else { '-' }
            $risk = if ($local.risk) { [string]$local.risk } else { 'unknown' }
            $prompt = if ($local.prompt_type) { [string]$local.prompt_type } else { 'auto' }
            $preview = if ($local.preview) { [string]$local.preview } else { '-' }
            if ($preview.Length -gt 100) { $preview = $preview.Substring(0, 100) + '...' }
            Write-Host ('  ' + $task.PadRight(18) + ' worker=' + $worker + ' risk=' + $risk + ' prompt=' + $prompt + ' preview=' + $preview) -ForegroundColor Red
        }
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
            $dispatchMode = Get-LockDispatchMode -lock $l
            $line = '  ' + $tidPad + ' state=' + $lState
            if ($tid -notmatch '^(BACKEND|SHOP-FE|ADMIN-FE)-\d+$') {
                $line += ' [INVALID-TASKID]'
                $stateColor = "Red"
                $invalidLocks.Add($tid) | Out-Null
            }
            $displayWorker = Get-AssignedWorkerFromLock -TaskId $tid -lock $l -State ([string]$lState) -WorkerMap $workerMapForStatus
            if ($displayWorker) {
                if ($dispatchMode -eq 'headless') {
                    $line += ' worker=' + $displayWorker + ' mode=headless'
                } elseif ([string]$lState -in @('in_progress', 'qa')) {
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
            $recApprovals = @()
            if ($pendingApprovalsByTask.ContainsKey($tid)) {
                $recApprovals = @($pendingApprovalsByTask[$tid].ToArray())
            }
            $recLocalApproval = $null
            if ($pendingLocalApprovalsByTask.ContainsKey($tid)) {
                $recLocalApproval = $pendingLocalApprovalsByTask[$tid]
            }
            $recommendation = Get-TaskRecommendation -TaskId $tid -Lock $l -PendingApprovals $recApprovals -PendingLocalApproval $recLocalApproval -WorkerMap $workerMapForStatus -GateContext $gate
            if ($recommendation -and $recommendation.activity_age -and $recommendation.activity_age -ne '-') {
                $line += ' last=' + $recommendation.activity_age
            } elseif ($activityUtc) {
                $line += ' last=' + (Get-TaskActivityAgeText -ActivityUtc $activityUtc)
            }
            if ($recommendation) {
                if ($recommendation.dispatch_mode -eq 'headless' -and $recommendation.headless_snapshot) {
                    $hs = $recommendation.headless_snapshot
                    if ($hs.runtime_status) {
                        $line += ' runtime=' + $hs.runtime_status
                    }
                    if ($hs.runtime_phase) {
                        $line += '/' + $hs.runtime_phase
                    }
                    if ($hs.process_id -gt 0) {
                        $line += ' pid=' + [string]$hs.process_id
                    }
                    $line += ' proc=' + $(if ($hs.process_alive) { 'alive' } else { 'gone' })
                    if ($hs.runtime_updated_age -and $hs.runtime_updated_age -ne '-') {
                        $line += ' rt_last=' + $hs.runtime_updated_age
                    }
                    if (-not $recommendation.worker_alive -and [string]$lState -in @('in_progress', 'qa')) {
                        $stateColor = 'Red'
                    }
                }
                if ($recommendation.runtime_residue -and $recommendation.runtime_residue.has_residue -and [string]$lState -in @('assigned','waiting_qa')) {
                    $line += ' [RUNTIME-RESIDUE]'
                    $stateColor = 'Red'
                }
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
            if ($recommendation -and $recommendation.runtime_residue -and $recommendation.runtime_residue.has_residue -and [string]$lState -in @('assigned','waiting_qa')) {
                Write-Host ('    residue=' + $recommendation.runtime_residue.summary) -ForegroundColor DarkGray
            }
            if ($recommendation -and $recommendation.dispatch_mode -eq 'headless' -and $recommendation.headless_snapshot) {
                $hs = $recommendation.headless_snapshot
                if ($hs.run_dir) {
                    Write-Host ('    run_dir=' + $hs.run_dir) -ForegroundColor DarkGray
                }
                if ($hs.runtime_note) {
                    $runtimeNote = [string]$hs.runtime_note
                    if ($runtimeNote.Length -gt 120) { $runtimeNote = $runtimeNote.Substring(0, 120) + '...' }
                    Write-Host ('    note=' + $runtimeNote) -ForegroundColor DarkGray
                }
            }
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
        watcher_entries_removed = 0
    }

    # 1) Worker registry reconcile/health-check
    try { Reconcile-WorkerRegistryFromPanes | Out-Null } catch {}
    $regScript = Join-Path $scriptDir "worker-registry.ps1"
    if (Test-Path $regScript) {
        try { & $regScript -Action health-check *> $null } catch {}
    }
    $watcherCleanup = Cleanup-StalePaneApprovalWatchers
    $summary.watcher_entries_removed = $watcherCleanup.removed

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
        Write-Host '[FAIL] recover requires -RecoverAction (reap-stale / restart-task / restart-worker / reset-task / normalize-locks / baseline-clean / full-clean)' -ForegroundColor Red
        exit 1
    }

    $tlPaneId = $null
    if ($RecoverAction -eq "restart-worker") {
        $tlPaneId = Resolve-TeamLeadPaneId
        Assert-TeamLeadPaneId $tlPaneId 'recover'
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
                $clean = Cleanup-StalePaneApprovalWatchers -Verbose
                if ($clean.removed -gt 0) {
                    Write-Host ('[OK] cleaned stale pane-approval-watcher entries: removed=' + $clean.removed + ', killed=' + $clean.killed) -ForegroundColor Green
                }
            } catch {}
            Write-Host '[OK] reap-stale done' -ForegroundColor Green
        }

        "restart-task" {
            if (-not $TaskId) {
                Write-Host '[FAIL] restart-task requires -TaskId' -ForegroundColor Red
                exit 1
            }
            Assert-CanonicalTaskId $TaskId

            $workerMap = Get-WorkerMap
            $locks = Read-TaskLocks
            if ($locks.locks.PSObject.Properties.Name -notcontains $TaskId) {
                Write-Host ('[FAIL] Task ' + $TaskId + ' not in TASK-LOCKS.json') -ForegroundColor Red
                exit 1
            }

            $lock = $locks.locks.$TaskId
            $currentState = if ($lock.state) { [string]$lock.state } else { '' }
            if ($currentState -in @('completed', 'archiving')) {
                Write-Host ('[FAIL] restart-task does not support state=' + $currentState + ' for ' + $TaskId) -ForegroundColor Red
                exit 1
            }

            $assignedWorker = Get-AssignedWorkerFromLock -TaskId $TaskId -lock $lock -State $currentState -WorkerMap $workerMap
            $dispatchMode = Get-LockDispatchMode -lock $lock
            $headlessSnapshot = Read-HeadlessRunSnapshot -TaskId $TaskId -Lock $lock
            $phase = Resolve-PhaseFromWorkerName -WorkerName (Get-TaskLatestRouteWorker -lock $lock)
            if (-not $phase) {
                $phase = Resolve-PhaseFromWorkerName -WorkerName $assignedWorker
            }
            $targetState = Resolve-RecoveryTargetState -State $currentState -Phase $phase

            $killedPid = 0
            if ($dispatchMode -eq 'headless' -and $headlessSnapshot -and $headlessSnapshot.process_alive -and $headlessSnapshot.process_id -gt 0) {
                try {
                    Stop-Process -Id $headlessSnapshot.process_id -Force -ErrorAction Stop
                    $killedPid = [int]$headlessSnapshot.process_id
                    Write-Host ('[OK] Stopped headless process pid=' + $killedPid + ' for task ' + $TaskId) -ForegroundColor Green
                } catch {
                    Write-Host ('[WARN] Failed to stop headless process pid=' + [string]$headlessSnapshot.process_id + ': ' + $_.Exception.Message) -ForegroundColor Yellow
                }
            }

            if ($assignedWorker) {
                Stop-PaneApprovalWatcher -TaskId $TaskId -WorkerName $assignedWorker -Quiet | Out-Null
            }

            $now = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
            Update-TaskLocksData {
                param($latest)
                if ($latest.locks.PSObject.Properties.Name -notcontains $TaskId) {
                    throw ('Task missing during restart-task commit: ' + $TaskId)
                }
                $latestLock = $latest.locks.$TaskId
                $latestLock.state = $targetState
                $latestLock.updated_at = $now
                $latestLock.updated_by = 'teamlead-control/recover-restart-task'
                Set-NoteField -obj $latestLock -value ('Recovered to ' + $targetState + ' by team lead: restart-task')
                Clear-TaskRuntimeFields -lock $latestLock -ClearAssignedWorker -ClearDispatchMode
                Set-ObjectField -obj $latestLock -name 'last_recovery' -value @{
                    previous_state = $currentState
                    target_state = $targetState
                    recover_action = 'restart-task'
                    requested_at = $now
                    requested_by = 'teamlead-control/recover-restart-task'
                    dispatch_mode = $dispatchMode
                    killed_headless_pid = $killedPid
                }
                return $null
            } | Out-Null

            Update-LatestTaskAttempt -TaskId $TaskId -Phase $phase -Result 'requeued' -FinalState $targetState -EndedAt $now -RequeueReason 'restart_task' -UpdatedBy 'teamlead-control/recover-restart-task' | Out-Null

            Write-Host ('[OK] Task ' + $TaskId + ' recovered: ' + $currentState + ' -> ' + $targetState) -ForegroundColor Green
            if ($dispatchMode -eq 'headless') {
                if ($killedPid -gt 0) {
                    Write-Host ('     Cleared headless runtime and killed pid ' + $killedPid) -ForegroundColor Gray
                } else {
                    Write-Host '     Cleared headless runtime metadata' -ForegroundColor Gray
                }
            } else {
                Write-Host '     Cleared stale runtime metadata' -ForegroundColor Gray
            }
            if ($targetState -eq 'waiting_qa') {
                Write-Host ('     Next: powershell -File scripts/teamlead-control.ps1 -Action dispatch-qa -TaskId ' + $TaskId) -ForegroundColor White
            } else {
                Write-Host ('     Next: powershell -File scripts/teamlead-control.ps1 -Action dispatch -TaskId ' + $TaskId) -ForegroundColor White
            }
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
                $clean = Cleanup-StalePaneApprovalWatchers -Verbose
                if ($clean.removed -gt 0) {
                    Write-Host ('[OK] cleaned stale pane-approval-watcher entries: removed=' + $clean.removed + ', killed=' + $clean.killed) -ForegroundColor Green
                }
            } catch {}

            Write-Host '[INFO] full-clean step 3/3: status...' -ForegroundColor Yellow
            Invoke-Status
            Write-Host '[OK] full-clean done' -ForegroundColor Green
        }
    }
}

# ============================================================
# Action: show-approval
# ============================================================
function Invoke-ShowApproval {
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

    $summary = ''
    foreach ($candidate in @($req.summary, $req.reason, $req.prompt, $req.message, $req.body)) {
        if ($candidate) {
            $summary = [string]$candidate
            break
        }
    }
    $summary = $summary -replace '\s+', ' '
    if ($summary.Length -gt 240) {
        $summary = $summary.Substring(0, 240) + '...'
    }

    Write-Host ''
    Write-Host '==========================================' -ForegroundColor Green
    Write-Host '  Approval Request Detail' -ForegroundColor Green
    Write-Host '==========================================' -ForegroundColor Green
    Write-Host ('  id: ' + [string]$req.id) -ForegroundColor White
    Write-Host ('  status: ' + [string]$req.status) -ForegroundColor White
    if ($req.task_id) { Write-Host ('  task: ' + [string]$req.task_id) -ForegroundColor White }
    if ($req.worker) { Write-Host ('  worker: ' + [string]$req.worker) -ForegroundColor White }
    if ($req.worker_pane_id) { Write-Host ('  pane: ' + [string]$req.worker_pane_id) -ForegroundColor White }
    if ($req.prompt_type) { Write-Host ('  prompt_type: ' + [string]$req.prompt_type) -ForegroundColor White }
    if ($req.risk) { Write-Host ('  risk: ' + [string]$req.risk) -ForegroundColor White }
    if ($req.created_at) { Write-Host ('  created_at: ' + [string]$req.created_at) -ForegroundColor White }
    if ($req.expires_at) { Write-Host ('  expires_at: ' + [string]$req.expires_at) -ForegroundColor White }
    if ($summary) { Write-Host ('  summary: ' + $summary) -ForegroundColor White }
    Write-Host ''
    if ([string]$req.status -eq 'pending') {
        Write-Host 'Next:' -ForegroundColor Cyan
        Write-Host ('  approve  -> powershell -File scripts/teamlead-control.ps1 -Action approve-request -RequestId ' + [string]$req.id) -ForegroundColor White
        Write-Host ('  deny     -> powershell -File scripts/teamlead-control.ps1 -Action deny-request -RequestId ' + [string]$req.id) -ForegroundColor White
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
# Action: approve-local / approve-local-session / deny-local
# ============================================================
function Invoke-LocalApprovalDecision([string]$decision, [string]$approvalMode = "default") {
    if (-not $WorkerName) {
        Write-Host ('[FAIL] ' + $Action + ' requires -WorkerName') -ForegroundColor Red
        exit 1
    }

    $paneId = Resolve-WorkerPaneByName -workerName $WorkerName
    if (-not $paneId) {
        Write-Host ('[FAIL] Worker pane not found: ' + $WorkerName) -ForegroundColor Red
        exit 1
    }

    $resolvedPromptType = Resolve-LocalPromptType -paneId $paneId -explicitPromptType $PromptType
    if ($decision -eq 'approve' -and $approvalMode -eq 'session' -and $resolvedPromptType -ne 'menu_approval') {
        Write-Host ('[FAIL] approve-local-session only supports menu_approval. Resolved prompt type: ' + $resolvedPromptType) -ForegroundColor Red
        exit 1
    }

    $sent = Send-ApprovalDecisionToPane -paneId $paneId -decision $decision -promptType $resolvedPromptType -approvalMode $approvalMode
    if (-not $sent) {
        Write-Host ('[FAIL] Failed to send local approval decision to pane ' + $paneId + ' (worker=' + $WorkerName + ')') -ForegroundColor Red
        exit 1
    }

    $modeLabel = if ($decision -eq 'approve' -and $approvalMode -eq 'session') { 'approve-session' } elseif ($decision -eq 'approve') { 'approve' } else { 'deny' }
    Mark-LocalApprovalResolved -WorkerName $WorkerName -Decision $modeLabel -PromptType $resolvedPromptType -ResolvedBy ('teamlead-control/' + $Action)
    Write-Host ('[OK] Local approval ' + $modeLabel + ' sent to worker ' + $WorkerName + ' via pane ' + $paneId) -ForegroundColor Green
    Write-Host ('     prompt_type=' + $resolvedPromptType) -ForegroundColor Gray
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
    Assert-TeamLeadPaneId $tlPaneId 'archive'
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
        Ensure-PaneApprovalWatcher -TaskId $docTaskId -WorkerName "doc-updater" -WorkerPaneId $docPaneId -TeamLeadPaneId $tlPaneId -SkipTaskLockGuard
    } else {
        Write-Host '[WARN] doc-updater pane not returned, cannot auto-attach pane-approval-watcher.' -ForegroundColor Yellow
    }
    & $upsertArchiveJob -status "running" -docId $docTaskId -commitId "" -docStatus "pending" -commitStatus "pending" -note "Doc updater dispatched" -blockedReason ""

    # Trigger repo-committer（默认 push）
    try {
        if ($CommitMessage) {
            if ($NoPush.IsPresent) {
                $commitRaw = & $commitTriggerScript -TaskId $TaskId -TeamLeadPaneId $tlPaneId -Force -EmitJson -CommitMessage $CommitMessage
            } else {
                $commitRaw = & $commitTriggerScript -TaskId $TaskId -TeamLeadPaneId $tlPaneId -Force -EmitJson -Push -CommitMessage $CommitMessage
            }
        } elseif ($NoPush.IsPresent) {
            $commitRaw = & $commitTriggerScript -TaskId $TaskId -TeamLeadPaneId $tlPaneId -Force -EmitJson
        } else {
            $commitRaw = & $commitTriggerScript -TaskId $TaskId -TeamLeadPaneId $tlPaneId -Force -EmitJson -Push
        }
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
        Ensure-PaneApprovalWatcher -TaskId $commitTaskId -WorkerName $commitWorker -WorkerPaneId $commitPaneId -TeamLeadPaneId $tlPaneId -SkipTaskLockGuard
    } else {
        Write-Host '[WARN] repo-committer pane not returned, cannot auto-attach pane-approval-watcher.' -ForegroundColor Yellow
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
    "notify-ready" { Invoke-NotifyReady }
    "requeue"     { Invoke-Requeue }
    "recover"     { Invoke-Recover }
    "add-lock"    { Invoke-AddLock }
    "archive"     { Invoke-Archive }
    "show-approval" { Invoke-ShowApproval }
    "approve-request" { Invoke-ApprovalDecision -decision 'approve' }
    "deny-request"    { Invoke-ApprovalDecision -decision 'deny' }
    "approve-local"         { Invoke-LocalApprovalDecision -decision 'approve' -approvalMode 'default' }
    "approve-local-session" { Invoke-LocalApprovalDecision -decision 'approve' -approvalMode 'session' }
    "deny-local"            { Invoke-LocalApprovalDecision -decision 'deny' -approvalMode 'default' }
}
