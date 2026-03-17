#!/usr/bin/env pwsh
# [ROUTE] Message Monitor - Poll route inbox, update task locks, trigger doc-updater
# Usage: .\route-monitor.ps1 -TeamLeadPaneId <id> [-Continuous]

param(
    [Parameter(Mandatory = $false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID,

    [Parameter(Mandatory = $false)]
    [switch]$Continuous,

    [Parameter(Mandatory = $false)]
    [int]$PollIntervalSeconds = 2
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path $PSScriptRoot -Parent
$locksFile = Join-Path $scriptDir "01-tasks\TASK-LOCKS.json"
$inboxFile = Join-Path $scriptDir "mcp\route-server\data\route-inbox.json"
$docTriggerScript = Join-Path $scriptDir "scripts\trigger-doc-updater.ps1"
$commitTriggerScript = Join-Path $scriptDir "scripts\trigger-repo-committer.ps1"
$docSyncStateFile = Join-Path $scriptDir "config\api-doc-sync-state.json"
$archiveJobsFile = Join-Path $scriptDir "config\archive-jobs.json"
$taskAttemptHistoryFile = Join-Path $scriptDir "config\task-attempt-history.json"
$monitorStateFile = Join-Path $scriptDir "config\route-monitor-state.json"
$teamLeadAlertsFile = Join-Path $scriptDir "config\teamlead-alerts.jsonl"

$notifySentinelReadyPath = Join-Path $scriptDir "config\\notify-sentinel.ready.json"
$workerSamplesLogFile = Join-Path $scriptDir "config\worker-samples.log"
$processedRoutes = @{}
$processedRoutesFile = Join-Path $env:TEMP "moxton-ccb-processed-routes.json"
$activeSnapshotFile = Join-Path $env:TEMP "moxton-active-snapshot.json"
$activeTaskIds = @()
$taskLocksMutexName = "Global\MoxtonTaskLocksFileMutex"
$recentRouteNotifications = @{}
$recentSampleNotifications = @{}
$lastStaleSampleScanAt = Get-Date "1970-01-01T00:00:00Z"
$workerRegistryPath = Join-Path $scriptDir "config\worker-panels.json"
$autoDecisionStatePath = Join-Path $scriptDir "config\auto-decision-state.json"
$script:monitorStartedAt = Get-Date -Format "o"
$flag = $env:CCB_ENABLE_WEZTERM_NOTIFY
$script:enableWeztermNotify = $true
if ($flag) {
    $normalized = $flag.Trim().ToLowerInvariant()
    if ($normalized -in @("0","false","no","off")) {
        $script:enableWeztermNotify = $false
    }
}

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

function Write-MonitorState([string]$status, [string]$note = "") {
    $state = [ordered]@{
        status = if ([string]::IsNullOrWhiteSpace($status)) { "unknown" } else { $status }
        pid = [int]$PID
        teamlead_pane_id = if ($TeamLeadPaneId) { [string]$TeamLeadPaneId } else { "" }
        wezterm_notify_enabled = [bool]$script:enableWeztermNotify
        continuous = [bool]$Continuous
        poll_interval_seconds = [int]$PollIntervalSeconds
        started_at = $script:monitorStartedAt
        last_loop_at = (Get-Date -Format "o")
        script_path = $PSCommandPath
        note = if ($note) { [string]$note } else { "" }
    }
    Write-Utf8NoBomFile -path $monitorStateFile -content ($state | ConvertTo-Json -Depth 6)
}

function Read-AutoDecisionState {
    if (-not (Test-Path $autoDecisionStatePath)) {
        return @{ updated_at = (Get-Date -Format "o"); decisions = @{} }
    }
    try {
        $raw = Get-Content $autoDecisionStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $raw.decisions) {
            $raw | Add-Member -NotePropertyName decisions -NotePropertyValue @{} -Force
        }
        if (-not ($raw.decisions -is [System.Collections.IDictionary])) {
            $raw.decisions = Convert-ObjectToHashtable $raw.decisions
        }
        return $raw
    } catch {
        return @{ updated_at = (Get-Date -Format "o"); decisions = @{} }
    }
}

function Write-AutoDecisionState($state) {
    if (-not $state.decisions) { $state.decisions = @{} }
    $state.updated_at = Get-Date -Format "o"
    Write-Utf8NoBomFile -path $autoDecisionStatePath -content ($state | ConvertTo-Json -Depth 8)
}

function Mark-AutoDecisionApplied([string]$routeId, [string]$decision) {
    if (-not $routeId) { return }
    $state = Read-AutoDecisionState
    if (-not $state.decisions) { $state.decisions = @{} }
    $state.decisions[$routeId] = @{
        decision = $decision
        applied_at = (Get-Date -Format "o")
    }
    Write-AutoDecisionState $state
}

function Test-AutoDecisionApplied([string]$routeId) {
    if (-not $routeId) { return $false }
    $state = Read-AutoDecisionState
    if (-not $state.decisions) { return $false }
    return ($state.decisions.PSObject.Properties.Name -contains $routeId)
}

function Get-AutoDecisionNotifyKey([string]$TaskId, [string]$Worker, [string]$Decision) {
    $t = if ($TaskId) { $TaskId } else { "" }
    $w = if ($Worker) { $Worker } else { "" }
    $d = if ($Decision) { $Decision } else { "" }
    return ("notify:" + $d + ":" + $t + ":" + $w)
}

function Should-NotifyAutoDecision {
    param([string]$TaskId,[string]$Worker,[string]$Decision)
    $cooldown = Get-EnvIntOrDefault -name "AUTO_DECISION_NOTIFY_COOLDOWN_MINUTES" -defaultValue 10
    if ($cooldown -le 0) { return $true }
    $state = Read-AutoDecisionState
    if (-not $state.decisions) { $state.decisions = @{} }
    if (-not ($state.decisions -is [System.Collections.IDictionary])) { $state.decisions = Convert-ObjectToHashtable $state.decisions }
    $key = Get-AutoDecisionNotifyKey -TaskId $TaskId -Worker $Worker -Decision $Decision
    if (-not $state.decisions.ContainsKey($key)) { return $true }
    $last = $state.decisions[$key]
    if (-not $last -or -not $last.notified_at) { return $true }
    $parsed = $null
    try { $parsed = [DateTimeOffset]::Parse([string]$last.notified_at) } catch {}
    if (-not $parsed) { return $true }
    $age = ((Get-Date).ToUniversalTime() - $parsed.UtcDateTime).TotalMinutes
    return ($age -ge $cooldown)
}

function Mark-AutoDecisionNotified {
    param([string]$TaskId,[string]$Worker,[string]$Decision)
    $state = Read-AutoDecisionState
    if (-not $state.decisions) { $state.decisions = @{} }
    $key = Get-AutoDecisionNotifyKey -TaskId $TaskId -Worker $Worker -Decision $Decision
    $state.decisions[$key] = @{
        decision = $Decision
        task = $TaskId
        worker = $Worker
        notified_at = (Get-Date -Format "o")
    }
    Write-AutoDecisionState $state
}

function Get-WeztermPanes {
    try {
        $raw = wezterm cli list --format json 2>$null
        if (-not $raw) { return @() }
        return @($raw | ConvertFrom-Json)
    } catch {
        return @()
    }
}

function Get-WorkerPaneIdSet {
    $set = New-Object System.Collections.Generic.HashSet[string]
    if (-not (Test-Path $workerRegistryPath)) { return $set }
    try {
        $raw = Get-Content $workerRegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($raw -and $raw.workers) {
            foreach ($p in $raw.workers.PSObject.Properties) {
                $paneId = $null
                if ($p.Value -and $p.Value.pane_id) { $paneId = [string]$p.Value.pane_id }
                if ($paneId) { [void]$set.Add($paneId) }
            }
        }
    } catch {}
    return $set
}

function Resolve-TeamLeadPaneId([string]$preferredPaneId) {
    $panes = Get-WeztermPanes
    if (-not $panes -or $panes.Count -eq 0) { return $null }

    $workerPaneIds = Get-WorkerPaneIdSet
    if ($workerPaneIds.Count -gt 0) {
        $panes = @($panes | Where-Object { -not $workerPaneIds.Contains([string]$_.pane_id) })
    }
    if (-not $panes -or $panes.Count -eq 0) { return $null }

    if ($preferredPaneId) {
        $matched = $panes | Where-Object { ([string]$_.pane_id) -eq ([string]$preferredPaneId) } | Select-Object -First 1
        if ($matched) { return [string]$matched.pane_id }
    }
    if ($env:WEZTERM_PANE) {
        $matched = $panes | Where-Object { ([string]$_.pane_id) -eq ([string]$env:WEZTERM_PANE) } | Select-Object -First 1
        if ($matched) { return [string]$matched.pane_id }
    }
    $fallback = $panes | Where-Object { $_.title -like '*claude*' -or $_.title -like '* Claude*' } | Select-Object -First 1
    if ($fallback) { return [string]$fallback.pane_id }
    $ccbPane = $panes | Where-Object { $_.cwd -like '*\\moxton-ccb*' -or $_.cwd -like '*/moxton-ccb*' } | Select-Object -First 1
    if ($ccbPane) { return [string]$ccbPane.pane_id }
    if ($panes.Count -eq 1) { return [string]$panes[0].pane_id }
    return $null
}

function Notify-TeamLeadWake([string]$message) {
    if ([string]::IsNullOrWhiteSpace($message)) { return $false }
    if (-not (Should-NotifyTeamLeadWake)) { return }
    if (-not $script:enableWeztermNotify) { return $false }
    $targetPane = Resolve-TeamLeadPaneId -preferredPaneId $TeamLeadPaneId
    if (-not $targetPane) { return $false }
    try {
        wezterm cli send-text --pane-id $targetPane --no-paste $message | Out-Null
        Start-Sleep -Milliseconds 80
        wezterm cli send-text --pane-id $targetPane --no-paste "`r" | Out-Null
        return $true
    } catch {
        $targetPane = Resolve-TeamLeadPaneId -preferredPaneId ""
        if (-not $targetPane) { return $false }
        try {
            wezterm cli send-text --pane-id $targetPane --no-paste $message | Out-Null
            Start-Sleep -Milliseconds 80
            wezterm cli send-text --pane-id $targetPane --no-paste "`r" | Out-Null
            return $true
        } catch {
            return $false
        }
    }
}

function Read-NotifySentinelReady {
    if (-not (Test-Path $notifySentinelReadyPath)) { return $null }
    try { return (Get-Content $notifySentinelReadyPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Get-NotifySentinelAgeMinutes($ready) {
    if (-not $ready) { return $null }
    $at = $null
    try { if ($ready.at) { $at = [DateTimeOffset]::Parse([string]$ready.at) } } catch {}
    if (-not $at) { return $null }
    return ((Get-Date).ToUniversalTime() - $at.UtcDateTime).TotalMinutes
}

function Get-NotifySentinelWakeGraceMinutes {
    return Get-EnvIntOrDefault -name "CCB_NOTIFY_SENTINEL_WAKE_GRACE_MINUTES" -defaultValue 3
}

function Should-NotifyTeamLeadWake {
    $flag = $env:CCB_ROUTE_MONITOR_NOTIFY
    if ($flag) {
        $norm = $flag.Trim().ToLowerInvariant()
        if ($norm -in @("0","false","no","off")) { return $false }
        if ($norm -in @("1","true","yes","on")) { return $true }
    }

    $ready = Read-NotifySentinelReady
    if (-not $ready) { return $true }

    $source = if ($ready.source) { [string]$ready.source } else { "" }
    if ($source -ne "notify-sentinel") { return $true }

    $notifyState = if ($ready.notify) { ([string]$ready.notify).Trim().ToLowerInvariant() } else { "" }
    if ($notifyState -notin @("on", "1", "true", "yes")) { return $true }

    $age = Get-NotifySentinelAgeMinutes $ready
    if ($null -eq $age) { return $true }

    $grace = Get-NotifySentinelWakeGraceMinutes
    return ($age -gt $grace)
}

function Write-TeamLeadAlert {
    param(
        [string]$Kind,
        [string]$TaskId,
        [string]$Worker,
        [string]$Status,
        [string]$Action,
        [string]$RunId,
        [string]$LockState,
        [string]$Detail
    )

    $record = [ordered]@{
        at = (Get-Date -Format "o")
        kind = if ($Kind) { $Kind } else { "route" }
        task = if ($TaskId) { $TaskId } else { "" }
        worker = if ($Worker) { $Worker } else { "" }
        status = if ($Status) { $Status } else { "" }
        action = if ($Action) { $Action } else { "" }
        run_id = if ($RunId) { $RunId } else { "" }
        lock = if ($LockState) { $LockState } else { "" }
        detail = if ($Detail) { $Detail } else { "" }
    }
    Append-Utf8Line -path $teamLeadAlertsFile -line ($record | ConvertTo-Json -Compress -Depth 6)
}

function Get-RouteDetailPreview([string]$detail) {
    if ([string]::IsNullOrWhiteSpace($detail)) { return "-" }
    $flat = ($detail -replace "\r?\n", " ").Trim()
    if ($flat.Length -gt 140) {
        return $flat.Substring(0, 140) + "..."
    }
    return $flat
}

function Should-NotifyTeamLeadRouteEvent {
    param(
        [object]$Route,
        [string]$Action,
        [string]$LockState,
        [string]$Detail
    )

    if (-not $Route) { return $false }
    $status = if ($Route.status) { ([string]$Route.status).ToLower() } else { "" }
    $actionText = if ([string]::IsNullOrWhiteSpace($Action)) { "processed" } else { $Action.ToLower() }
    $lockText = if ([string]::IsNullOrWhiteSpace($LockState)) { "" } else { $LockState.ToLower() }

    # 正常 in_progress 心跳不直接唤醒 Team Lead，避免刷屏；状态变化通知交由 Agent Teams 或 Team Lead 主动查看。
    # 但如果是 ACK 上报（body 含 ack=1），允许通知一次。
    if ($actionText -eq "applied" -and $status -eq "in_progress" -and $lockText -eq "in_progress") {
        if ($Detail -and $Detail.IndexOf("ack=1", [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            # allow
        } else {
            return $false
        }
    }

    $preview = Get-RouteDetailPreview -detail $Detail
    $taskId = if ($Route.task) { [string]$Route.task } else { "-" }
    $worker = if ($Route.from) { [string]$Route.from } else { "-" }
    $key = ($taskId + "|" + $worker + "|" + $status + "|" + $actionText + "|" + $lockText + "|" + $preview)
    $now = Get-Date

    $expiredKeys = @()
    foreach ($existingKey in @($recentRouteNotifications.Keys)) {
        $lastAt = $recentRouteNotifications[$existingKey]
        if ($lastAt -is [datetime] -and (($now - $lastAt).TotalSeconds -gt 120)) {
            $expiredKeys += $existingKey
        }
    }
    foreach ($expired in $expiredKeys) {
        $recentRouteNotifications.Remove($expired) | Out-Null
    }

    if ($recentRouteNotifications.ContainsKey($key)) {
        $lastAt = $recentRouteNotifications[$key]
        if ($lastAt -is [datetime] -and (($now - $lastAt).TotalSeconds -lt 30)) {
            return $false
        }
    }

    $recentRouteNotifications[$key] = $now
    return $true
}

function Notify-TeamLeadRouteEvent {
    param(
        [object]$Route,
        [string]$Action,
        [string]$LockState,
        [string]$Detail
    )

    if (-not $Route) { return }
    if (-not (Should-NotifyTeamLeadRouteEvent -Route $Route -Action $Action -LockState $LockState -Detail $Detail)) { return }
    $taskId = if ($Route.task) { [string]$Route.task } else { "-" }
    $worker = if ($Route.from) { [string]$Route.from } else { "-" }
    $status = if ($Route.status) { [string]$Route.status } else { "-" }
    $runId = if ($Route.PSObject.Properties.Name -contains "run_id" -and $Route.run_id) { [string]$Route.run_id } else { "-" }
    $lockText = if ([string]::IsNullOrWhiteSpace($LockState)) { "-" } else { $LockState }
    $actionText = if ([string]::IsNullOrWhiteSpace($Action)) { "processed" } else { $Action }
    $preview = Get-RouteDetailPreview -detail $Detail
    Write-TeamLeadAlert -Kind "route" -TaskId $taskId -Worker $worker -Status $status -Action $actionText -RunId $runId -LockState $lockText -Detail $preview
    $message = "[ROUTE] task=$taskId status=$status from=$worker action=$actionText. next=status/check_routes"
    Notify-TeamLeadWake -message $message | Out-Null
}

function Get-EnvIntOrDefault([string]$name, [int]$defaultValue) {
    try {
        $raw = [string](Get-Item -Path ("Env:" + $name) -ErrorAction SilentlyContinue).Value
        if ([string]::IsNullOrWhiteSpace($raw)) { return $defaultValue }
        $val = 0
        if ([int]::TryParse($raw, [ref]$val)) { return $val }
    } catch {}
    return $defaultValue
}

function Get-HeartbeatStaleThresholdMinutes {
    return Get-EnvIntOrDefault -name "TEAMLEAD_HEARTBEAT_STALE_MINUTES" -defaultValue 3
}

function Try-ParseUtc([string]$value) {
    if (-not $value) { return $null }
    try {
        $dto = [DateTimeOffset]::Parse([string]$value)
        return $dto.UtcDateTime
    } catch {
        return $null
    }
}

function Get-AttemptHeartbeatUtc($attempt) {
    if (-not $attempt) { return $null }
    $last = $null
    if ($attempt.PSObject.Properties['last_heartbeat_at']) {
        $last = Try-ParseUtc ([string]$attempt.last_heartbeat_at)
    }
    if (-not $last) {
        $last = Try-ParseUtc ([string]$attempt.started_at)
    }
    return $last
}

function Get-AttemptHeartbeatAgeMinutes($attempt) {
    $last = Get-AttemptHeartbeatUtc $attempt
    if (-not $last) { return $null }
    $span = ((Get-Date).ToUniversalTime() - $last)
    return $span.TotalMinutes
}

function Get-WorkerPaneId([string]$workerName) {
    if (-not $workerName) { return $null }
    $registryScript = Join-Path $scriptDir "scripts\worker-registry.ps1"
    if (-not (Test-Path $registryScript)) { return $null }
    try {
        $pane = & $registryScript -Action get -WorkerName $workerName 2>$null
        if (-not $pane) { return $null }
        return ([string]$pane).Trim()
    } catch {
        return $null
    }
}

function Get-PaneTailAscii([string]$paneId, [int]$maxLines = 20, [int]$maxChars = 1200) {
    if (-not $paneId) { return "" }
    try {
        $text = wezterm cli get-text --pane-id $paneId 2>$null
    } catch {
        return ""
    }
    if (-not $text) { return "" }
    $lines = @($text -split "`n")
    if ($lines.Count -gt $maxLines) {
        $lines = $lines[-$maxLines..-1]
    }
    $joined = ($lines -join "`n")
    $clean = ($joined -replace '[^\x09\x0A\x0D\x20-\x7E]', '')
    if ($clean.Length -gt $maxChars) {
        $clean = $clean.Substring($clean.Length - $maxChars)
    }
    return $clean.Trim()
}

function Should-NotifySample([string]$taskId, [string]$worker, [string]$reason) {
    if (-not $taskId -or -not $worker -or -not $reason) { return $false }
    $key = ($taskId + "|" + $worker + "|" + $reason)
    $now = Get-Date
    if ($recentSampleNotifications.ContainsKey($key)) {
        $lastAt = $recentSampleNotifications[$key]
        if ($lastAt -is [datetime] -and (($now - $lastAt).TotalSeconds -lt 120)) {
            return $false
        }
    }
    $recentSampleNotifications[$key] = $now
    return $true
}

function Notify-TeamLeadSample {
    param(
        [string]$TaskId,
        [string]$Worker,
        [string]$Reason
    )
    if (-not (Should-NotifySample -taskId $TaskId -worker $Worker -reason $Reason)) { return }
    $paneId = Get-WorkerPaneId -workerName $Worker
    $tail = if ($paneId) { Get-PaneTailAscii -paneId $paneId } else { "" }
    $sample = [ordered]@{
        at = (Get-Date -Format "o")
        task = if ($TaskId) { $TaskId } else { "" }
        worker = if ($Worker) { $Worker } else { "" }
        reason = if ($Reason) { $Reason } else { "" }
        pane = if ($paneId) { $paneId } else { "" }
        tail = if ($tail) { $tail } else { "" }
    }
    Append-Utf8Line -path $workerSamplesLogFile -line ($sample | ConvertTo-Json -Compress -Depth 6)
}

function Invoke-TeamLeadControl {
    param(
        [string]$Arguments
    )
    if (-not $Arguments) { return $false }
    $scriptPath = Join-Path $scriptDir "scripts\teamlead-control.ps1"
    if (-not (Test-Path $scriptPath)) { return $false }
    $pane = Resolve-TeamLeadPaneId -preferredPaneId $TeamLeadPaneId
    $envPrefix = if ($pane) { "`$env:TEAM_LEAD_PANE_ID = '$pane'; " } else { "" }
    $cmd = $envPrefix + "& '" + $scriptPath + "' " + $Arguments
    try {
        $proc = Start-Process -FilePath "powershell" -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-Command",$cmd) -NoNewWindow -PassThru
        $proc.WaitForExit() | Out-Null
        return ($proc.ExitCode -eq 0)
    } catch {
        return $false
    }
}

function Get-BlockedDecision([string]$body) {
    if (-not $body) { return "unknown" }
    $text = $body.ToLowerInvariant()
    if ($text -match "3033|health" -or $text -match "connection refused|econnrefused|port .* closed|service unavailable|server not started") {
        return "service_down"
    }
    if ($text -match "pre-existing|dirty state|working tree|uncommitted|git status|modified files|already modified|baseline") {
        return "dirty_state"
    }
    if ($text -match "credential|credentials|token|login|password|no credentials|sec_e_no_credentials|auth") {
        return "missing_credentials"
    }
    return "unknown"
}

function Auto-ResolveBlockedRoute {
    param(
        [object]$Route,
        [string]$RouteId
    )
    $disable = $env:CCB_DISABLE_AUTO_DECISION
    if ($disable) {
        $norm = $disable.Trim().ToLowerInvariant()
        if ($norm -in @("1","true","yes","on")) { return }
    }
    if (-not $Route) { return }
    $status = if ($Route.status) { ([string]$Route.status).ToLower() } else { "" }
    if ($status -ne "blocked" -and $status -ne "fail") { return }
    if (Test-AutoDecisionApplied -routeId $RouteId) { return }

    $taskId = if ($Route.task) { [string]$Route.task } else { "" }
    $worker = if ($Route.from) { [string]$Route.from } else { "" }
    $body = if ($Route.body) { [string]$Route.body } else { "" }
    $decision = Get-BlockedDecision -body $body

    switch ($decision) {
        "service_down" {
            if (-not (Should-NotifyAutoDecision -TaskId $taskId -Worker $worker -Decision $decision)) {
                return
            }
            Mark-AutoDecisionNotified -TaskId $taskId -Worker $worker -Decision $decision
            Write-TeamLeadAlert -Kind "auto-decision" -TaskId $taskId -Worker $worker -Status $status -Action $decision -RunId "" -LockState "" -Detail "decision=service_down; action=notify_only; next=restart service then requeue+dispatch-qa"
            Mark-AutoDecisionApplied -routeId $RouteId -decision $decision
            return
        }
        "dirty_state" {
            # auto baseline-clean + requeue + dispatch (dev or qa)
            $phase = if ($worker -match "-qa(?:-\\d+)?$") { "qa" } else { "dev" }
            if (-not (Should-NotifyAutoDecision -TaskId $taskId -Worker $worker -Decision $decision)) {
                return
            }
            Mark-AutoDecisionNotified -TaskId $taskId -Worker $worker -Decision $decision
            Write-TeamLeadAlert -Kind "auto-decision" -TaskId $taskId -Worker $worker -Status $status -Action $decision -RunId "" -LockState "" -Detail ("decision=dirty_state; action=baseline-clean + requeue + dispatch-" + $phase)
            Invoke-TeamLeadControl -Arguments "-Action recover -RecoverAction baseline-clean" | Out-Null
            if ($phase -eq "qa") {
                Invoke-TeamLeadControl -Arguments ("-Action requeue -TaskId " + $taskId + " -TargetState waiting_qa -RequeueReason ""auto_dirty_state_clean""") | Out-Null
                Invoke-TeamLeadControl -Arguments ("-Action dispatch-qa -TaskId " + $taskId) | Out-Null
            } else {
                Invoke-TeamLeadControl -Arguments ("-Action requeue -TaskId " + $taskId + " -TargetState assigned -RequeueReason ""auto_dirty_state_clean""") | Out-Null
                Invoke-TeamLeadControl -Arguments ("-Action dispatch -TaskId " + $taskId) | Out-Null
            }
            Mark-AutoDecisionApplied -routeId $RouteId -decision $decision
            return
        }
        "missing_credentials" {
            if (-not (Should-NotifyAutoDecision -TaskId $taskId -Worker $worker -Decision $decision)) {
                return
            }
            Mark-AutoDecisionNotified -TaskId $taskId -Worker $worker -Decision $decision
            Write-TeamLeadAlert -Kind "auto-decision" -TaskId $taskId -Worker $worker -Status $status -Action $decision -RunId "" -LockState "" -Detail "decision=missing_credentials; action=manual; next=provide credentials or run push in authenticated env"
            Mark-AutoDecisionApplied -routeId $RouteId -decision $decision
            return
        }
        default {
            # unknown: leave for Team Lead
            return
        }
    }
}

function Maybe-SampleOnRoute {
    param(
        [object]$Route
    )
    if (-not $Route) { return }
    $status = if ($Route.status) { ([string]$Route.status).ToLower() } else { "" }
    if ($status -in @("blocked", "fail")) {
        $taskId = if ($Route.task) { [string]$Route.task } else { "" }
        $worker = if ($Route.from) { [string]$Route.from } else { "" }
        Notify-TeamLeadSample -TaskId $taskId -Worker $worker -Reason $status
    }
}

function Check-StaleHeartbeatsAndSample {
    $threshold = Get-HeartbeatStaleThresholdMinutes
    if ($threshold -le 0) { return }
    $history = Read-TaskAttemptHistory
    $attempts = @(Get-TaskAttemptList $history)
    if ($attempts.Count -eq 0) { return }

    $latestByKey = @{}
    foreach ($attempt in $attempts) {
        if (-not $attempt) { continue }
        if (-not $attempt.task_id -or -not $attempt.phase) { continue }
        if ($attempt.result -ne "running") { continue }
        $last = Get-AttemptHeartbeatUtc $attempt
        if (-not $last) { continue }
        $key = ([string]$attempt.task_id + "|" + [string]$attempt.phase)
        if (-not $latestByKey.ContainsKey($key)) {
            $latestByKey[$key] = @{ attempt = $attempt; last = $last }
        } else {
            if ($last -gt $latestByKey[$key].last) {
                $latestByKey[$key] = @{ attempt = $attempt; last = $last }
            }
        }
    }

    foreach ($entry in $latestByKey.Values) {
        $attempt = $entry.attempt
        $age = Get-AttemptHeartbeatAgeMinutes $attempt
        if ($null -eq $age) { continue }
        if ($age -lt $threshold) { continue }
        $taskId = [string]$attempt.task_id
        $worker = [string]$attempt.worker
        Notify-TeamLeadSample -TaskId $taskId -Worker $worker -Reason "stale_heartbeat"
    }
}

function Read-Json([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    try {
        return (Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Read-TaskLocks {
    if (-not (Test-Path $locksFile)) {
        return @{ version = "1.0"; rev = 0; updated_at = (Get-Date -Format "o"); locks = @{} }
    }
    $raw = Get-Content $locksFile -Raw -Encoding UTF8
    $parsed = $raw | ConvertFrom-Json
    if (-not $parsed.PSObject.Properties['rev']) {
        $parsed | Add-Member -NotePropertyName rev -NotePropertyValue 0 -Force
    }
    if (-not $parsed.PSObject.Properties['version']) {
        $parsed | Add-Member -NotePropertyName version -NotePropertyValue "1.0" -Force
    }
    if (-not $parsed.PSObject.Properties['locks']) {
        $parsed | Add-Member -NotePropertyName locks -NotePropertyValue @{} -Force
    }
    return $parsed
}

function Write-TaskLocks($data) {
    if (-not $data.version) { $data.version = "1.0" }
    if (-not $data.PSObject.Properties['rev']) {
        $data | Add-Member -NotePropertyName rev -NotePropertyValue 0 -Force
    }
    if (-not $data.PSObject.Properties['locks']) {
        $data | Add-Member -NotePropertyName locks -NotePropertyValue @{} -Force
    }
    $data.rev = [int]$data.rev + 1
    $data.updated_at = Get-Date -Format "o"
    Write-Utf8NoBomFile -path $locksFile -content ($data | ConvertTo-Json -Depth 12)
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

function Convert-ObjectToHashtable($obj) {
    $hash = @{}
    if ($null -eq $obj) { return $hash }
    foreach ($p in $obj.PSObject.Properties) {
        $hash[$p.Name] = $p.Value
    }
    return $hash
}

function Set-ObjectField($obj, [string]$name, $value) {
    if (-not $obj -or -not $name) { return }
    if (-not $obj.PSObject.Properties[$name]) {
        $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
    } else {
        $obj.$name = $value
    }
}

function Read-TaskAttemptHistory {
    $default = @{
        version = "1.0"
        updated_at = (Get-Date -Format "o")
        attempts = @()
    }
    if (-not (Test-Path $taskAttemptHistoryFile)) { return $default }
    try {
        $raw = Get-Content $taskAttemptHistoryFile -Raw -Encoding UTF8 | ConvertFrom-Json
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

function Write-TaskAttemptHistory($state) {
    if (-not $state.version) { $state.version = "1.0" }
    if (-not $state.attempts) { $state.attempts = @() }
    $state.updated_at = Get-Date -Format "o"
    Write-Utf8NoBomFile -path $taskAttemptHistoryFile -content ($state | ConvertTo-Json -Depth 12)
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

function Resolve-TaskLockStateFromRoute([string]$Status, [string]$WorkerName) {
    $safeStatus = if ($null -eq $Status) { "" } else { [string]$Status }
    switch ($safeStatus.ToLower()) {
        "success" {
            if ($WorkerName -match "-qa(?:-\d+)?$") { return "qa_passed" }
            if ($WorkerName -match "-dev(?:-\d+)?$") { return "waiting_qa" }
            return "waiting_qa"
        }
        "fail" { return "blocked" }
        "blocked" { return "blocked" }
        "in_progress" { return "in_progress" }
        "qa" { return "qa" }
        "waiting_qa" { return "waiting_qa" }
        default { return $Status }
    }
}

function Get-CurrentTaskLock([string]$TaskId) {
    $locks = Read-TaskLocks
    if (-not $locks -or -not $locks.locks) { return $null }
    if ($locks.locks.PSObject.Properties.Name -notcontains $TaskId) { return $null }
    return $locks.locks.$TaskId
}

function Should-ApplyPrimaryTaskRoute {
    param(
        [string]$TaskId,
        [string]$WorkerName,
        [string]$RouteRunId
    )

    if (-not $TaskId -or $TaskId -notmatch '^(BACKEND|SHOP-FE|ADMIN-FE)-\d+$') {
        return @{ apply = $true; reason = "" }
    }

    if ($WorkerName -notmatch '-(dev|qa)(?:-\d+)?$') {
        return @{ apply = $true; reason = "" }
    }

    $lock = Get-CurrentTaskLock -TaskId $TaskId
    if (-not $lock -or -not $lock.state) {
        return @{ apply = $true; reason = "" }
    }

    $lockRunId = ""
    if ($lock.PSObject.Properties.Name -contains "run_id" -and $lock.run_id) {
        $lockRunId = [string]$lock.run_id
    }
    $state = ([string]$lock.state).ToLower()
    if ($lockRunId) {
        if ([string]::IsNullOrWhiteSpace($RouteRunId)) {
            return @{
                apply = $false
                reason = ("task_state=" + $state + "; lock_run_id=" + $lockRunId + "; route_run_id_missing")
            }
        }
        if ([string]$RouteRunId -ne $lockRunId) {
            return @{
                apply = $false
                reason = ("task_state=" + $state + "; lock_run_id=" + $lockRunId + "; route_run_id=" + [string]$RouteRunId + "; stale_run_id")
            }
        }
    }

    if ($state -in @("in_progress", "qa", "blocked")) {
        return @{ apply = $true; reason = "" }
    }

    return @{
        apply = $false
        reason = ("task_state=" + $state + "; stale_or_unassigned_worker_route")
    }
}

function Update-TaskAttemptHistoryFromRoute {
    param(
        [string]$TaskId,
        [string]$Status,
        [string]$WorkerName,
        [string]$ResolvedLockState,
        [string]$RunId
    )

    $phase = Resolve-PhaseFromWorkerName -WorkerName $WorkerName
    if (-not $phase) { return }
    if (-not $TaskId) { return }

    $history = Read-TaskAttemptHistory
    $attempts = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-TaskAttemptList $history)) {
        $attempts.Add($item) | Out-Null
    }

    $latest = $null
    if (-not [string]::IsNullOrWhiteSpace($RunId)) {
        for ($i = $attempts.Count - 1; $i -ge 0; $i--) {
            $attempt = $attempts[$i]
            if (-not $attempt) { continue }
            if ([string]$attempt.task_id -ne $TaskId) { continue }
            if ([string]$attempt.phase -ne $phase) { continue }
            if ([string]$attempt.run_id -ne [string]$RunId) { continue }
            $latest = $attempt
            break
        }
    }
    if (-not $latest) {
        for ($i = $attempts.Count - 1; $i -ge 0; $i--) {
            $attempt = $attempts[$i]
            if (-not $attempt) { continue }
            if ([string]$attempt.task_id -ne $TaskId) { continue }
            if ([string]$attempt.phase -ne $phase) { continue }
            if (-not [string]::IsNullOrWhiteSpace($RunId) -and -not [string]::IsNullOrWhiteSpace([string]$attempt.run_id) -and [string]$attempt.run_id -ne [string]$RunId) {
                continue
            }
            $latest = $attempt
            break
        }
    }

    $now = Get-Date -Format "o"
    if (-not $latest) {
        $latest = [pscustomobject]@{
            attempt_id = (New-TaskAttemptId -TaskId $TaskId -Phase $phase)
            task_id = $TaskId
            phase = $phase
            worker = $WorkerName
            engine = ""
            dispatch_action = "route-monitor/reconstructed"
            run_id = $RunId
            started_at = $now
            last_heartbeat_at = ""
            ended_at = ""
            result = "running"
            final_state = ""
            requeue_reason = ""
            updated_by = "route-monitor/reconstructed"
        }
        $attempts.Add($latest) | Out-Null
    }

    $statusLower = if ($Status) { ([string]$Status).ToLower() } else { "" }
    if (-not $latest.worker) { $latest.worker = $WorkerName }
    if ($RunId -and ((-not $latest.PSObject.Properties['run_id']) -or [string]::IsNullOrWhiteSpace([string]$latest.run_id))) {
        Set-ObjectField -obj $latest -name "run_id" -value $RunId
    }

    switch ($statusLower) {
        "success" {
            Set-ObjectField -obj $latest -name "result" -value "success"
            Set-ObjectField -obj $latest -name "final_state" -value $ResolvedLockState
            Set-ObjectField -obj $latest -name "last_heartbeat_at" -value $now
            Set-ObjectField -obj $latest -name "ended_at" -value $now
            Set-ObjectField -obj $latest -name "updated_by" -value "route-monitor/success"
        }
        "blocked" {
            Set-ObjectField -obj $latest -name "result" -value "blocked"
            Set-ObjectField -obj $latest -name "final_state" -value $ResolvedLockState
            Set-ObjectField -obj $latest -name "last_heartbeat_at" -value $now
            Set-ObjectField -obj $latest -name "ended_at" -value $now
            Set-ObjectField -obj $latest -name "updated_by" -value "route-monitor/blocked"
        }
        "fail" {
            Set-ObjectField -obj $latest -name "result" -value "blocked"
            Set-ObjectField -obj $latest -name "final_state" -value $ResolvedLockState
            Set-ObjectField -obj $latest -name "last_heartbeat_at" -value $now
            Set-ObjectField -obj $latest -name "ended_at" -value $now
            Set-ObjectField -obj $latest -name "updated_by" -value "route-monitor/fail"
        }
        "in_progress" {
            Set-ObjectField -obj $latest -name "result" -value "running"
            Set-ObjectField -obj $latest -name "final_state" -value $ResolvedLockState
            Set-ObjectField -obj $latest -name "last_heartbeat_at" -value $now
            Set-ObjectField -obj $latest -name "updated_by" -value "route-monitor/in_progress"
        }
        "qa" {
            Set-ObjectField -obj $latest -name "result" -value "running"
            Set-ObjectField -obj $latest -name "final_state" -value $ResolvedLockState
            Set-ObjectField -obj $latest -name "last_heartbeat_at" -value $now
            Set-ObjectField -obj $latest -name "updated_by" -value "route-monitor/qa"
        }
        "waiting_qa" {
            Set-ObjectField -obj $latest -name "result" -value "running"
            Set-ObjectField -obj $latest -name "final_state" -value $ResolvedLockState
            Set-ObjectField -obj $latest -name "last_heartbeat_at" -value $now
            Set-ObjectField -obj $latest -name "updated_by" -value "route-monitor/waiting_qa"
        }
        default {
            return
        }
    }
    $history.attempts = @($attempts.ToArray())
    Write-TaskAttemptHistory $history
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

function Try-RecoverArchiveCommitDispatch {
    param(
        $Job,
        [string]$TaskId
    )

    if (-not $TaskId) {
        return @{ kind = "invalid"; message = "missing_task_id" }
    }
    if (-not (Test-Path $commitTriggerScript)) {
        return @{ kind = "invalid"; message = "trigger_repo_committer_script_missing" }
    }

    $pushRequired = $true
    if ($Job -and $Job.PSObject.Properties.Name -contains "push_required") {
        $pushRequired = Convert-ToBoolean -value $Job.push_required -default $true
    }

    $args = @("-TaskId", $TaskId, "-Force", "-EmitJson")
    if ($TeamLeadPaneId) {
        $args += @("-TeamLeadPaneId", $TeamLeadPaneId)
    }
    if ($pushRequired) {
        $args += @("-Push")
    }

    $raw = & $commitTriggerScript @args 2>&1
    $exitCode = $LASTEXITCODE
    $resp = Convert-CommandOutputToJson -output $raw
    if (-not $resp) {
        return @{
            kind = "invalid_response"
            message = "trigger_repo_committer_no_json"
            exit_code = $exitCode
        }
    }

    $status = if ($resp.status) { [string]$resp.status } else { "" }
    switch ($status) {
        "dispatched" {
            return @{
                kind = "ok"
                message = "repo_committer_dispatched"
                commit_task_id = if ($resp.commitTaskId) { [string]$resp.commitTaskId } else { "" }
                worker = if ($resp.worker) { [string]$resp.worker } else { "repo-committer" }
                pane_id = if ($resp.paneId) { [string]$resp.paneId } else { "" }
            }
        }
        "already_dispatched" {
            return @{
                kind = "ok"
                message = "repo_committer_already_dispatched"
                commit_task_id = if ($resp.commitTaskId) { [string]$resp.commitTaskId } else { "" }
                worker = if ($resp.worker) { [string]$resp.worker } else { "repo-committer" }
                pane_id = if ($resp.paneId) { [string]$resp.paneId } else { "" }
            }
        }
        "queued_pending_worker" {
            return @{
                kind = "queued"
                message = if ($resp.message) { [string]$resp.message } else { "committer_worker_unavailable" }
            }
        }
        default {
            return @{
                kind = "failed"
                message = if ($resp.message) { [string]$resp.message } else { ("status=" + $status + ", exit=" + $exitCode) }
                exit_code = $exitCode
            }
        }
    }
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

function Write-ArchiveJobs($state) {
    if (-not $state.version) { $state.version = "1.0" }
    $state.jobs = Convert-ToArchiveJobMap $state.jobs
    $state.updated_at = Get-Date -Format "o"
    Write-Utf8NoBomFile -path $archiveJobsFile -content ($state | ConvertTo-Json -Depth 12)
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

function Mark-BackendDocSyncPending([string]$BackendTaskId, [string]$QaWorker) {
    if (-not $BackendTaskId) { return }
    $state = Read-DocSyncState
    if (-not ($state.backend -is [System.Collections.IDictionary])) { $state.backend = Convert-ObjectToHashtable $state.backend }
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
        if (-not ($state.backend -is [System.Collections.IDictionary])) { $state.backend = Convert-ObjectToHashtable $state.backend }
        if (-not $state.backend.ContainsKey($backendTask)) {
            $state.backend[$backendTask] = @{}
        }
        $entry = $state.backend[$backendTask]
        if (-not ($entry -is [System.Collections.IDictionary])) {
            $entry = Convert-ObjectToHashtable $entry
        }
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

function Convert-ToSingleLineText([string]$value, [int]$maxLength = 280) {
    if ([string]::IsNullOrWhiteSpace($value)) { return "" }
    $normalized = (($value -replace '\r?\n', ' ') -replace '\s+', ' ').Trim()
    if ($normalized.Length -le $maxLength) { return $normalized }
    return $normalized.Substring(0, $maxLength).TrimEnd() + "..."
}

function Resolve-TaskMarkdownPath([string]$TaskId) {
    if ([string]::IsNullOrWhiteSpace($TaskId)) { return $null }

    $roots = @(
        (Join-Path $scriptDir "01-tasks\active"),
        (Join-Path $scriptDir "01-tasks\completed")
    )

    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $matches = @(Get-ChildItem -Path $root -Recurse -File -Filter "$TaskId*.md" -ErrorAction SilentlyContinue | Sort-Object FullName)
        if ($matches.Count -eq 1) {
            return $matches[0].FullName
        }
        if ($matches.Count -gt 1) {
            $preferred = @($matches | Where-Object { $_.BaseName -eq $TaskId -or $_.BaseName -like ($TaskId + "-*") })
            if ($preferred.Count -ge 1) {
                return $preferred[0].FullName
            }
        }
    }

    return $null
}

function Get-TaskQALevel([string]$TaskId) {
    $path = Resolve-TaskMarkdownPath -TaskId $TaskId
    if (-not $path) { return "full" }
    try {
        $content = Get-Content -Path $path -Raw -Encoding UTF8
    } catch {
        return "full"
    }
    if (-not $content) { return "full" }
    $m = [regex]::Match($content, '^\s*QA_LEVEL\s*:\s*([A-Za-z]+)\s*$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $m.Success) { return "full" }
    $level = $m.Groups[1].Value.ToLowerInvariant()
    if ($level -in @("full", "smoke", "skip")) { return $level }
    return "full"
}

function Get-QaPayload([string]$Body) {
    if ([string]::IsNullOrWhiteSpace($Body)) { return $null }
    try {
        return ($Body | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        return $null
    }
}

function Build-QaSummaryMarkdown {
    param(
        [string]$TaskId,
        [string]$WorkerName,
        [string]$Status,
        [string]$Body,
        [string]$Timestamp
    )

    $payload = Get-QaPayload -Body $Body
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("## QA 摘要（自动回写）") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add(('- 最后更新: `{0}`' -f $Timestamp)) | Out-Null
    $lines.Add(('- QA Worker: `{0}`' -f $WorkerName)) | Out-Null
    $lines.Add(('- 路由状态: `{0}`' -f $Status)) | Out-Null

    if ($payload) {
        $verdict = [string](Get-PropValue $payload "verdict")
        $summary = Convert-ToSingleLineText -value ([string](Get-PropValue $payload "summary")) -maxLength 320
        if (-not [string]::IsNullOrWhiteSpace($verdict)) {
            $lines.Add(('- 验收结论: `{0}`' -f $verdict.Trim().ToUpper())) | Out-Null
        }
        if (-not [string]::IsNullOrWhiteSpace($summary)) {
            $lines.Add("- 结论摘要: " + $summary) | Out-Null
        }

        $checks = Get-PropValue $payload "checks"
        if ($checks) {
            $lines.Add("- 证据索引:") | Out-Null
            foreach ($prop in @($checks.PSObject.Properties | Sort-Object Name)) {
                $checkName = [string]$prop.Name
                $node = $prop.Value
                $passValue = if (Convert-ToBoolean -value (Get-PropValue $node "pass") -default $false) { "PASS" } else { "FAIL" }
                $evidence = Convert-ToStringArray (Get-PropValue $node "evidence")
                if ($evidence.Count -gt 0) {
                    $formattedEvidence = @($evidence | ForEach-Object { ('`{0}`' -f $_) }) -join ", "
                    $lines.Add(('  - `{0}`: `{1}` -> {2}' -f $checkName, $passValue, $formattedEvidence)) | Out-Null
                } else {
                    $lines.Add(('  - `{0}`: `{1}`' -f $checkName, $passValue)) | Out-Null
                }
            }
        }

        $commands = Convert-ToStringArray (Get-PropValue $payload "commands")
        if ($commands.Count -gt 0) {
            $lines.Add("- 验证命令:") | Out-Null
            foreach ($cmd in $commands) {
                $lines.Add(('  - `{0}`' -f $cmd)) | Out-Null
            }
        }
    } else {
        $summaryText = Convert-ToSingleLineText -value $Body -maxLength 360
        if (-not [string]::IsNullOrWhiteSpace($summaryText)) {
            $lines.Add("- 回传摘要: " + $summaryText) | Out-Null
        } else {
            $lines.Add("- 回传摘要: （空）") | Out-Null
        }
    }

    $lines.Add('- 原始证据仍以 `05-verification/` 中的文件为准。') | Out-Null
    return (($lines -join "`r`n").TrimEnd() + "`r`n")
}

function Write-QaSummaryToTaskFile {
    param(
        [string]$TaskId,
        [string]$WorkerName,
        [string]$Status,
        [string]$Body,
        [string]$Timestamp
    )

    if ($WorkerName -notmatch "-qa(?:-\d+)?$") { return }
    if ($Status -notin @("success", "blocked", "fail")) { return }

    $taskPath = Resolve-TaskMarkdownPath -TaskId $TaskId
    if (-not $taskPath) {
        Write-Host ("  [WARN] QA summary write-back skipped, task file not found: " + $TaskId) -ForegroundColor Yellow
        return
    }

    $raw = Get-Content -Path $taskPath -Raw -Encoding UTF8
    $beginMarker = "<!-- AUTO-QA-SUMMARY:BEGIN -->"
    $endMarker = "<!-- AUTO-QA-SUMMARY:END -->"
    $summaryBody = Build-QaSummaryMarkdown -TaskId $TaskId -WorkerName $WorkerName -Status $Status -Body $Body -Timestamp $Timestamp
    $replacement = $beginMarker + "`r`n" + $summaryBody.TrimEnd() + "`r`n" + $endMarker + "`r`n"

    if ($raw -match [regex]::Escape($beginMarker) -and $raw -match [regex]::Escape($endMarker)) {
        $pattern = "(?s)" + [regex]::Escape($beginMarker) + ".*?" + [regex]::Escape($endMarker) + "\r?\n?"
        $updated = [regex]::Replace($raw, $pattern, $replacement, 1)
    } else {
        $trimmed = $raw.TrimEnd()
        $updated = $trimmed + "`r`n`r`n" + $replacement
    }

    if ($updated -ne $raw) {
        Write-Utf8NoBomFile -path $taskPath -content $updated
        Write-Host ("  QA summary written back: " + $TaskId + " -> " + $taskPath) -ForegroundColor Cyan
    }
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
        $isFrontendQa = ($WorkerName -match "^(shop-fe|admin-fe)-qa(?:-\d+)?$")
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

    if ($statusLower -ne "success" -or $fromText -notmatch "-qa(?:-\d+)?$") {
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
        [string]$Body,
        [string]$RouteRunId
    )

    $lockState = Resolve-TaskLockStateFromRoute -Status $Status -WorkerName $WorkerName
    $statusLower = if ($Status) { ([string]$Status).ToLower() } else { "" }
    $qaLevel = Get-TaskQALevel -TaskId $TaskId
    $isDevSuccess = ($statusLower -eq "success" -and $WorkerName -match "-dev(?:-\\d+)?$")
    if ($lockState -eq "waiting_qa" -and $isDevSuccess -and $qaLevel -eq "skip") {
        $lockState = "qa_passed"
    }
    $safeBody = if ($null -eq $Body) { "" } else { [string]$Body }
    $bodyPreview = if ($safeBody.Length -gt 100) { $safeBody.Substring(0, 100) + "..." } else { $safeBody }
    $updateResult = Invoke-WithTaskLocksMutex {
        $locks = Read-TaskLocks
        if (-not $locks -or -not $locks.locks) {
            return @{ applied = $false; reason = "locks_missing"; state = "" }
        }
        if ($locks.locks.PSObject.Properties.Name -notcontains $TaskId) {
            return @{ applied = $false; reason = "task_lock_missing"; state = "" }
        }

        $lock = $locks.locks.$TaskId
        $isPrimaryTask = ($TaskId -match '^(BACKEND|SHOP-FE|ADMIN-FE)-\d+$' -and $WorkerName -match '-(dev|qa)(?:-\d+)?$')
        $currentState = if ($lock.state) { ([string]$lock.state).ToLower() } else { "" }
        $currentRunId = ""
        if ($lock.PSObject.Properties.Name -contains "run_id" -and $lock.run_id) {
            $currentRunId = [string]$lock.run_id
        }

        if ($isPrimaryTask) {
            if ($currentRunId) {
                if ([string]::IsNullOrWhiteSpace($RouteRunId)) {
                    return @{
                        applied = $false
                        reason = ("task_state=" + $currentState + "; lock_run_id=" + $currentRunId + "; route_run_id_missing")
                        state = ""
                    }
                }
                if ([string]$RouteRunId -ne $currentRunId) {
                    return @{
                        applied = $false
                        reason = ("task_state=" + $currentState + "; lock_run_id=" + $currentRunId + "; route_run_id=" + [string]$RouteRunId + "; stale_run_id")
                        state = ""
                    }
                }
            }
            if ($currentState -notin @("in_progress", "qa")) {
                return @{
                    applied = $false
                    reason = ("task_state=" + $currentState + "; stale_or_unassigned_worker_route")
                    state = ""
                }
            }
        }

        $now = Get-Date -Format "o"
        $lock.state = $lockState
        $lock.updated_at = $now
        $lock.updated_by = "route-monitor"
        if ($qaLevel -and ($qaLevel -ne "full")) {
            Set-ObjectField -obj $lock -name "qa_level" -value $qaLevel
        }
        if ($RouteRunId) {
            Set-ObjectField -obj $lock -name "run_id" -value $RouteRunId
        }
        $routeUpdate = @{
            worker = $WorkerName
            timestamp = $now
            bodyPreview = $bodyPreview
        }
        if ($RouteRunId) {
            $routeUpdate.run_id = $RouteRunId
        }
        Set-ObjectField -obj $lock -name "routeUpdate" -value $routeUpdate
        Write-TaskLocks $locks
        return @{ applied = $true; reason = ""; state = $lockState }
    }

    if (-not $updateResult.applied) {
        return $updateResult
    }

    Write-Host ("  Task lock updated: " + $TaskId + " -> " + $lockState) -ForegroundColor Green

    # 后端 QA 成功后实时触发 doc-updater
    if ($lockState -eq "qa_passed" -and $TaskId -match "^BACKEND-" -and $WorkerName -match "-qa(?:-\d+)?$") {
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

    return $updateResult
}

function Set-TaskLockState {
    param(
        [string]$TaskId,
        [string]$State,
        [string]$UpdatedBy,
        [string]$Note
    )
    Invoke-WithTaskLocksMutex {
        $locks = Read-TaskLocks
        if (-not $locks -or -not $locks.locks) { return }
        if ($locks.locks.PSObject.Properties.Name -notcontains $TaskId) { return }
        $locks.locks.$TaskId.state = $State
        $locks.locks.$TaskId.updated_at = Get-Date -Format "o"
        $locks.locks.$TaskId.updated_by = $UpdatedBy
        if ($Note) {
            $locks.locks.$TaskId.note = $Note
        }
        Write-TaskLocks $locks
    } | Out-Null
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

    $jobHash = Convert-ToArchiveJobMap $jobs.jobs

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

        # 归档兜底：
        # 若 doc-updater 已成功但 commit_task_id 丢失（常见于 archive 中途被中断），
        # 则由 route-monitor 自动补触发 repo-committer，避免任务长期停留在 archiving/running。
        $needCommitRecover = ($RouteTaskId -eq $docTaskId -and $subStatus -eq "success" -and [string]::IsNullOrWhiteSpace($commitTaskId) -and -not [string]::IsNullOrWhiteSpace($taskId))
        if ($needCommitRecover) {
            $recover = Try-RecoverArchiveCommitDispatch -Job $job -TaskId $taskId
            if ($recover.kind -eq "ok") {
                if ($recover.commit_task_id) {
                    Set-ObjectField -obj $job -name "commit_task_id" -value $recover.commit_task_id
                    $commitTaskId = [string]$recover.commit_task_id
                }
                if (-not $job.commit_status -or [string]$job.commit_status -eq "pending") {
                    Set-ObjectField -obj $job -name "commit_status" -value "in_progress"
                }
                if ($recover.worker) {
                    Set-ObjectField -obj $job -name "commit_worker" -value $recover.worker
                }
                if ($recover.pane_id) {
                    Set-ObjectField -obj $job -name "commit_worker_pane_id" -value $recover.pane_id
                }
                Set-ObjectField -obj $job -name "note" -value ("Repo-committer fallback dispatched by route-monitor (" + $recover.message + ")")
                Write-Host ("  [ARCHIVE-JOB] " + $taskId + " fallback dispatched repo-committer (" + $recover.message + ")") -ForegroundColor Cyan
                $commitState = if ($job.commit_status) { [string]$job.commit_status } else { "pending" }
            } elseif ($recover.kind -eq "queued") {
                Set-ObjectField -obj $job -name "note" -value ("Repo-committer fallback queued: " + $recover.message)
                Write-Host ("  [ARCHIVE-JOB] " + $taskId + " fallback queued (" + $recover.message + ")") -ForegroundColor Yellow
            } else {
                Set-ObjectField -obj $job -name "commit_status" -value "blocked"
                Set-ObjectField -obj $job -name "blocked_reason" -value ("commit_fallback_failed: " + $recover.message)
                $commitState = "blocked"
                Write-Host ("  [ARCHIVE-JOB] " + $taskId + " fallback failed (" + $recover.message + ")") -ForegroundColor Yellow
            }
        }

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

function Reconcile-ArchiveCommitFallback {
    $jobs = Read-ArchiveJobs
    if (-not $jobs.jobs) { return }

    $jobHash = Convert-ToArchiveJobMap $jobs.jobs
    $changed = $false

    foreach ($jobId in @($jobHash.Keys)) {
        $job = $jobHash[$jobId]
        if (-not $job) { continue }

        $status = if ($job.status) { [string]$job.status } else { "" }
        if ($status -eq "success" -or $status -eq "blocked") { continue }

        $taskId = if ($job.task_id) { [string]$job.task_id } else { "" }
        $docState = if ($job.doc_status) { [string]$job.doc_status } else { "pending" }
        $commitTaskId = if ($job.commit_task_id) { [string]$job.commit_task_id } else { "" }
        if ([string]::IsNullOrWhiteSpace($taskId)) { continue }
        if ($docState -ne "success") { continue }
        if (-not [string]::IsNullOrWhiteSpace($commitTaskId)) { continue }

        $recover = Try-RecoverArchiveCommitDispatch -Job $job -TaskId $taskId
        if ($recover.kind -eq "ok") {
            if ($recover.commit_task_id) {
                Set-ObjectField -obj $job -name "commit_task_id" -value $recover.commit_task_id
            }
            Set-ObjectField -obj $job -name "commit_status" -value "in_progress"
            Set-ObjectField -obj $job -name "status" -value "running"
            Set-ObjectField -obj $job -name "updated_at" -value (Get-Date -Format "o")
            Set-ObjectField -obj $job -name "updated_by" -value "route-monitor/archive-fallback"
            Set-ObjectField -obj $job -name "note" -value ("Repo-committer fallback dispatched by reconcile (" + $recover.message + ")")
            if ($recover.worker) {
                Set-ObjectField -obj $job -name "commit_worker" -value $recover.worker
            }
            if ($recover.pane_id) {
                Set-ObjectField -obj $job -name "commit_worker_pane_id" -value $recover.pane_id
            }
            Set-TaskLockState -TaskId $taskId -State "archiving" -UpdatedBy "route-monitor/archive-fallback" -Note "Archive resumed: repo-committer fallback dispatched"
            Write-Host ("  [ARCHIVE-JOB] " + $taskId + " reconcile dispatched repo-committer (" + $recover.message + ")") -ForegroundColor Cyan
            $changed = $true
        } elseif ($recover.kind -eq "queued") {
            Set-ObjectField -obj $job -name "updated_at" -value (Get-Date -Format "o")
            Set-ObjectField -obj $job -name "updated_by" -value "route-monitor/archive-fallback"
            Set-ObjectField -obj $job -name "note" -value ("Repo-committer fallback queued: " + $recover.message)
            Write-Host ("  [ARCHIVE-JOB] " + $taskId + " reconcile queued (" + $recover.message + ")") -ForegroundColor Yellow
            $changed = $true
        } else {
            Set-ObjectField -obj $job -name "commit_status" -value "blocked"
            Set-ObjectField -obj $job -name "status" -value "blocked"
            Set-ObjectField -obj $job -name "updated_at" -value (Get-Date -Format "o")
            Set-ObjectField -obj $job -name "updated_by" -value "route-monitor/archive-fallback"
            Set-ObjectField -obj $job -name "blocked_reason" -value ("commit_fallback_failed: " + $recover.message)
            Set-TaskLockState -TaskId $taskId -State "blocked" -UpdatedBy "route-monitor/archive-fallback" -Note ("Archive blocked: commit fallback failed (" + $recover.message + ")")
            Write-Host ("  [ARCHIVE-JOB] " + $taskId + " reconcile failed (" + $recover.message + ")") -ForegroundColor Red
            $changed = $true
        }

        $jobHash[$jobId] = $job
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
    $inboxChanged = $false
    $newProcessed = @{}

    foreach ($r in $routes) {
        $routeId = if ($r.id) { $r.id } else { Get-ShortHash("$($r.task)|$($r.from)|$($r.status)|$($r.created_at)") }
        if ($processedRoutes.ContainsKey($routeId)) {
            # 补偿回写：历史已处理但 inbox 未标记 processed 的记录直接收口，避免 status 假 pending。
            if (-not $r.processed) {
                $r.processed = $true
                $r.processed_at = Get-Date -Format "o"
                $inboxChanged = $true
            }
            continue
        }

        try {
            $gate = Apply-QaSuccessGate -Route $r
            $effectiveRoute = $gate.route
            $notifyAction = "processed"
            $notifyLockState = ""
            $notifyDetail = if ($effectiveRoute.body) { [string]$effectiveRoute.body } else { "" }
            if ($gate.downgraded) {
                Write-Host ("  [QA GATE] success -> blocked: " + $gate.reason) -ForegroundColor Yellow
                $notifyDetail = "qa_gate=" + $gate.reason + "; " + $notifyDetail
            }
            Show-RouteNotification -route $effectiveRoute
            Update-DocSyncStateFromRoute -TaskId $effectiveRoute.task -Status $effectiveRoute.status -WorkerName $effectiveRoute.from -Body $effectiveRoute.body
            Update-ArchiveJobsFromRoute -RouteTaskId ([string]$effectiveRoute.task) -RouteStatus ([string]$effectiveRoute.status) -WorkerName ([string]$effectiveRoute.from) -Body ([string]$effectiveRoute.body)
            $routeRunId = if ($effectiveRoute.PSObject.Properties.Name -contains "run_id" -and $effectiveRoute.run_id) { [string]$effectiveRoute.run_id } else { "" }
            $routeApply = Should-ApplyPrimaryTaskRoute -TaskId ([string]$effectiveRoute.task) -WorkerName ([string]$effectiveRoute.from) -RouteRunId $routeRunId
            if ($routeApply.apply) {
                $lockUpdate = Update-TaskLockFromRoute -TaskId $effectiveRoute.task -Status $effectiveRoute.status -WorkerName $effectiveRoute.from -Body $effectiveRoute.body -RouteRunId $routeRunId
                if ($lockUpdate.applied) {
                    $notifyAction = "applied"
                    $notifyLockState = [string]$lockUpdate.state
                    Update-TaskAttemptHistoryFromRoute -TaskId ([string]$effectiveRoute.task) -Status ([string]$effectiveRoute.status) -WorkerName ([string]$effectiveRoute.from) -ResolvedLockState ([string]$lockUpdate.state) -RunId $routeRunId
                    Write-QaSummaryToTaskFile -TaskId ([string]$effectiveRoute.task) -WorkerName ([string]$effectiveRoute.from) -Status ([string]$effectiveRoute.status).ToLower() -Body ([string]$effectiveRoute.body) -Timestamp (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz")
                } else {
                    $notifyAction = "ignored"
                    $notifyDetail = [string]$lockUpdate.reason
                    Write-Host ("  [ROUTE-IGNORED] task=" + [string]$effectiveRoute.task + " from=" + [string]$effectiveRoute.from + " reason=" + [string]$lockUpdate.reason) -ForegroundColor DarkYellow
                }
            } else {
                $notifyAction = "ignored"
                $notifyDetail = [string]$routeApply.reason
                Write-Host ("  [ROUTE-IGNORED] task=" + [string]$effectiveRoute.task + " from=" + [string]$effectiveRoute.from + " reason=" + $routeApply.reason) -ForegroundColor DarkYellow
            }
            Notify-TeamLeadRouteEvent -Route $effectiveRoute -Action $notifyAction -LockState $notifyLockState -Detail $notifyDetail
            Auto-ResolveBlockedRoute -Route $effectiveRoute -RouteId $routeId
            Maybe-SampleOnRoute -Route $effectiveRoute

            $processedAt = Get-Date -Format "o"
            $newProcessed[$routeId] = $processedAt
            $r.processed = $true
            $r.processed_at = $processedAt
            $inboxChanged = $true
        } catch {
            Notify-TeamLeadRouteEvent -Route $r -Action "error" -LockState "" -Detail $_.Exception.Message
            Write-Host ("  [ROUTE-ERROR] route_id=" + $routeId + " task=" + [string]$r.task + " err=" + $_.Exception.Message) -ForegroundColor Yellow
            continue
        }
    }

    if ($inboxChanged) {
        $inbox.updated_at = Get-Date -Format "o"
        Write-Utf8NoBomFile -path $inboxFile -content ($inbox | ConvertTo-Json -Depth 20)
    }

    if ($newProcessed.Count -gt 0) {
        foreach ($k in $newProcessed.Keys) {
            $processedRoutes[$k] = $newProcessed[$k]
        }
        Save-ProcessedRoutes
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

Write-MonitorState -status "starting" -note "route-monitor bootstrap complete"

do {
    try {
        Process-InboxRoutes
        Reconcile-ArchiveCommitFallback
        Check-RoundCompleteTrigger
        $now = Get-Date
        if (($now - $script:lastStaleSampleScanAt).TotalSeconds -ge 15) {
            Check-StaleHeartbeatsAndSample
            $script:lastStaleSampleScanAt = $now
        }
        Write-MonitorState -status "running"
    } catch {
        Write-MonitorState -status "error" -note $_.Exception.Message
        Write-Host ("Monitor error: " + $_.Exception.Message) -ForegroundColor Yellow
    }

    if ($Continuous) {
        Start-Sleep -Seconds $PollIntervalSeconds
    }
} while ($Continuous)

Write-MonitorState -status "stopped" -note "route-monitor loop exited"
Write-Host ""
Write-Host "Monitor stopped." -ForegroundColor Cyan





