#!/usr/bin/env pwsh
# [ROUTE] Team Lead Notifier - Consume alert events and wake Team Lead
# Usage: .\route-notifier.ps1 -TeamLeadPaneId <id> [-Continuous]

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
$alertsFile = Join-Path $scriptDir "config\teamlead-alerts.jsonl"
$stateFile = Join-Path $scriptDir "config\route-notifier-state.json"
$deliveryLogFile = Join-Path $scriptDir "config\teamlead-delivery.jsonl"
$deliveryFailureLogFile = Join-Path $scriptDir "config\teamlead-delivery-failures.jsonl"
$workerRegistryPath = Join-Path $scriptDir "config\worker-panels.json"
$processedEventsFile = Join-Path $env:TEMP "moxton-ccb-processed-alert-events.json"
$script:notifierStartedAt = Get-Date -Format "o"
$script:weztermCliHealthy = $true
$script:weztermCliLastError = ""
$script:processedCount = 0

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

function Write-NotifierState([string]$status, [string]$note = "") {
    $resolvedNote = if ($note) { [string]$note } else { "" }
    if ([string]::IsNullOrWhiteSpace($resolvedNote) -and (-not $script:weztermCliHealthy)) {
        $resolvedNote = if ($script:weztermCliLastError) { 'wezterm_cli_unavailable: ' + [string]$script:weztermCliLastError } else { 'wezterm_cli_unavailable' }
    }
    $notifierPaneId = ""
    if ($env:WEZTERM_PANE) {
        $notifierPaneId = [string]$env:WEZTERM_PANE
    } elseif ($env:WEZTERM_PANE_ID) {
        $notifierPaneId = [string]$env:WEZTERM_PANE_ID
    }
    $state = [ordered]@{
        status = if ([string]::IsNullOrWhiteSpace($status)) { 'unknown' } else { $status }
        pid = [int]$PID
        teamlead_pane_id = if ($TeamLeadPaneId) { [string]$TeamLeadPaneId } else { '' }
        notifier_pane_id = $notifierPaneId
        continuous = [bool]$Continuous
        poll_interval_seconds = [int]$PollIntervalSeconds
        started_at = $script:notifierStartedAt
        last_loop_at = (Get-Date -Format 'o')
        processed_count = [int]$script:processedCount
        script_path = $PSCommandPath
        note = $resolvedNote
    }
    Write-Utf8NoBomFile -path $stateFile -content ($state | ConvertTo-Json -Depth 6)
}

