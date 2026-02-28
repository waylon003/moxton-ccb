#!/usr/bin/env pwsh
# approval-router.ps1 - 监听 Worker 权限提示，低风险自动批准，高风险转发 Team Lead
# Exit codes: 0=handled, 1=timeout/no approval, 2=script error
param(
    [Parameter(Mandatory=$true)]
    [string]$WorkerPaneId,

    [Parameter(Mandatory=$true)]
    [string]$WorkerName,

    [Parameter(Mandatory=$true)]
    [string]$TaskId,

    [Parameter(Mandatory=$true)]
    [string]$TeamLeadPaneId,

    [int]$PollInterval = 2,
    [int]$Timeout = 600,
    [string]$PolicyPath
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
$inboxPath = Join-Path $rootDir "mcp\route-server\data\route-inbox.json"
$locksPath = Join-Path $rootDir "01-tasks\TASK-LOCKS.json"
$requestsPath = Join-Path $rootDir "mcp\route-server\data\approval-requests.json"
if (-not $PolicyPath) {
    $PolicyPath = Join-Path $rootDir "config\approval-policy.json"
}

function Read-JsonRetry($path, $maxRetry = 3) {
    for ($i = 0; $i -lt $maxRetry; $i++) {
        try {
            if (-not (Test-Path $path)) { return $null }
            return (Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json)
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }
    return $null
}

function Write-JsonUtf8($path, $data) {
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = ($data | ConvertTo-Json -Depth 20)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $json, $utf8NoBom)
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

function Contains-Any([string]$text, $patterns) {
    if (-not $text -or -not $patterns) { return $false }
    foreach ($pat in $patterns) {
        if ($text -like ("*" + $pat + "*")) { return $true }
    }
    return $false
}

function Ensure-RequestsFile {
    if (Test-Path $requestsPath) { return }
    $initial = @{
        version = "1.0"
        updated_at = (Get-Date -Format "o")
        requests = @()
    }
    Write-JsonUtf8 -path $requestsPath -data $initial
}

function Save-ApprovalRequest($request) {
    Ensure-RequestsFile
    $store = Read-JsonRetry -path $requestsPath
    if (-not $store) {
        $store = @{ version = "1.0"; updated_at = (Get-Date -Format "o"); requests = @() }
    }
    $store.requests = @($store.requests) + $request
    $store.updated_at = Get-Date -Format "o"
    Write-JsonUtf8 -path $requestsPath -data $store
}

function Append-RouteInbox([string]$status, [string]$body) {
    $routeId = Get-ShortHash("$WorkerName|$TaskId|$status|$body|$(Get-Date -Format o)")
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        try {
            $inbox = Read-JsonRetry -path $inboxPath
            if (-not $inbox) {
                $inbox = @{
                    version = "1.0"
                    updated_at = (Get-Date -Format "o")
                    routes = @()
                }
            }
            if (-not $inbox.routes) {
                $inbox.routes = @()
            }
            $route = @{
                id = $routeId
                from = $WorkerName
                to = "team-lead"
                type = "status"
                task = $TaskId
                status = $status
                body = $body
                created_at = (Get-Date -Format "o")
                processed = $false
                processed_at = $null
            }
            $inbox.routes = @($inbox.routes) + $route
            $inbox.updated_at = Get-Date -Format "o"
            Write-JsonUtf8 -path $inboxPath -data $inbox
            return $routeId
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }
    throw "Failed to append route inbox after retries."
}

function Mark-TaskBlocked([string]$note) {
    $locks = Read-JsonRetry -path $locksPath
    if (-not $locks -or -not $locks.locks) { return }
    if ($locks.locks.PSObject.Properties.Name -notcontains $TaskId) { return }
    $locks.locks.$TaskId.state = "blocked"
    $locks.locks.$TaskId.updated_at = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    $locks.locks.$TaskId.updated_by = "approval-router"
    $locks.locks.$TaskId.note = $note
    Write-JsonUtf8 -path $locksPath -data $locks
}

function Send-DecisionToWorker([string]$decisionKey) {
    wezterm cli send-text --pane-id $WorkerPaneId --no-paste $decisionKey | Out-Null
    Start-Sleep -Milliseconds 150
    wezterm cli send-text --pane-id $WorkerPaneId --no-paste "`r" | Out-Null
}

try {
    $policy = Read-JsonRetry -path $PolicyPath
    if (-not $policy) {
        $policy = @{
            approval_prompt_patterns = @("Approval needed", "requires approval", "permission", "approve")
            low_risk_patterns = @("mcp__vitest__", "mcp__playwright__", "mcp__context7__", "git status", "git diff", "rg ")
            high_risk_patterns = @("rm ", "Remove-Item", "git reset", "git clean", "npm install", "pnpm add", "pip install")
        }
    }

    $elapsed = 0
    $seen = @{}
    while ($elapsed -lt $Timeout) {
        $paneText = wezterm cli get-text --pane-id $WorkerPaneId 2>$null
        if ($paneText) {
            $tailLines = @($paneText -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -Last 30)
            $tail = $tailLines -join "`n"
            if (Contains-Any -text $tail -patterns $policy.approval_prompt_patterns) {
                $fingerprint = Get-ShortHash($tail)
                if (-not $seen.ContainsKey($fingerprint)) {
                    $seen[$fingerprint] = $true
                    $risk = "unknown"
                    if (Contains-Any -text $tail -patterns $policy.high_risk_patterns) {
                        $risk = "high"
                    } elseif (Contains-Any -text $tail -patterns $policy.low_risk_patterns) {
                        $risk = "low"
                    }

                    if ($risk -eq "low") {
                        Send-DecisionToWorker -decisionKey "y"
                        Write-Output ("[APPROVAL-AUTO] task=" + $TaskId + " worker=" + $WorkerName + " risk=low")
                        exit 0
                    }

                    $requestId = "APR-" + (Get-Date -Format "yyyyMMddHHmmss") + "-" + (Get-Random -Minimum 1000 -Maximum 9999)
                    $snippet = ($tailLines | Select-Object -Last 8) -join " | "
                    if ($snippet.Length -gt 500) {
                        $snippet = $snippet.Substring(0, 500)
                    }
                    $request = @{
                        id = $requestId
                        task = $TaskId
                        worker = $WorkerName
                        worker_pane_id = $WorkerPaneId
                        team_lead_pane_id = $TeamLeadPaneId
                        risk = if ($risk -eq "unknown") { "high" } else { $risk }
                        snippet = $snippet
                        status = "pending"
                        created_at = Get-Date -Format "o"
                        resolved_at = $null
                        decision = $null
                        resolved_by = $null
                    }
                    Save-ApprovalRequest -request $request

                    $body = "[APPROVAL_REQUEST] request_id=$requestId worker=$WorkerName pane=$WorkerPaneId risk=$($request.risk) snippet=$snippet"
                    $routeId = Append-RouteInbox -status "blocked" -body $body
                    Mark-TaskBlocked -note ("Approval required: " + $requestId)

                    Write-Output ("[APPROVAL-ESCALATED] request_id=" + $requestId + " route_id=" + $routeId + " task=" + $TaskId)
                    exit 0
                }
            }
        }
        Start-Sleep -Seconds $PollInterval
        $elapsed += $PollInterval
    }

    Write-Output ("[APPROVAL-TIMEOUT] No approval prompt after " + $Timeout + "s task=" + $TaskId)
    exit 1
} catch {
    Write-Output ("[APPROVAL-ERROR] " + $_.Exception.Message)
    exit 2
}
