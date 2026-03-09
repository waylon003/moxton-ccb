#!/usr/bin/env pwsh
# Repo-Committer auto trigger
# Dispatch commit tasks to repo-specific committer workers after QA success

param(
    [Parameter(Mandatory = $true)]
    [string]$TaskId,

    [Parameter(Mandatory = $false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$Push,

    [Parameter(Mandatory = $false)]
    [string]$CommitMessage,

    [Parameter(Mandatory = $false)]
    [switch]$EmitJson
)

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot
$rootDir = Split-Path $scriptDir -Parent
$workerMapPath = Join-Path $rootDir "config\worker-map.json"
$historyFile = Join-Path $rootDir "config\repo-commit-history.json"

function Exit-WithResult([int]$Code, [string]$Status, [string]$Message, [hashtable]$Extra = @{}) {
    if ($EmitJson.IsPresent) {
        $payload = @{
            status = $Status
            message = $Message
            taskId = $TaskId
            mode = if ($Push.IsPresent) { "ship" } else { "commit" }
            timestamp = (Get-Date -Format "o")
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
    return @($value)
}

function Resolve-TaskPrefix([string]$tid) {
    foreach ($p in @("BACKEND", "SHOP-FE", "ADMIN-FE")) {
        if ($tid.StartsWith($p + "-", [System.StringComparison]::OrdinalIgnoreCase)) { return $p }
    }
    return $null
}

function Resolve-TeamLeadPaneId([string]$paneId) {
    if ($paneId) { return $paneId }
    try {
        $panes = wezterm cli list --format json 2>$null | ConvertFrom-Json
        $tlPane = $panes | Where-Object { $_.title -like '*claude*' } | Select-Object -First 1
        if ($tlPane) { return $tlPane.pane_id.ToString() }
    } catch {}
    return ""
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "      Repo-Committer Trigger Check" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ("Task: " + $TaskId) -ForegroundColor White
Write-Host "==============================================" -ForegroundColor Cyan

$prefix = Resolve-TaskPrefix -tid $TaskId
if (-not $prefix) {
    Write-Host "Skip: unsupported task prefix for repo-committer." -ForegroundColor Yellow
    Exit-WithResult -Code 0 -Status "noop" -Message "unsupported_task_prefix"
}

$workerMap = Read-Json -path $workerMapPath
if (-not $workerMap -or -not $workerMap.$prefix) {
    Write-Host ("Skip: missing worker-map config for prefix " + $prefix) -ForegroundColor Yellow
    Exit-WithResult -Code 0 -Status "noop" -Message "missing_worker_map"
}

$cfg = $workerMap.$prefix
$repoPath = $cfg.workdir
if (-not (Test-Path $repoPath)) {
    Write-Host ("Skip: repo path not found " + $repoPath) -ForegroundColor Yellow
    Exit-WithResult -Code 0 -Status "noop" -Message "repo_path_not_found" -Extra @{ repo = $repoPath }
}

$history = Read-Json -path $historyFile
$historyList = @(Normalize-ToList -value $history)
$mode = if ($Push.IsPresent) { "ship" } else { "commit" }
if (-not $Force.IsPresent) {
    $existing = $historyList | Where-Object {
        $recordMode = if ($_.PSObject.Properties.Name -contains "mode" -and $_.mode) { [string]$_.mode } else { "commit" }
        $_.taskId -eq $TaskId -and $recordMode -eq $mode -and $_.status -in @("dispatched", "success", "in_progress")
    } | Select-Object -First 1
    if ($existing) {
        Write-Host ("Skip: task already triggered for repo-committer (" + $mode + "), record_id=" + $existing.id) -ForegroundColor Yellow
        Exit-WithResult -Code 0 -Status "already_dispatched" -Message "already_triggered" -Extra @{
            recordId = [string]$existing.id
            commitTaskId = [string]$existing.commitTaskId
            worker = [string]$existing.worker
            paneId = [string]$existing.paneId
        }
    }
}

$commitWorker = switch ($prefix) {
    "BACKEND" { "backend-committer" }
    "SHOP-FE" { "shop-fe-committer" }
    "ADMIN-FE" { "admin-fe-committer" }
    default { "repo-committer" }
}

$engine = if ($cfg.commit_engine) { $cfg.commit_engine } elseif ($cfg.qa_engine) { $cfg.qa_engine } elseif ($cfg.engine) { $cfg.engine } else { "codex" }
$paneId = & (Join-Path $scriptDir "worker-registry.ps1") -Action get -WorkerName $commitWorker 2>$null
$resolvedTeamLeadPaneId = Resolve-TeamLeadPaneId -paneId $TeamLeadPaneId

if (-not $paneId) {
    if (-not $resolvedTeamLeadPaneId) {
        Write-Host "Cannot auto-start committer worker: TeamLeadPaneId missing." -ForegroundColor Yellow
        Exit-WithResult -Code 0 -Status "queued_pending_worker" -Message "team_lead_pane_missing"
    }
    Write-Host ("Committer worker offline, starting: " + $commitWorker) -ForegroundColor Yellow
    try {
        & (Join-Path $scriptDir "start-worker.ps1") -WorkDir $repoPath -WorkerName $commitWorker -Engine $engine -TeamLeadPaneId $resolvedTeamLeadPaneId | Out-Null
        Start-Sleep -Seconds 3
        $paneId = & (Join-Path $scriptDir "worker-registry.ps1") -Action get -WorkerName $commitWorker 2>$null
    } catch {
        Write-Host ("WARN: start-worker failed for " + $commitWorker + ": " + $_.Exception.Message) -ForegroundColor Yellow
        $paneId = $null
    }
}

if (-not $paneId) {
    Write-Host ("Cannot resolve committer pane: " + $commitWorker) -ForegroundColor Yellow
    Exit-WithResult -Code 0 -Status "queued_pending_worker" -Message "committer_worker_unavailable" -Extra @{ worker = $commitWorker }
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$commitTaskId = ($(if ($Push.IsPresent) { "SHIP-" } else { "COMMIT-" })) + $TaskId + "-" + $timestamp
$resolvedCommitMessage = if ($CommitMessage) { $CommitMessage } else { "chore(" + $TaskId.ToLower() + "): apply qa-verified changes" }

$taskLines = @(
    "# $commitTaskId",
    "",
    "## Target",
    "- Source task: $TaskId",
    "- Repo: $repoPath",
    "- Worker: $commitWorker",
    "",
    "## Steps",
    "1. Run git status --short to inspect pending changes.",
    "2. If no changes, report blocked with reason no_changes_to_commit.",
    "3. If changes exist:",
    "   - git add -A",
    "   - git commit -m '$resolvedCommitMessage'",
    "   - git rev-parse HEAD and report commit SHA.",
    "4. If no local changes but branch may be ahead, check: git status --porcelain=v1 -b",
    "5. If push is required for this task, run: git push",
    "6. Report completion through report_route (include commit SHA and push result).",
    "",
    "## Constraints",
    "- No sub-agent usage.",
    ($(if ($Push.IsPresent) { "- Push is REQUIRED for this task." } else { "- Do not run git push unless Team Lead explicitly asks." })),
    "- No destructive git commands (reset/clean/force checkout)."
)
$taskContent = $taskLines -join "`n"

& (Join-Path $scriptDir "dispatch-task.ps1") `
    -WorkerPaneId $paneId `
    -WorkerName $commitWorker `
    -TaskId $commitTaskId `
    -InlineTaskBody $taskContent `
    -Engine $engine `
    -TeamLeadPaneId $resolvedTeamLeadPaneId

$dispatchExit = $LASTEXITCODE
if ($dispatchExit -ne 0) {
    Write-Host ("Repo-Committer dispatch failed: exit=" + $dispatchExit) -ForegroundColor Red
    Exit-WithResult -Code 1 -Status "dispatch_failed" -Message ("dispatch_exit_" + $dispatchExit) -Extra @{
        worker = $commitWorker
        commitTaskId = $commitTaskId
        paneId = [string]$paneId
    }
}

$recordId = "RC-" + (Get-Date -Format "yyyyMMddHHmmss") + "-" + (Get-Random -Minimum 1000 -Maximum 9999)
$historyList += @{
    id = $recordId
    taskId = $TaskId
    mode = $mode
    commitTaskId = $commitTaskId
    worker = $commitWorker
    repo = $repoPath
    paneId = $paneId
    status = "dispatched"
    triggeredAt = (Get-Date -Format "o")
}
Write-Utf8NoBomFile -path $historyFile -content ($historyList | ConvertTo-Json -Depth 10)

Write-Host ("Repo-Committer task dispatched: " + $commitTaskId + " -> " + $commitWorker) -ForegroundColor Green
Exit-WithResult -Code 0 -Status "dispatched" -Message "repo_committer_dispatched" -Extra @{
    worker = $commitWorker
    commitTaskId = $commitTaskId
    paneId = [string]$paneId
}
