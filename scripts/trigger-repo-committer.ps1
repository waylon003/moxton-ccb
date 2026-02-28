#!/usr/bin/env pwsh
# Repo-Committer auto trigger
# Dispatch commit tasks to repo-specific committer workers after QA success

param(
    [Parameter(Mandatory = $true)]
    [string]$TaskId,

    [Parameter(Mandatory = $false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot
$rootDir = Split-Path $scriptDir -Parent
$workerMapPath = Join-Path $rootDir "config\worker-map.json"
$historyFile = Join-Path $rootDir "config\repo-commit-history.json"

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
    exit 0
}

$workerMap = Read-Json -path $workerMapPath
if (-not $workerMap -or -not $workerMap.$prefix) {
    Write-Host ("Skip: missing worker-map config for prefix " + $prefix) -ForegroundColor Yellow
    exit 0
}

$cfg = $workerMap.$prefix
$repoPath = $cfg.workdir
if (-not (Test-Path $repoPath)) {
    Write-Host ("Skip: repo path not found " + $repoPath) -ForegroundColor Yellow
    exit 0
}

$history = Read-Json -path $historyFile
$historyList = if ($history) { @($history) } else { @() }
if (-not $Force.IsPresent) {
    $existing = $historyList | Where-Object {
        $_.taskId -eq $TaskId -and $_.status -in @("dispatched", "success", "in_progress")
    } | Select-Object -First 1
    if ($existing) {
        Write-Host ("Skip: task already triggered for repo-committer, record_id=" + $existing.id) -ForegroundColor Yellow
        exit 0
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
        exit 0
    }
    Write-Host ("Committer worker offline, starting: " + $commitWorker) -ForegroundColor Yellow
    & (Join-Path $scriptDir "start-worker.ps1") -WorkDir $repoPath -WorkerName $commitWorker -Engine $engine -TeamLeadPaneId $resolvedTeamLeadPaneId | Out-Null
    Start-Sleep -Seconds 3
    $paneId = & (Join-Path $scriptDir "worker-registry.ps1") -Action get -WorkerName $commitWorker 2>$null
}

if (-not $paneId) {
    Write-Host ("Cannot resolve committer pane: " + $commitWorker) -ForegroundColor Yellow
    exit 0
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$commitTaskId = "COMMIT-" + $TaskId + "-" + $timestamp
$taskDir = Join-Path $rootDir "01-tasks\active\repo-committer"
$taskPath = Join-Path $taskDir ($commitTaskId + ".md")
$commitMessage = "chore(" + $TaskId.ToLower() + "): apply qa-verified changes"

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
    "   - git commit -m '$commitMessage'",
    "   - git rev-parse HEAD and report commit SHA.",
    "4. Report completion through report_route.",
    "",
    "## Constraints",
    "- No sub-agent usage.",
    "- Do not run git push unless Team Lead explicitly asks.",
    "- No destructive git commands (reset/clean/force checkout)."
)
$taskContent = $taskLines -join "`n"

Write-Utf8NoBomFile -path $taskPath -content $taskContent

& (Join-Path $scriptDir "dispatch-task.ps1") `
    -WorkerPaneId $paneId `
    -WorkerName $commitWorker `
    -TaskId $commitTaskId `
    -TaskFilePath $taskPath `
    -Engine $engine `
    -TeamLeadPaneId $resolvedTeamLeadPaneId

$recordId = "RC-" + (Get-Date -Format "yyyyMMddHHmmss") + "-" + (Get-Random -Minimum 1000 -Maximum 9999)
$historyList += @{
    id = $recordId
    taskId = $TaskId
    commitTaskId = $commitTaskId
    worker = $commitWorker
    repo = $repoPath
    paneId = $paneId
    status = "dispatched"
    triggeredAt = (Get-Date -Format "o")
}
Write-Utf8NoBomFile -path $historyFile -content ($historyList | ConvertTo-Json -Depth 10)

Write-Host ("Repo-Committer task dispatched: " + $commitTaskId + " -> " + $commitWorker) -ForegroundColor Green
exit 0
