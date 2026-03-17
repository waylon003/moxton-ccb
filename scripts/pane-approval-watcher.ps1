#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkerPaneId,

    [Parameter(Mandatory = $true)]
    [string]$WorkerName,

    [Parameter(Mandatory = $true)]
    [string]$TaskId,

    [Parameter(Mandatory = $false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID,

    [Parameter(Mandatory = $false)]
    [string]$RunId,

    [Parameter(Mandatory = $false)]
    [int]$PollIntervalSeconds = 5,

    [Parameter(Mandatory = $false)]
    [int]$MaxMinutes = 180,

    [Parameter(Mandatory = $false)]
    [switch]$SkipTaskLockGuard
)

$ErrorActionPreference = 'Stop'
$rootDir = Split-Path $PSScriptRoot -Parent
$policyPath = Join-Path $rootDir 'config\approval-policy.json'
$taskLocksPath = Join-Path $rootDir '01-tasks\TASK-LOCKS.json'
$watcherStatePath = Join-Path $rootDir 'config\pane-approval-watchers.json'
$localApprovalEventsPath = Join-Path $rootDir 'config\local-approval-events.jsonl'
$localApprovalStatePath = Join-Path $rootDir 'config\local-approval-state.json'
$teamLeadAlertsPath = Join-Path $rootDir 'config\teamlead-alerts.jsonl'
$watcherMutexName = 'Global\MoxtonPaneApprovalWatcherStateMutex'
$localStateMutexName = 'Global\MoxtonLocalApprovalStateMutex'
$script:startAt = Get-Date
$script:seenFingerprints = @{}
$script:noPromptLoops = 0
$script:weztermUnavailableSince = $null

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

function Invoke-WithNamedMutex([string]$Name, [scriptblock]$Action) {
    $mutex = $null
    $locked = $false
    try {
        $mutex = New-Object System.Threading.Mutex($false, $Name)
        $locked = $mutex.WaitOne(15000)
        if (-not $locked) {
            throw ('mutex timeout: ' + $Name)
        }
        return (& $Action)
    } finally {
        if ($locked -and $mutex) {
            try { $mutex.ReleaseMutex() | Out-Null } catch {}
        }
        if ($mutex) { $mutex.Dispose() }
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

function Read-JsonObject([string]$path, $defaultValue) {
    if (-not (Test-Path $path)) { return $defaultValue }
    try {
        return (Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $defaultValue
    }
}

function Read-ApprovalPolicy {
    $default = [pscustomobject]@{
        approval_prompt_patterns = @('Approval needed','Approve Once','Approve this session','Question 1/1','Would you like to run the following command?','Would you like to make the following edits?','Press enter to confirm or esc to cancel','[y/N]','(y/n)')
        low_risk_patterns = @('mcp__vitest__','mcp__playwright__','mcp__context7__','mcp__route__','apply_patch','browser_','read-only')
        high_risk_patterns = @('rm ','Remove-Item','git reset','git clean','npm install','pnpm add','pip install','dangerously-bypass')
    }
    $policy = Read-JsonObject -path $policyPath -defaultValue $default
    if (-not $policy.approval_prompt_patterns) { $policy | Add-Member -NotePropertyName approval_prompt_patterns -NotePropertyValue $default.approval_prompt_patterns -Force }
    if (-not $policy.low_risk_patterns) { $policy | Add-Member -NotePropertyName low_risk_patterns -NotePropertyValue $default.low_risk_patterns -Force }
    if (-not $policy.high_risk_patterns) { $policy | Add-Member -NotePropertyName high_risk_patterns -NotePropertyValue $default.high_risk_patterns -Force }
    return $policy
}

function Read-TaskLocks {
    return (Read-JsonObject -path $taskLocksPath -defaultValue @{ updated_at = (Get-Date -Format 'o'); locks = @{} })
}

function Read-LocalApprovalState {
    return (Invoke-WithNamedMutex -Name $localStateMutexName -Action {
        $raw = Read-JsonObject -path $localApprovalStatePath -defaultValue @{ updated_at = (Get-Date -Format 'o'); workers = @{} }
        if (-not $raw.workers) {
            $raw | Add-Member -NotePropertyName workers -NotePropertyValue @{} -Force
        } elseif (-not ($raw.workers -is [System.Collections.IDictionary])) {
            $raw.workers = Convert-ToObjectMap $raw.workers
        }
        return $raw
    })
}

function Update-LocalApprovalStateEntry([string]$WorkerNameArg, [scriptblock]$Mutator) {
    Invoke-WithNamedMutex -Name $localStateMutexName -Action {
        $state = Read-JsonObject -path $localApprovalStatePath -defaultValue @{ updated_at = (Get-Date -Format 'o'); workers = @{} }
        $workers = Convert-ToObjectMap $state.workers
        $current = $null
        if ($workers.ContainsKey($WorkerNameArg)) { $current = $workers[$WorkerNameArg] }
        $next = & $Mutator $current
        if ($null -eq $next) {
            if ($workers.ContainsKey($WorkerNameArg)) { $workers.Remove($WorkerNameArg) | Out-Null }
        } else {
            $workers[$WorkerNameArg] = $next
        }
        $state.updated_at = Get-Date -Format 'o'
        $state.workers = $workers
        Write-Utf8NoBomFile -path $localApprovalStatePath -content ($state | ConvertTo-Json -Depth 10)
        return $next
    }
}

function Read-WatcherStore {
    return (Invoke-WithNamedMutex -Name $watcherMutexName -Action {
        $raw = Read-JsonObject -path $watcherStatePath -defaultValue @{ updated_at = (Get-Date -Format 'o'); watchers = @{} }
        if (-not $raw.watchers) {
            $raw | Add-Member -NotePropertyName watchers -NotePropertyValue @{} -Force
        } elseif (-not ($raw.watchers -is [System.Collections.IDictionary])) {
            $raw.watchers = Convert-ToObjectMap $raw.watchers
        }
        return $raw
    })
}

function Update-WatcherStoreEntry([scriptblock]$Mutator) {
    Invoke-WithNamedMutex -Name $watcherMutexName -Action {
        $store = Read-JsonObject -path $watcherStatePath -defaultValue @{ updated_at = (Get-Date -Format 'o'); watchers = @{} }
        $watchers = Convert-ToObjectMap $store.watchers
        $nextWatchers = & $Mutator $watchers
        if ($null -eq $nextWatchers) { $nextWatchers = $watchers }
        $store.updated_at = Get-Date -Format 'o'
        $store.watchers = $nextWatchers
        Write-Utf8NoBomFile -path $watcherStatePath -content ($store | ConvertTo-Json -Depth 10)
    }
}

function Set-WatcherHeartbeat([string]$status, [string]$reason = '') {
    $key = ($TaskId + '|' + $WorkerName).ToUpperInvariant()
    Update-WatcherStoreEntry {
        param($watchers)
        $entry = if ($watchers.ContainsKey($key)) { $watchers[$key] } else { @{} }
        $entry.task = $TaskId
        $entry.worker = $WorkerName
        $entry.worker_pane_id = $WorkerPaneId
        $entry.team_lead_pane_id = if ($TeamLeadPaneId) { $TeamLeadPaneId } else { '' }
        $entry.run_id = if ($RunId) { $RunId } else { '' }
        $entry.skip_task_lock_guard = [bool]$SkipTaskLockGuard
        $entry.pid = [int]$PID
        $entry.started_at = if ($entry.started_at) { $entry.started_at } else { $script:startAt.ToString('o') }
        $entry.last_seen = Get-Date -Format 'o'
        $entry.status = if ($status) { $status } else { 'active' }
        $entry.reason = if ($reason) { $reason } else { '' }
        $watchers[$key] = $entry
        return $watchers
    }
}

function Remove-WatcherEntry {
    $key = ($TaskId + '|' + $WorkerName).ToUpperInvariant()
    Update-WatcherStoreEntry {
        param($watchers)
        if ($watchers.ContainsKey($key)) {
            $watchers.Remove($key) | Out-Null
        }
        return $watchers
    }
}

function Get-WeztermPanes {
    try {
        $raw = wezterm cli list --format json 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $raw) { return @() }
        return @($raw | ConvertFrom-Json)
    } catch {
        return @()
    }
}

function Test-PaneAlive([string]$paneId) {
    if (-not $paneId) { return $false }
    $panes = Get-WeztermPanes
    foreach ($pane in $panes) {
        if ([string]$pane.pane_id -eq [string]$paneId) { return $true }
    }
    try {
        $text = wezterm cli get-text --pane-id $paneId 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Get-WorkerPaneTail([string]$paneId, [int]$maxLines = 120) {
    if (-not $paneId) { return '' }
    try {
        $text = wezterm cli get-text --pane-id $paneId 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $text) { return '' }
        $parts = @($text -split "`n")
        if ($parts.Count -gt $maxLines) {
            $parts = $parts[-$maxLines..-1]
        }
        return (($parts -join "`n") -replace "`r", '')
    } catch {
        return ''
    }
}

function Test-ContainsAny([string]$text, $patterns) {
    if (-not $text -or -not $patterns) { return $false }
    foreach ($pattern in @($patterns)) {
        $needle = [string]$pattern
        if (-not $needle) { continue }
        if ($text.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }
    return $false
}

function Resolve-LocalPromptTypeFromText([string]$tail) {
    if (-not $tail) { return 'command_approval' }
    if (Test-ContainsAny -text $tail -patterns @('Question 1/1','Approve Once','Approve this session','Run the tool and continue','1. Approve Once','2. Approve this session','3. Cancel')) {
        return 'menu_approval'
    }
    if (Test-ContainsAny -text $tail -patterns @('Press enter to confirm or esc to cancel','press enter to confirm and save','enter to confirm','esc to cancel','tab to add notes')) {
        return 'edit_confirm'
    }
    return 'command_approval'
}

function Resolve-Risk([string]$tail, $policy) {
    if (Test-ContainsAny -text $tail -patterns $policy.high_risk_patterns) { return 'high' }
    if (Test-ContainsAny -text $tail -patterns $policy.low_risk_patterns) { return 'low' }
    return 'unknown'
}

function New-Fingerprint([string]$tail, [string]$promptType) {
    $normalized = (($tail -replace '\s+', ' ').Trim()) + '|' + $promptType
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant())
    } finally {
        $sha.Dispose()
    }
}

function Get-Preview([string]$tail) {
    if (-not $tail) { return '' }
    $flat = ($tail -replace '\s+', ' ').Trim()
    if ($flat.Length -gt 180) {
        return $flat.Substring($flat.Length - 180)
    }
    return $flat
}

function Send-ApprovalDecisionToPane([string]$paneId, [string]$promptType, [string]$decision, [string]$approvalMode = 'default') {
    if ($promptType -eq 'edit_confirm') {
        $key = if ($decision -eq 'approve') { "`r" } else { "`e" }
        wezterm cli send-text --pane-id $paneId --no-paste $key | Out-Null
        return ($LASTEXITCODE -eq 0)
    }

    if ($promptType -eq 'menu_approval') {
        if ($decision -eq 'approve') {
            $key = if ($approvalMode -eq 'session') { '2' } else { '1' }
        } else {
            $key = '3'
        }
        wezterm cli send-text --pane-id $paneId --no-paste $key | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
        Start-Sleep -Milliseconds 200
        wezterm cli send-text --pane-id $paneId --no-paste "`r" | Out-Null
        return ($LASTEXITCODE -eq 0)
    }

    $yn = if ($decision -eq 'approve') { 'y' } else { 'n' }
    wezterm cli send-text --pane-id $paneId --no-paste $yn | Out-Null
    if ($LASTEXITCODE -ne 0) { return $false }
    Start-Sleep -Milliseconds 200
    wezterm cli send-text --pane-id $paneId --no-paste "`r" | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Write-WatcherAlert([string]$Status, [string]$Action, [string]$Detail) {
    $locks = Read-TaskLocks
    $lockState = ''
    if ($locks.locks -and $locks.locks.PSObject.Properties.Name -contains $TaskId) {
        $lock = $locks.locks.$TaskId
        if ($lock.state) { $lockState = [string]$lock.state }
    }
    $record = [ordered]@{
        at = (Get-Date -Format 'o')
        kind = 'watcher'
        task = $TaskId
        worker = $WorkerName
        status = if ($Status) { $Status } else { '' }
        action = if ($Action) { $Action } else { '' }
        run_id = if ($RunId) { $RunId } else { '' }
        lock = $lockState
        detail = if ($Detail) { $Detail } else { '' }
    }
    Append-Utf8Line -path $teamLeadAlertsPath -line ($record | ConvertTo-Json -Compress -Depth 8)
}

function Write-TeamLeadAlert([string]$status, [string]$action, [string]$detail) {
    $locks = Read-TaskLocks
    $lockState = ''
    if ($locks.locks -and $locks.locks.PSObject.Properties.Name -contains $TaskId) {
        $lock = $locks.locks.$TaskId
        if ($lock.state) { $lockState = [string]$lock.state }
    }
    $record = [ordered]@{
        at = (Get-Date -Format 'o')
        kind = 'local_approval'
        task = $TaskId
        worker = $WorkerName
        status = if ($status) { $status } else { '' }
        action = if ($action) { $action } else { '' }
        run_id = if ($RunId) { $RunId } else { '' }
        lock = $lockState
        detail = if ($detail) { $detail } else { '' }
    }
    Append-Utf8Line -path $teamLeadAlertsPath -line ($record | ConvertTo-Json -Compress -Depth 8)
}

function Get-CurrentLocalStateEntry {
    $state = Read-LocalApprovalState
    $workers = Convert-ToObjectMap $state.workers
    if ($workers.ContainsKey($WorkerName)) {
        return $workers[$WorkerName]
    }
    return $null
}

function Test-TaskStillActive {
    if ($SkipTaskLockGuard) { return $true }
    $locks = Read-TaskLocks
    if (-not $locks.locks -or $locks.locks.PSObject.Properties.Name -notcontains $TaskId) {
        return $false
    }
    $lock = $locks.locks.$TaskId
    $state = if ($lock.state) { [string]$lock.state } else { '' }
    if ($state -notin @('in_progress', 'qa', 'archiving')) {
        return $false
    }
    $assignedWorker = if ($lock.assigned_worker) { [string]$lock.assigned_worker } else { '' }
    if ($assignedWorker -and $assignedWorker -ne $WorkerName) {
        return $false
    }
    $lockRunId = if ($lock.run_id) { [string]$lock.run_id } else { '' }
    if ($RunId -and $lockRunId -and $RunId -ne $lockRunId) {
        return $false
    }
    return $true
}

function Write-LocalApprovalRecord([string]$eventId, [string]$status, [string]$risk, [string]$promptType, [string]$fingerprint, [string]$preview, [string]$actionTaken) {
    $now = Get-Date -Format 'o'
    $record = [ordered]@{
        at = $now
        kind = 'local_approval'
        event_id = $eventId
        task = $TaskId
        worker = $WorkerName
        pane_id = $WorkerPaneId
        run_id = if ($RunId) { $RunId } else { '' }
        status = if ($status) { $status } else { '' }
        risk = if ($risk) { $risk } else { 'unknown' }
        prompt_type = if ($promptType) { $promptType } else { 'command_approval' }
        fingerprint = if ($fingerprint) { $fingerprint } else { '' }
        preview = if ($preview) { $preview } else { '' }
        action = if ($actionTaken) { $actionTaken } else { '' }
    }
    Append-Utf8Line -path $localApprovalEventsPath -line ($record | ConvertTo-Json -Compress -Depth 8)
}

function Set-LocalApprovalState([string]$eventId, [string]$status, [string]$risk, [string]$promptType, [string]$fingerprint, [string]$preview, [string]$decision = '') {
    $updatedAt = Get-Date -Format 'o'
    Update-LocalApprovalStateEntry -WorkerNameArg $WorkerName -Mutator {
        param($current)
        return @{
            event_id = $eventId
            worker = $WorkerName
            task = $TaskId
            pane_id = $WorkerPaneId
            run_id = if ($RunId) { $RunId } else { '' }
            status = $status
            risk = $risk
            prompt_type = $promptType
            fingerprint = $fingerprint
            preview = $preview
            decision = $decision
            opened_at = if ($current.opened_at) { [string]$current.opened_at } else { $updatedAt }
            updated_at = $updatedAt
        }
    } | Out-Null
}

function Clear-LocalStateWithEvent([string]$reason) {
    $current = Get-CurrentLocalStateEntry
    if ($current) {
        $preview = if ($current.preview) { [string]$current.preview } else { '' }
        Write-LocalApprovalRecord -eventId (if ($current.event_id) { [string]$current.event_id } else { '' }) -status 'closed' -risk (if ($current.risk) { [string]$current.risk } else { 'unknown' }) -promptType (if ($current.prompt_type) { [string]$current.prompt_type } else { 'command_approval' }) -fingerprint (if ($current.fingerprint) { [string]$current.fingerprint } else { '' }) -preview $preview -actionTaken $reason
    }
    Update-LocalApprovalStateEntry -WorkerNameArg $WorkerName -Mutator { param($current) return $null } | Out-Null
}

$policy = Read-ApprovalPolicy
Set-WatcherHeartbeat -status 'active' -reason 'started'
Write-WatcherAlert -Status 'watcher_started' -Action 'start' -Detail ('pane=' + $WorkerPaneId + '; run_id=' + (if ($RunId) { $RunId } else { '' }))

try {
    while ($true) {
        if ($MaxMinutes -gt 0 -and ((Get-Date) - $script:startAt).TotalMinutes -ge $MaxMinutes) {
            throw 'timeout'
        }

        if (-not (Test-TaskStillActive)) {
            throw 'task_not_active'
        }

        if (-not (Test-PaneAlive -paneId $WorkerPaneId)) {
            if (-not $script:weztermUnavailableSince) {
                $script:weztermUnavailableSince = Get-Date
                Set-WatcherHeartbeat -status 'waiting_wezterm' -reason 'pane_unreachable'
            }
            $downSeconds = ((Get-Date) - $script:weztermUnavailableSince).TotalSeconds
            if ($downSeconds -lt 90) {
                Start-Sleep -Seconds ([Math]::Max(2, $PollIntervalSeconds))
                continue
            }
            throw 'pane_gone'
        }
        $script:weztermUnavailableSince = $null

        Set-WatcherHeartbeat -status 'active'
        $tail = Get-WorkerPaneTail -paneId $WorkerPaneId
        $hasPrompt = Test-ContainsAny -text $tail -patterns $policy.approval_prompt_patterns

        if ($hasPrompt) {
            $script:noPromptLoops = 0
            $promptType = Resolve-LocalPromptTypeFromText -tail $tail
            $risk = Resolve-Risk -tail $tail -policy $policy
            $fingerprint = New-Fingerprint -tail $tail -promptType $promptType
            $preview = Get-Preview -tail $tail
            $existing = Get-CurrentLocalStateEntry
            $alreadyTracked = $false
            if ($existing -and $existing.fingerprint -and [string]$existing.fingerprint -eq $fingerprint -and [string]$existing.status -in @('pending_teamlead', 'auto_approved')) {
                $alreadyTracked = $true
            }
            if (-not $alreadyTracked -and -not $script:seenFingerprints.ContainsKey($fingerprint)) {
                $eventId = 'LAP-' + (Get-Date -Format 'yyyyMMddHHmmssfff') + '-' + $WorkerName
                $actionTaken = 'notify_teamlead'
                $status = 'pending_teamlead'
                $decision = ''
                $sent = $false
                if ($risk -eq 'low') {
                    $sent = Send-ApprovalDecisionToPane -paneId $WorkerPaneId -promptType $promptType -decision 'approve'
                    if ($sent) {
                        $status = 'auto_approved'
                        $actionTaken = if ($promptType -eq 'menu_approval') { 'approve_once' } elseif ($promptType -eq 'edit_confirm') { 'enter_confirm' } else { 'approve' }
                        $decision = $actionTaken
                    }
                }
                Set-LocalApprovalState -eventId $eventId -status $status -risk $risk -promptType $promptType -fingerprint $fingerprint -preview $preview -decision $decision
                Write-LocalApprovalRecord -eventId $eventId -status $status -risk $risk -promptType $promptType -fingerprint $fingerprint -preview $preview -actionTaken $actionTaken
                if ($status -eq 'pending_teamlead') {
                    Write-TeamLeadAlert -status 'pending_teamlead' -action $promptType -detail ('risk=' + $risk + '; event_id=' + $eventId + '; preview=' + $preview)
                }
                $script:seenFingerprints[$fingerprint] = Get-Date
            }
        } else {
            $script:noPromptLoops++
            $current = Get-CurrentLocalStateEntry
            if ($current -and [string]$current.task -eq $TaskId -and $script:noPromptLoops -ge 6) {
                Clear-LocalStateWithEvent -reason 'prompt_disappeared'
            }
        }

        foreach ($key in @($script:seenFingerprints.Keys)) {
            $at = $script:seenFingerprints[$key]
            if ($at -is [datetime] -and ((Get-Date) - $at).TotalMinutes -gt 30) {
                $script:seenFingerprints.Remove($key) | Out-Null
            }
        }

        Start-Sleep -Seconds ([Math]::Max(2, $PollIntervalSeconds))
    }
} catch {
    $reason = if ($_.Exception -and $_.Exception.Message) { $_.Exception.Message } else { 'stopped' }
    Set-WatcherHeartbeat -status 'stopped' -reason $reason
    if ($reason -notin @('task_not_active')) {
        Write-WatcherAlert -Status 'watcher_error' -Action 'error' -Detail ('reason=' + $reason + '; pane=' + $WorkerPaneId + '; run_id=' + (if ($RunId) { $RunId } else { '' }))
        Write-TeamLeadAlert -status 'watcher_error' -action 'pane_watcher' -detail ('reason=' + $reason + '; worker=' + $WorkerName + '; task=' + $TaskId + '; pane=' + $WorkerPaneId)
    }
} finally {
    Clear-LocalStateWithEvent -reason 'watcher_exit'
    Remove-WatcherEntry
}