function Read-JsonLinesFile([string]$Path) {
    if (-not (Test-Path $Path)) { return @() }
    try {
        $lines = @(Get-Content $Path -Encoding UTF8)
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

function Get-EnvIntOrDefault([string]$name, [int]$defaultValue) {
    try {
        $raw = [string](Get-Item -Path ("Env:" + $name) -ErrorAction SilentlyContinue).Value
        if ([string]::IsNullOrWhiteSpace($raw)) { return $defaultValue }
        $val = 0
        if ([int]::TryParse($raw, [ref]$val)) { return $val }
    } catch {}
    return $defaultValue
}

function Get-TeamLeadNotifyRetryCount {
    return Get-EnvIntOrDefault -name "CCB_TEAMLEAD_NOTIFY_RETRY_COUNT" -defaultValue 2
}

function Get-TeamLeadNotifyRetryDelayMs {
    return Get-EnvIntOrDefault -name "CCB_TEAMLEAD_NOTIFY_RETRY_DELAY_MS" -defaultValue 1200
}

function Should-NotifyTeamLeadWake {
    $flag = $env:CCB_ROUTE_MONITOR_NOTIFY
    if ($flag) {
        $norm = $flag.Trim().ToLowerInvariant()
        if ($norm -in @('0','false','no','off')) { return $false }
    }
    return $true
}

function Load-ProcessedEvents {
    $result = @{}
    if (-not (Test-Path $processedEventsFile)) { return $result }
    try {
        $saved = Get-Content $processedEventsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $saved.PSObject.Properties) {
            $result[[string]$prop.Name] = $prop.Value
        }
    } catch {}
    return $result
}

function Save-ProcessedEvents($map) {
    $recent = @{}
    $entries = @()
    if ($map) {
        $entries = @($map.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 500)
    }
    foreach ($entry in $entries) {
        $recent[[string]$entry.Key] = $entry.Value
    }
    Write-Utf8NoBomFile -path $processedEventsFile -content ($recent | ConvertTo-Json -Depth 4)
}

function Get-WeztermPanes {
    try {
        $raw = wezterm cli list --format json 2>$null
        if (-not $raw) {
            $script:weztermCliHealthy = $false
            $script:weztermCliLastError = 'wezterm_cli_empty_result'
            return @()
        }
        $script:weztermCliHealthy = $true
        $script:weztermCliLastError = ''
        return @($raw | ConvertFrom-Json)
    } catch {
        $script:weztermCliHealthy = $false
        $script:weztermCliLastError = $_.Exception.Message
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

function Invoke-TeamLeadSendText([string]$PaneId, [string]$Message) {
    if ([string]::IsNullOrWhiteSpace($PaneId) -or [string]::IsNullOrWhiteSpace($Message)) { return $false }
    wezterm cli send-text --pane-id $PaneId --no-paste $Message | Out-Null
    Start-Sleep -Milliseconds 80
    wezterm cli send-text --pane-id $PaneId --no-paste "`r" | Out-Null
    return $true
}

function Write-TeamLeadDelivery {
    param(
        [string]$EventId,
        [string]$TaskId,
        [string]$Worker,
        [string]$Status,
        [string]$Action,
        [string]$RunId,
        [string]$LockState,
        [string]$PaneId,
        [int]$Attempt,
        [bool]$Sent,
        [string]$Error,
        [string]$Message
    )

    $record = [ordered]@{
        at = (Get-Date -Format 'o')
        event_id = if ($EventId) { $EventId } else { '' }
        task = if ($TaskId) { $TaskId } else { '' }
        worker = if ($Worker) { $Worker } else { '' }
        status = if ($Status) { $Status } else { '' }
        action = if ($Action) { $Action } else { '' }
        run_id = if ($RunId) { $RunId } else { '' }
        lock = if ($LockState) { $LockState } else { '' }
        pane_id = if ($PaneId) { $PaneId } else { '' }
        attempt = if ($Attempt -gt 0) { $Attempt } else { 1 }
        sent = [bool]$Sent
        error = if ($Error) { $Error } else { '' }
        message = if ($Message) { $Message } else { '' }
    }

    $json = $record | ConvertTo-Json -Compress -Depth 8
    Append-Utf8Line -path $deliveryLogFile -line $json
    if (-not $Sent) {
        Append-Utf8Line -path $deliveryFailureLogFile -line $json
    }
}

function Build-AlertMessage($record) {
    if ($record.message) { return [string]$record.message }
    $kind = if ($record.kind) { ([string]$record.kind).ToLowerInvariant() } else { 'route' }
    $task = if ($record.task) { [string]$record.task } else { '-' }
    $worker = if ($record.worker) { [string]$record.worker } else { '-' }
    $status = if ($record.status) { [string]$record.status } else { '-' }
    $action = if ($record.action) { [string]$record.action } else { 'processed' }
    switch ($kind) {
        'auto-decision' { return "[ROUTE-AUTO] task=$task worker=$worker status=$status action=$action. next=status/check_routes" }
        default { return "[ROUTE] task=$task status=$status from=$worker action=$action. next=status/check_routes" }
    }
}

function Test-AlertNeedsReliableNotify($record) {
    if (-not $record) { return $false }
    if ($record.PSObject.Properties.Name -contains 'reliable' -and $null -ne $record.reliable) {
        return [bool]$record.reliable
    }
    $status = if ($record.status) { ([string]$record.status).ToLowerInvariant() } else { '' }
    return ($status -in @('success','blocked','fail','error'))
}

function Notify-AlertRecord($record) {
    if (-not $record) { return $false }
    if (-not (Should-NotifyTeamLeadWake)) {
        Write-TeamLeadDelivery -EventId ([string]$record.event_id) -TaskId ([string]$record.task) -Worker ([string]$record.worker) -Status ([string]$record.status) -Action ([string]$record.action) -RunId ([string]$record.run_id) -LockState ([string]$record.lock) -PaneId '' -Attempt 1 -Sent $false -Error 'route_notifier_notify_disabled' -Message (Build-AlertMessage $record)
        return $false
    }

    $message = Build-AlertMessage $record
    $attemptLimit = 1
    $retryCount = if ($record.retry_count) { [int]$record.retry_count } else { $(if (Test-AlertNeedsReliableNotify $record) { Get-TeamLeadNotifyRetryCount } else { 0 }) }
    $retryDelayMs = if ($record.retry_delay_ms) { [int]$record.retry_delay_ms } else { $(if (Test-AlertNeedsReliableNotify $record) { Get-TeamLeadNotifyRetryDelayMs } else { 0 }) }
    if ($retryCount -gt 0) { $attemptLimit += $retryCount }

    for ($attempt = 1; $attempt -le $attemptLimit; $attempt++) {
        $paneCandidates = New-Object System.Collections.Generic.List[string]
        $preferredPane = Resolve-TeamLeadPaneId -preferredPaneId $TeamLeadPaneId
        if ($preferredPane) { $paneCandidates.Add([string]$preferredPane) | Out-Null }
        $fallbackPane = Resolve-TeamLeadPaneId -preferredPaneId ''
        if ($fallbackPane -and -not $paneCandidates.Contains([string]$fallbackPane)) {
            $paneCandidates.Add([string]$fallbackPane) | Out-Null
        }

        $targetPane = ''
        $lastError = ''
        $sent = $false

        if ($paneCandidates.Count -eq 0) {
            $lastError = 'teamlead_pane_unresolved'
        } else {
            foreach ($candidate in $paneCandidates) {
                $targetPane = [string]$candidate
                try {
                    if (Invoke-TeamLeadSendText -PaneId $targetPane -Message $message) {
                        $sent = $true
                        $lastError = ''
                        break
                    }
                } catch {
                    $lastError = $_.Exception.Message
                }
            }
        }

        Write-TeamLeadDelivery -EventId ([string]$record.event_id) -TaskId ([string]$record.task) -Worker ([string]$record.worker) -Status ([string]$record.status) -Action ([string]$record.action) -RunId ([string]$record.run_id) -LockState ([string]$record.lock) -PaneId $targetPane -Attempt $attempt -Sent $sent -Error $lastError -Message $message
        if ($sent) { return $true }
        if ($attempt -lt $attemptLimit -and $retryDelayMs -gt 0) {
            Start-Sleep -Milliseconds $retryDelayMs
        }
    }

    return $false
}

function Process-TeamLeadAlerts {
    $processed = Load-ProcessedEvents
    $records = @(Read-JsonLinesFile -Path $alertsFile | Sort-Object at)
    foreach ($record in $records) {
        if (-not $record) { continue }
        $kind = if ($record.kind) { ([string]$record.kind).ToLowerInvariant() } else { 'route' }
        if ($kind -notin @('route','auto-decision')) { continue }
        $eventId = if ($record.event_id) { [string]$record.event_id } else { '' }
        if ([string]::IsNullOrWhiteSpace($eventId)) { continue }
        if ($processed.ContainsKey($eventId)) { continue }
        if (Notify-AlertRecord -record $record) {
            $processed[$eventId] = Get-Date -Format 'o'
            $script:processedCount++
        }
    }
    Save-ProcessedEvents $processed
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "       [ROUTE] Team Lead Notifier Started" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ("Team Lead Pane ID: " + $TeamLeadPaneId) -ForegroundColor Cyan
Write-Host ("Mode: " + ($(if ($Continuous) { 'Continuous monitoring' } else { 'Single check' }))) -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

Write-NotifierState -status 'starting' -note 'route-notifier bootstrap complete'

do {
    try {
        Process-TeamLeadAlerts
        Write-NotifierState -status 'running'
    } catch {
        Write-NotifierState -status 'error' -note $_.Exception.Message
        Write-Host ("Notifier error: " + $_.Exception.Message) -ForegroundColor Yellow
    }

    if ($Continuous) {
        Start-Sleep -Seconds $PollIntervalSeconds
    }
} while ($Continuous)

Write-NotifierState -status 'stopped' -note 'route-notifier loop exited'