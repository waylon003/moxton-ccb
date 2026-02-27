#!/usr/bin/env pwsh
# [ROUTE] Message Monitor - Auto-parse Worker receipts and update task locks
# Usage: .\route-monitor.ps1 -TeamLeadPaneId <id> [-Continuous]

param(
    [Parameter(Mandatory=$false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID,

    [Parameter(Mandatory=$false)]
    [switch]$Continuous,

    [Parameter(Mandatory=$false)]
    [int]$PollIntervalSeconds = 5
)

$ErrorActionPreference = "Stop"

# Validate environment
if (-not $TeamLeadPaneId) {
    Write-Error "TEAM_LEAD_PANE_ID not set. Please set environment variable first."
    exit 1
}

# Get project root
$scriptDir = Split-Path $PSScriptRoot -Parent
$locksFile = Join-Path $scriptDir "01-tasks\TASK-LOCKS.json"

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "       [ROUTE] Message Monitor Started" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Team Lead Pane ID: $TeamLeadPaneId" -ForegroundColor Cyan
if ($Continuous) {
    Write-Host "Mode: Continuous monitoring" -ForegroundColor Cyan
} else {
    Write-Host "Mode: Single check" -ForegroundColor Cyan
}
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# Processed messages tracking
$processedRoutes = @{}
$processedRoutesFile = Join-Path $env:TEMP "moxton-ccb-processed-routes.json"

# Load persisted records
function Load-ProcessedRoutes {
    if (Test-Path $processedRoutesFile) {
        try {
            $content = Get-Content $processedRoutesFile -Raw -ErrorAction SilentlyContinue
            if ($content) {
                $saved = $content | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($saved) {
                    foreach ($key in $saved.PSObject.Properties.Name) {
                        $processedRoutes[$key] = $saved.$key
                    }
                    Write-Host "  Loaded $($processedRoutes.Count) historical message records" -ForegroundColor Gray
                }
            }
        }
        catch {
            # Ignore load errors
        }
    }
}

# Save processed records (CALLED AFTER EACH MESSAGE)
function Save-ProcessedRoutes {
    try {
        # Keep only last 100 records
        $recentRoutes = @{}
        $sortedKeys = $processedRoutes.Keys | Sort-Object -Descending | Select-Object -First 100
        foreach ($key in $sortedKeys) {
            $recentRoutes[$key] = $processedRoutes[$key]
        }
        $recentRoutes | ConvertTo-Json -Depth 3 | Set-Content $processedRoutesFile -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch {
        # Ignore save errors
    }
}

# Compute SHA256 hash for deduplication
function Get-MessageHash {
    param([string]$content)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
    $hash = $sha256.ComputeHash($bytes)
    return [BitConverter]::ToString($hash).Replace("-", "").Substring(0, 16)
}

# Update task lock from ROUTE message
function Update-TaskLockFromRoute {
    param(
        [string]$TaskId,
        [string]$Status,
        [string]$WorkerName,
        [string]$Body
    )

    Write-Host "Updating task lock: $TaskId -> $Status" -ForegroundColor Yellow

    # Smart state mapping: dev success -> waiting_qa, qa success -> completed
    $lockState = switch ($Status.ToLower()) {
        "success" {
            if ($WorkerName -match "-qa$") {
                "completed"
            } elseif ($WorkerName -match "-dev$") {
                Write-Host "  Dev done, marking as waiting_qa, needs QA verification" -ForegroundColor Cyan
                "waiting_qa"
            } else {
                "waiting_qa"
            }
        }
        "fail" { "blocked" }
        "blocked" { "blocked" }
        "in_progress" { "in_progress" }
        "qa" { "qa" }
        "waiting_qa" { "waiting_qa" }
        default { $Status }
    }

    try {
        if (Test-Path $locksFile) {
            $locks = Get-Content $locksFile -Raw | ConvertFrom-Json

            if ($locks.locks.$TaskId) {
                $locks.locks.$TaskId.state = $lockState
                $locks.locks.$TaskId.updated_at = Get-Date -Format "o"
                $bodyPreview = if ($Body.Length -gt 100) { $Body.Substring(0, 100) + "..." } else { $Body }
                $routeInfo = [PSCustomObject]@{
                    worker = $WorkerName
                    timestamp = Get-Date -Format "o"
                    bodyPreview = $bodyPreview
                }
                if ($locks.locks.$TaskId.PSObject.Properties["routeUpdate"]) {
                    $locks.locks.$TaskId.routeUpdate = $routeInfo
                } else {
                    $locks.locks.$TaskId | Add-Member -NotePropertyName "routeUpdate" -NotePropertyValue $routeInfo
                }

                $locks | ConvertTo-Json -Depth 10 | Set-Content $locksFile -Encoding UTF8
                Write-Host "  Task lock updated: $TaskId -> $lockState" -ForegroundColor Green

                # Show next steps
                switch ($lockState) {
                    "waiting_qa" {
                        Write-Host "  Next: Dispatch QA Worker for verification" -ForegroundColor Cyan
                    }
                    "completed" {
                        Write-Host "  Task completed, can archive to completed/ folder" -ForegroundColor Cyan

                        # Trigger Doc-Updater for BACKEND QA success
                        if ($TaskId -match "^BACKEND-" -and $WorkerName -match "-qa$") {
                            Write-Host "  Triggering Doc-Updater for API documentation..." -ForegroundColor Cyan
                            $docTriggerScript = Join-Path $scriptDir "trigger-doc-updater.ps1"
                            if (Test-Path $docTriggerScript) {
                                Start-Job -ScriptBlock {
                                    param($script, $task, $pane)
                                    & $script -TaskId $task -TeamLeadPaneId $pane
                                } -ArgumentList $docTriggerScript, $TaskId, $TeamLeadPaneId | Out-Null
                            }
                        }
                    }
                    "blocked" {
                        Write-Host "  WARNING: Task blocked, needs Team Lead intervention" -ForegroundColor Red
                    }
                }
            }
            else {
                Write-Host "  Warning: Task $TaskId lock record not found, skipping update" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "  Error: Failed to update task lock: $_" -ForegroundColor Red
    }
}

# Parse ROUTE messages from text
function Parse-RouteMessage {
    param([string]$text)

    # Match [ROUTE] ... [/ROUTE] blocks
    $routePattern = '\[ROUTE\]\s*(.*?)\s*\[/ROUTE\]'
    $matchResults = [regex]::Matches($text, $routePattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

    foreach ($match in $matchResults) {
        $routeContent = $match.Groups[1].Value

        # Parse fields
        $localFrom = ""
        $localTo = ""
        $localType = ""
        $localTask = ""
        $localStatus = ""

        if ($routeContent -match 'from:\s*(\S+)') {
            $localFrom = $matches[1]
        }
        if ($routeContent -match 'to:\s*(\S+)') {
            $localTo = $matches[1]
        }
        if ($routeContent -match 'type:\s*(\S+)') {
            $localType = $matches[1]
        }
        if ($routeContent -match 'task:\s*(\S+)') {
            $localTask = $matches[1]
        }
        if ($routeContent -match 'status:\s*(\S+)') {
            $localStatus = $matches[1]
        }

        # Extract body (multiline)
        $localBody = ""
        if ($routeContent -match 'body:\s*\|?\s*\r?\n(.*)') {
            $localBody = $matches[1].Trim()
        }

        # Deduplication: Use content hash (NOT minute-based)
        $routeId = Get-MessageHash -content $routeContent

        if (-not $processedRoutes.ContainsKey($routeId)) {
            $processedRoutes[$routeId] = (Get-Date).ToString("o")

            # SAVE AFTER EACH MESSAGE (required by acceptance criteria)
            Save-ProcessedRoutes

            [PSCustomObject]@{
                From = $localFrom
                To = $localTo
                Type = $localType
                Task = $localTask
                Status = $localStatus
                Body = $localBody
                RouteId = $routeId
            }
        }
    }
}

function Show-RouteNotification {
    param([PSCustomObject]$route)

    $color = "Yellow"
    if ($route.Status -eq "success") {
        $color = "Green"
    }
    elseif ($route.Status -eq "fail") {
        $color = "Red"
    }

    Write-Host ""
    Write-Host "==============================================" -ForegroundColor $color
    Write-Host "  [ROUTE] Message Received" -ForegroundColor White
    Write-Host "==============================================" -ForegroundColor $color
    Write-Host "  From:   $($route.From)" -ForegroundColor White
    Write-Host "  To:     $($route.To)" -ForegroundColor White
    Write-Host "  Task:   $($route.Task)" -ForegroundColor White
    Write-Host "  Status: $($route.Status)" -ForegroundColor White
    Write-Host "  Type:   $($route.Type)" -ForegroundColor White
    Write-Host "==============================================" -ForegroundColor $color
    Write-Host ""
}

# Initialize
Load-ProcessedRoutes

# Main monitoring loop
do {
    try {
        # Get latest output from Team Lead pane
        $output = wezterm cli get-text --pane-id $TeamLeadPaneId 2>&1

        if ($output -match '\[ROUTE\]') {
            $routes = Parse-RouteMessage -text $output

            foreach ($route in $routes) {
                Show-RouteNotification -route $route

                # Auto-update task lock
                if ($route.Task -and $route.Status) {
                    Update-TaskLockFromRoute `
                        -TaskId $route.Task `
                        -Status $route.Status `
                        -WorkerName $route.From `
                        -Body $route.Body
                }

                # Blocker handling
                if ($route.Type -eq "blocker") {
                    Write-Host "BLOCKER received! Team Lead intervention required." -ForegroundColor Red -BackgroundColor Black
                }
            }
        }
    }
    catch {
        Write-Host "Monitor error: $_" -ForegroundColor Yellow
    }

    if ($Continuous) {
        Write-Host "." -NoNewline -ForegroundColor Gray
        Start-Sleep -Seconds $PollIntervalSeconds
    }
} while ($Continuous)

Write-Host ""
Write-Host "Monitor stopped." -ForegroundColor Cyan
